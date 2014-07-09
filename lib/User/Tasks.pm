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

has _task_interface_proxy => (
    is => 'ro',
    isa => 'CodeRef',
    lazy => 1,
    builder => '__build_task_interface_proxy',
    init_arg => undef,
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
    return Task->new(
        dbicrow => $row,
        callback_proxy => $self->_task_interface_proxy,
    );
}

sub __build_task_interface_proxy {
    my ($self) = @_;
    my %callback_for = (

        bind_tracks => sub {
            my $task = shift;
            my @stages = ref $_[0] eq 'ARRAY' ? @{ shift @_ } : @_;
            my $tpp = $self->track_finder;
            for my $s ( @stages ) {
                my ($track, $until)
                    = blessed($s) ? ($s->track, $s->until)
                                  : @{$s}{'track', 'until'}
                                  ;
                 $track = $tpp->($track)
                     // croak "Track not found: '$track'";
                 $s = { track => $track, until => $until };
            }
            return @_ && wantarray ? @stages : \@stages;
        },

        link_step_row => sub {
            my ($task, $step, $o) = @_;
            my ($otask, $ostep) = $o ? @{$o}{'task', 'step'} : ();
            croak "hashref with 'task' and 'step' names missing"
                if !($otask && $ostep);
            my $found = $self->tasks_rs->find($otask)
                // croak "No task '$otask' defined";
            $found = $found->substeps->find($ostep)
                // croak "Task '$otask' has no step of name '$ostep'"
            return $step->link_row($found);
        },    

    );

    return sub {
        my $name = shift;
        return $callback_for{ $name } //
            croak "callback not found: $name";
    };

}

sub _next_unused_name {
    my ($self, $prefix) = @_;
    my $search_expr = $prefix ? { like   => "$prefix%" }
                    :           { regexp => '^[0-9]+$' }
                    ;
    my $name = $self->tasks->search(
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

    my $base_row = $self->tasks_rs->find($existing_task_name)
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
    my $task = $self->get($existing_task_name);
    my $res_href = $task->store($md_href);
    if ( $new_name ) {
        $self->cache->{$new_name} = delete $self->cache->{$existing_task_name};
    }

    # Recalculate progress of depending tasks on next access of progress 
    for my $task ( @{$res_href->{task_to_recalc}} ) {
        $self->get($task)->clear_progress;
    }
    return $task;
}

sub delete {
    my ($self, $name) = @_;
    if ( my $task = delete $self->cache->{$name} ) {
        $task->dbirow->delete;
    }
    elsif ( my $row = $self->task_rs->find($name) ) {
        $row->delete;
    }
    else {
        carp "no task $name to delete";
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

