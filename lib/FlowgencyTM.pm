use 5.014;
use strict;

package FlowgencyTM {
use Carp qw(croak);
use version; our $VERSION = qv("v0.9.0");
use FTM::Error;

sub import {
    # load FTM::User in the right mode
    my ($class, $mode, @args) = @_;
    require FTM::User;
    if ( FTM::User->class_already_setup ) {
        croak "FTM::User already initialized" if @_ > 1;
        return;
    }
    if ( !defined($mode) and my $string = $mode // $ENV{FLOWGENCYTM_MODE} ) {
        $mode = $string =~ s{^Backend:}{}i || $string =~ /:0$/       ? 'Backend'
              : $string =~ s{^Proxy:}{}i   || $string =~ /^[^a-z]+$/ ? 'Proxy'
              : croak "Environment variable FLOGENCYTM_MODE is invalid"
              ;
        push @args, $string;
    }
    FTM::User->import($mode, @args);
}

my ($db, %users, @current_users);

my %DEFAULT_USER_DATA = (
    password => '',
    priorities => q[{"pile":1,"whentime":2,"soon":3,"urgent":5}], 
    weights => q[{"priority":1,"drift":1,"due":-1,"open":1,"timeneed":1}],
    time_model => q[{"default":{"label":"Default track not yet configured (hence 24/7)","week_pattern":"Mo-Su@0-23","unmentioned_variations_from":["private"]},"private":{"label":"Off, i.e. urgency frozen","week_pattern":"Mo-Su@!0-23","default_inherit_mode":"impose"}}],
    extprivacy => 0,
);

my %ADMINS = map { $_ => 1 } split /\W+/, $ENV{FLOWGENCYTM_ADMIN};

sub database () {
    require FTM::FlowDB;
    $db //= FTM::FlowDB->connect($ENV{FLOWDB_SQLITE_FILE});
}

sub user {
    my ($user_id, $create_if_unknown) = @_;
    @_ or $user_id = $current_users[0]
                  // $ENV{FLOWGENCYTM_USER}
                  // return;

    my $retr = "find";

    my $data = { user_id => $user_id };
    if ( my $new = $create_if_unknown ) {
        $retr .= "_or_new";
        $data = {
            user_id => $user_id,
            %DEFAULT_USER_DATA,
            ref $new eq 'HASH' ? %$new :
                $new eq '1' ? ()       :
                croak "user: 2nd arg is $new. Must be either a hash-ref or 1",
        };
    }
    elsif ( defined $create_if_unknown ) {
        # user( $user_id => 0 ) to reset a user object

        my $i = _seek_user_in_queue($user_id);
        if ( defined $i ) {
            my $user = delete( $users{ splice @current_users, $i, 1 } );
            if ( $user->DOES('FTM::User::Proxy') ) {
                $user->dequeue_from_server;
            }
        }
        else { croak "no user $user_id cached" }

        return if !defined wantarray; # in void context, we do not regenerate
                                      # the user from its database record

    }

    my $user_obj = do {
        if ( my $u = $users{$user_id} ) {
            # Force re-fetch database row, otherwise we could risk that we work
            # with an older version of the data that has been changed by
            # another process in the meanwhile.
            $u->refetch_from_db if @_;
            $u;
        }
        else {
            $users{ $user_id } = FTM::User->new(
                dbicrow => database->resultset("User")->$retr($data)
                        // croak(qq{Could not find a user with id = '$user_id'}),
                can_admin => $ADMINS{$user_id} // 0,
            )
        }
    };

    if ( my $max_users = $ENV{MAX_USERS_IN_CACHE} ) {

        if ( $user_obj->in_storage ) {
            my $i = _seek_user_in_queue($user_id);
            unshift @current_users, splice @current_users, $i, 1;
        }
        else {
            unshift @current_users, $user_obj->user_id;
        }

        if ( (my $drop_count = $max_users - @current_users) < 0 ) {
            delete $users{ splice @current_users, $drop_count };
        }
    }
    else {
        $current_users[0] = $user_obj->user_id;
        %users = ( $user_id => $user_obj );
    }

    
    return $user_obj;

}

sub _seek_user_in_queue {
    my $user_id = shift;
    my $i;
    for ( $i = 0; $i < @current_users; $i++ ) {
        last if $user_id eq $current_users[$i];
    }
    return $i < @current_users ? $i : ();
}

sub new_user {
    my ($user_id, $data) = @_;
    $data //= {};
    my $invite = delete $data->{'-invite'};
    my $user_exists = [
        { user_id => $user_id },
        $data->{email} ? { email => $data->{email} } : ()
    ];
    my $rs = database->resultset("User");
    if ( $rs->search($user_exists)->count ) {
        FTM::Error::User::DataInvalid->throw(
            "A user with this id or email already exists"
        );
    }

    my $row = $rs->create({
        %DEFAULT_USER_DATA, user_id => $user_id, %$data
    });

    my $user = $users{$user_id} = FTM::User->new( dbicrow => $row );
    if ( $invite ) { $user->needs_to_confirm('invite'); }
    elsif ( !defined $invite ) {      
        unshift @current_users, $user->user_id;
    }

    return $user;
}


} 1;

__END__

=head1 NAME

FlowgencyTM - Basic entry functions

Not to be used directly, just the commons of the Browser and command line interface and, the script processor, too.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 COPYRIGHT

(C) 2012-2014 Florian Hess

=head1 LICENSE

This file is part of FlowgencyTM.

FlowgencyTM is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowgencyTM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowgencyTM. If not, see <http://www.gnu.org/licenses/>.

