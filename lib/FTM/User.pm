use strict;

package FTM::User;
use Moose;
use Carp qw(croak);

sub TRIGGERS { return [qw[
    get_ranking get_task_data update_task open_task add_task copy_task
    get_settings update_settings
]]; }

has _dbicrow => (
    is => 'ro',
    isa => 'FTM::FlowDB::User',
    required => 1,
    handles => [qw/
        user_id username email created salted_password password_equals
        find_related insert invite update in_storage extprivacy
    /],
    init_arg => "dbicrow",
);

has can_admin => (
    is => 'ro',
    isa => 'Bool',
    default => sub { 0 },
);

has can_login => (
    is => 'ro', isa => 'Bool',
    default => sub {
       my $row = shift->_dbicrow;
       $row &&= $row->mailoop or return 1;
       return $row->type ne 'invite';
    }
);

my $IS_INITIALIZED;

INIT {
    return if $IS_INITIALIZED;

    # we are used with "()", normally suppressing import call, but as we are
    # that important, we call it ourselves nevertheless:
    __PACKAGE__->import();

}

sub import {
    my ($class, $mode, $args) = @_;
    if ( $IS_INITIALIZED ) {
        croak "$class already initialized" if @_ > 1;
        return;
    }

    $mode = !$mode             ? 'Common'
          : $mode eq 'Backend' ? 'Interface' # Installed POE::Component::IKC?
          : $mode eq 'Proxy'   ? 'Proxy'
          :                      croak "Illegal $class mode: $mode"
          ;

    my $role = "FTM::User::$mode";

    if ( $args ) {
        eval "require $role" or die;
        $role->import(%$args);
    }

    with $role;

    $class->meta->make_immutable;
    $IS_INITIALIZED = 1;
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::User - Representation of a user, invocator and object of FlowgencyTM actions

=head1 SYNOPSIS

 my $user = FTM::User->new( dbicrow => $row ); # pass a FTM::FlowDB::User row

 my $name = $user->name;
 my %hash = $user->weights;

 $user->update({ name => $new_name });
 $user->tasks->...;
 $user->update_time_model(\%diff_data);
  
=head1 DESCRIPTION

Instances of this class provide proxy closures to be accessed by User::Tasks for
actions involving other entities than tasks.
 
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

