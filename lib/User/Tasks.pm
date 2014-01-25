use strict;

package User::Tasks;
use Moose;
use Carp qw(carp croak);
use Task;

has task_rs => (
    is => 'ro',
    isa => 'DBIx::Class::ResultSet',
    required => 1,
);

has step_retriever => (
    is => 'ro',
    init_arg => undef,
    lazy => 1,
    default => sub {
        my $task_rs = shift->task_rs;
        sub {
            my ($task,$step) = @_;
            $task = $task_rs->find($task) // return;
            return $task if @_ == 1;
            return $task->steps->find($step);
        }
    },
);

has cache => (
    is => 'ro',
    isa => 'HashRef[Task]',
    init_arg => undef,
    default => sub {{}},
);

has ['time_profile_provider', 'flowrank_processor'] => (
    is => 'rw', isa => 'CodeRef', required => 1,
);

sub _build_task_obj {
    my ($self, $row) = @_;
    my $tpp = $self->time_profile_provider;
    return Task->new(
        step_retriever => $self->step_retriever,
        dbicrow => $row,
        profile_resolver => sub {[ map { 
            my $profile = $tpp->($_->profile);
            { profile => $profile, until => $_->until };
        } @_ ]},
    );
};

sub get_task {
    my ($self, $id) = @_;

    return $self->cache->{$id} ||= do {
        my $t = $self->task_rs->find($id) || return;
        $self->_build_task_obj($t);
    };
}

sub new_task {
    my ($self, $id, $copy_flag) = @_;
    my $task_rs = $self->task_rs;

    my ($r,$r_base);

    do { $r = $task_rs->find($id); } while $r
        && ($r_base ||= $r)
        && $id =~ s{ (?<!\d) (\d*) \z }{ $1+1 }exms;

    my $row =  $r_base && $copy_flag ? $r_base->copy({ name => $id })
                        : $copy_flag ? croak "No task found to copy: $id"
                                     : $task_rs->new({ name => $id })
                                     ;

    return $self->cache->{$row->name} = $self->_build_task_obj($row);

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
