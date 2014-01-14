use strict;

package User::Tasks;
use Moose;
use Carp qw(carp croak);
use Task;
use Time::Cursor;

has task_rs => (
    is => 'ro',
    isa => 'DBIx::Class::ResultSet',
    required => 1,
);

has step_retriever => (
    is => 'ro',
    lazy => 1,
    init_arg => undef,
    default => sub {
        my $task_rs = shift->task_rs;
        sub {
            my ($task,$step) = @_;
            $task = $task_rs->find($task) // return;
            $step //= '';
            return $task->steps->find($step);
        }
    },
);

has cache => (
    is => 'ro',
    isa => 'HashRef[FlowDB::Task]',
    init_arg => undef,
    default => sub {{}},
);

has ['time_profile_provider', 'flowrank_processor'] => (
    is => 'rw', isa => 'CodeRef', required => 1,
);

sub get_task {
    my ($self, $id) = @_;

    my $tpp = $self->time_profile_provider;
    my $profile_resolver = sub {[ map { 
        my $profile = $tpp->($_->profile);
        { profile => $profile, until => $_->until };
    } @_ ]};

    return $self->cache->{$id} ||= do {
        my $t = $self->task_rs->find($id) || return;
        Task->new(
            cursor => Time::Cursor->new(
                timeprofiles => $profile_resolver->($t->timelines),
                run_from => $t->from_date,
            ),
            profile_resolver => $profile_resolver,
            step_retriever => $self->step_retriever,
            dbicrow => $t,
            id => $id,
            model => $self->model,
        );
    };
}

sub new_task {
    my ($self, $id, $copy_flag) = @_;
    my $task_rs = $self->task_rs;

    my $row = $id ? do {
        my ($r,$r_base);

        do { $r = $task_rs->find($id); } while $r
            && ($r_base ||= $r)
            && $id =~ s{ (?<!\d) (\d*) \z }{ $1+1 }exms;

        $r_base && $copy_flag ? $r_base->copy({ name => $id })
                 : $copy_flag ? croak "No task found to copy: $id"
                              : $task_rs->new({ name => $id })
                              ;

    } : $task_rs->new();

    return $self->cache->{$row->name} = Task->new(
        model => $self->model, dbirow => $row,
        step_retriever => $self->step_retriever,
        id => $id,
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
