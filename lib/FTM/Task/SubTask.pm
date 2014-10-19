use 5.014;
use strict;

package FTM::Task::SubTask;
use Moose;
use Carp qw(croak);

extends 'FTM::Task';

has parent => ( is => 'ro', isa => 'FTM::Task', required => 1, weak_ref => 1 );

has task => (
    is => 'ro', isa => 'FTM::Task', # can => 'steps',
    required => 1, weak_ref => 1,
);

has '+dbicrow' => (
    default => sub { # called after clearer has been called
        my $self = shift;
        my $row = $self->task->steps->find({ name => $self->name });
        $row->_upper_subtask_row( $self->parent->dbicrow );
    },
    handles => ['main_step_row'], # -steps
);

sub BUILD {
    my ($self, $args) = @_;

    croak "task cannot be a FTM::Task::SubTask instance"
        if $self->task->isa("FTM::Task::SubTask");

    my ($dbicrow, $parent) = ($self->dbicrow, $self->parent);
    $dbicrow->_upper_subtask_row( $parent->dbicrow );

}

before ['store', '_init_subtasks', '_update_subtask_if_any'] => sub {
    croak "A FTM::Task::SubTask cannot do this operation";
};

__PACKAGE__->meta->make_immutable();

__END__

=head1 NAME

FTM::Task::SubTask = Unowned task row linked to a main_step that has a parent

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 COPYRIGHT

(C) 2012-2014 Florian Hess

=head1 LICENSE

This file is part of FlowTiMeter.

FlowTiMeter is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowTiMeter is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowTiMeter. If not, see <http://www.gnu.org/licenses/>.

