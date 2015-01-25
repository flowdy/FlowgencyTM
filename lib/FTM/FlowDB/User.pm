use strict;

package FTM::FlowDB::User;
use Digest::SHA qw(hmac_sha256_hex);
use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('user');
__PACKAGE__->add_columns(qw/
    user_id  password
    weights time_model priorities
/);

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
        my @chars = ( 0..9, "a".."z", "A".."Z" );
        my $random_string = join q{}, map { $chars[ int rand(62) ] } 1 .. 8;
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

1;
