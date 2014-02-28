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

has ['track_finder', 'flowrank_processor'] => (
    is => 'rw', isa => 'CodeRef', required => 1,
);

sub _build_task_obj {
    my ($self, $row) = @_;
    my $tpp = $self->track_finder;
    return Task->new(
        step_retriever => $self->step_retriever,
        dbicrow => $row,
        track_finder => sub {[ map { 
            my $track = $tpp->($_->track);
            { track => $track, until => $_->until };
        } @_ ]},
    );
}

sub _next_unused_name {
    my ($self, $prefix) = @_;
    my $search_expr = $prefix ? { like   => "$prefix%" }
                    :           { regexp => '^[0-9]+$' }
                    ;
    $name = $self->tasks->search(
        { name => $search_expr }, { columns => ['name'] }
    )->get_column('name')->max();

    $name =~ s{ (?<!\d) (\d*) \z }{ $1+1 }exms;

    return $name;
    
}

sub get {
    my ($self, $id) = @_;

    return $self->cache->{$id} ||= do {
        my $t = $self->task_rs->find($id) || return;
        $self->_build_task_obj($t);
    };
}

sub add {
    my ($self, $md_href) = @_;
    my $tasks_rs    = $self->task_rs;
    my $name = delete $md_href->{name}
            // $self->_next_unused_name(
                 delete $md_href->{incr_name_prefix}
               )
             ;
    
    my $row = $tasks_rs->new({ name => $name });
    my $task = $self->cache->{$row->name}
             = $self->_build_task_obj($row);

    $task->store($md_href);
    
    return $task;

}

sub copy {
    my ($self, $existing_task_name, $md_href) = @_;

    my $base_row = $tasks_rs->find($existing_task_name)
        // croak "No task with name $existing_task_name found";

    my $name = delete $md_href->{name}
            // $self->_next_unused_name($existing_task_name);

    return $self->cache->{$name}
         = $base_row->result_source->storage->txn_do(sub {
               my $t = $base_row->copy({ name => $name });
               $t = $self->_build_task_obj($t);
               $t->store($md_href);
               return $t;
         });
}

sub update {
    my ($self, $existing_task_name, $md_href) = @_;
    my $new_name = $md_href->{name};
    my $task = $self->cache->{$existing_task_name}
    $task->store($md_href);
    if ( $new_name ) {
        $self->cache->{$new_name} = delete $self->cache->{$existing_task_name};
    }
    return $task;
}

sub delete {
    my ($self, $name) = @_;
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

__END__

sub new_task { # do not use
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

