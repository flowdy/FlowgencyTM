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
        tasks => $self,
    );
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
    
sub bind_tracks {
     my $self = shift;
     my @stages = ref $_[0] eq 'ARRAY' ? @{ shift @_ } : @_;
     my $tpp = $self->track_finder;
     for my $s ( @stages ) {
         my ($track, $until)
             = blessed($s) ? ($s->track, $s->until_date)
                           : @{$s}{'track', 'until_date'}
                           ;

         $track = $tpp->($track)
             // croak "Track not found: '$track'";

         $s = { track => $track, until_date => $until };

     }

     return @_ && wantarray ? @stages : \@stages;

}

sub _retrieve_task_step {
    my ($self, $task, $step) = @_;

    my $found = $self->tasks_rs->find($task)
        // croak "No task '$task' defined";
    $found = $found->substeps->find($step)
        // croak "Task '$task' has no step named '$step'";

    return $step;

}

sub link_step_row {
    my ($self, $step, $other) = @_;
    my ($other_task, $other_step)
        = $other ? @{$other}{'task', 'step'} : ();

    croak "hashref with 'task' and 'step' names missing"
        if !($other_task && $other_step);
    croak "Cannot establish links between steps of same task"
        if $step->task eq $other_task->id;

    return $step->link_row(
        $self->_retrieve_task_step($other_task, $other_step)
    );
}    

sub recalc_dependencies {
     my ($self, $task) = (shift, shift);
     my @links = map {[ $task, $_ ]} @_;

     my (%depending, $step, $link, $p, $str);

     while ( $link = shift @links ) {
         ($task,$step) = @$link;
         next if $depending{$task}{$step}++;

         $link = $self->_retrieve_task_step($task, $step);

         if ( $p = $link->parent_row ) {
             push @links, [ $p->task, $p->name ];
             if ( $str = $link->subtask_row ) {
                 $depending{$str->name}++;
             }
         }

         push @links, map {[ $_->task, $_->name ]}
                      $link->linked_by->all;

     }

     for my $task ( keys %depending ) {
         $self->get($task)->_clear_progress;
     }

     return;

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

