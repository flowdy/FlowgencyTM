use strict;

package FTM::FlowDB::User;
use Digest::SHA qw(hmac_sha256_hex);
use Moose;
use Carp qw(croak);
extends 'DBIx::Class::Core';

__PACKAGE__->table('user');
__PACKAGE__->add_columns(qw/
    user_id  password
    weights time_model priorities
/);

__PACKAGE__->add_column(extprivacy => {
    data_type => 'TINYINT',
    default_value => 0
});

__PACKAGE__->add_column('appendix' => {
    data_type => 'FLOAT',
    default_value => 0.1
});

__PACKAGE__->add_column($_ => {
    is_nullable => 1
}) for qw/username email/;

__PACKAGE__->add_column(created => {
    data_type => 'DATETIME',
    default_value => \'CURRENT_TIMESTAMP',
});

__PACKAGE__->set_primary_key('user_id');

__PACKAGE__->has_many(tasks => 'FTM::FlowDB::Task',
    'user_id',
);

__PACKAGE__->might_have(mailoop => 'FTM::FlowDB::Mailoop', 'user_id');

sub salted_password {
    my ($self, $password) = @_;
    if ( exists $_[1] ) {
        my $random_string = _randomstring(8);
        return $self->password(
            $random_string."//".hmac_sha256_hex($password, $random_string)
        );
    }
    else {
         my @ret = reverse split m{//}, $self->password;
         $ret[1] //= undef;
         return reverse @ret;
    }
}

sub password_equals {
    my ($self, $password) = @_;
    my ($salt, $stored_password) = split m{//}, $self->password, 2;
    return hmac_sha256_hex($password, $salt) eq $stored_password;
}

sub needs_to_confirm {
    my ($self, $type, $value, $token) = @_;

    if ( !defined $type && defined $value ) {
        $token //= $value;
    }

    # We take into account that requests requiring confirmation can overwrite
    # each other. Either the right token is past or other conditions must be
    # met. So, it may not happen that confirmation of reset passwords is sent
    # to an unverified mail address. 
    my $old_ml;
    if ( $old_ml = $self->mailoop ) {
        if ( defined $token ) {
            FTM::Error::User::ConfirmationFailure->throw(
                "Tokens are not identical"
            ) if $old_ml->token ne $token;
        }
        elsif (
            ($old_ml->type eq 'invite'
                && !defined $old_ml->request_date )
            || ($type && $type ne 'change_email'
                   && $old_ml->type eq 'change_email'
            )
        ) {
            FTM::Error::User::ConfirmationFailure->throw(
                "Existing user confirmation token cannot be overwritten.".
                " Please confirm it first by clicking the link sent by e-mail."
            );
        }
        $old_ml->delete;
    }
    elsif ( !$type ) {
        croak "No confirm token type passed (arg 1)";
    }
 
    $token = _randomstring(40);
    return $type ? $self->create_related( mailoop => {
                       type => $type, token => $token, value => $value,
                   })
                 : $old_ml
                 ;
}

sub sqlt_deploy_hook {
   my ($self, $sqlt_table) = @_;

   $sqlt_table->add_index(
        name => 'unique_mail',
        fields => ['email'],
        type => 'unique'
   );

}

my @chars = ( 0..9, "a".."z", "A".."Z" );
sub _randomstring {
    my ($length) = @_;
    return join q{}, map { $chars[ int rand(62) ] } 1 .. $length;
}

package FTM::Error::User::ConfirmationFailure;
use Moose;
extends 'FTM::Error';

1;
