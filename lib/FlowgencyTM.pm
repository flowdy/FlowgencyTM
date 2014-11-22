use strict;

package FlowgencyTM {
our $VERSION = '0.01';
use Carp qw(croak);
use FTM::FlowDB;
use FTM::User; # No, it is rather the user who use FlowgencyTM

my ($db, %users, $current_user);

my %DEFAULT_USER_DATA = (
    username => 'Yet Unnamed',
    password => '',
    priorities => q[{"pile":1,"whentime":2,"soon":3,"urgent":5}], 
    weights => q[{"priority":1,"drift":1,"due":-1,"open":1,"timeneed":1}],
    time_model => q[{"default":{"label":"24/7 workaholic? Please define a healthy time model","week_pattern":"Mo-So@0-23"},"private":{"label":"Task shall sleep, i.e. its urgency be frozen","week_pattern":"Mo-So@!0-23"}}],
);

sub database () {
    $db //= FTM::FlowDB->connect($ENV{FLOWDB_SQLITE_FILE});
}

sub user {
    my ($user_id, $create_if_unknown) = @_;
    return $current_user if !@_;

    my $retr = "find";

    my $data = { user_id => $user_id };
    if ( my $new = $create_if_unknown ) {
        $retr .= "_or_new";
        $data = {
            user_id => $user_id,
            %DEFAULT_USER_DATA,
            ref $new eq 'HASH' ? %$new :
            $new eq '1' ? ()           :
            croak "user: 2nd arg is $new. Must be either a hash-ref or 1",
        };
    }

    return $current_user = $users{$user_id} //= FTM::User->new(
        dbicrow => database->resultset("User")->$retr($data)
                // croak qq{Could not find a user with id = '$user_id'}
    );
}

sub new_user ($) {
    my ($username) = @_;
    my $user = $users{$username} = FTM::User->new(
        dbicrow => database->resultset("User")->create({
            %DEFAULT_USER_DATA, user_id => $username
        })
    );
    return $current_user = $user;
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

