use strict;

package User::Tasks;
use Moose;
use Carp qw(carp croak);
use Task;
use Time::Cursor;

has task_rs => (
    is => 'rw',
    isa => 'DBIx::Class::ResultSet',
    required => 1,
);

has cache => (
    is => 'ro',
    isa => 'HashRef[FlowDB::Task]',
    init_arg => undef,
    default => sub {{}},
);

has scheme => (
    is => 'rw',
    isa => 'Time::Scheme',
    required => 1,
);

sub get_task {
    my ($self, $id) = @_;
    return $self->cache->{$id} ||= do {
        my $t = $self->task_rs->find($id) || return;
        Task->new(
            cursor => Time::Cursor->new(
                timeline => $self->scheme->get($t->timeline)->timeline,
                run_from => $t->from_date,
                run_until => $t->until_date,
            ),
            dbirow => $t,
        );
    };
}

sub new_task {
    my ($self, $id, $copy_flag) = @_;
    my $task_rs = $self->task_rs;

    my $row = $id ? do {
        my ($r,$r_base);

        do { $r = $task_rs->find($id); }
          while $r && ($r_base ||= $r)
            && $id =~ s{ (?<!\d) (\d*) \z }{ $1+1 }exms;

        $r_base && $copy_flag ? $r_base->copy({ name => $id })
                 : $copy_flag ? croak "No task found to copy: $id"
                              : $task_rs->new({ name => $id)
                              ;

    } : $task_rs->new();

    return $self->cache->{$row->name} = Task->new(
        scheme => $self->scheme, dbirow => $row
    );

}

sub delete_task {
    my ($self, $id) = @_;
    if ( my $task = delete $self->cache->{$id} ) {
        $task->dbirow->delete;
    }
    elsif ( my $row = $self->task_rs->find($id) ) {
        $row->delete;
    }
    else {
        carp "no task $id to delete";
        return 0;
    }
    return 1;
}
    
1;
