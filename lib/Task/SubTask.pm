use 5.014;
use strict;

package Task::SubTask;
use Moose;
use Carp qw(croak);

extends 'Task';

has parent => ( is => 'ro', isa => 'Task', required => 1, weak_ref => 1 );

has task => (
    is => 'ro', isa => 'Task', # can => 'steps',
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

    croak "task cannot be a Task::SubTask instance"
        if $self->task->isa("Task::SubTask");

    my ($dbicrow, $parent) = ($self->dbicrow, $self->parent);
    $dbicrow->_upper_subtask_row( $parent->dbicrow );

}

before ['store', '_init_subtasks', '_update_subtask_if_any'] => sub {
    croak "A Task::SubTask cannot do this operation";
};

__PACKAGE__->meta->make_immutable();

1;
