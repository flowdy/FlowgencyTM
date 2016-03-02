package FTM::User::Common;
use strict;
use Moose::Role;
use FTM::Time::Model;
use FTM::FlowRank;
use JSON qw(from_json to_json);
use Carp qw(carp croak);
use FTM::Error;
use Try::Tiny;

has _time_model => (
    is => 'ro',
    isa => 'FTM::Time::Model',
    lazy => 1,
    init_arg => undef,
    handles => {
        dump_time_model => 'dump',
        get_available_time_tracks => 'get_available_tracks',
    },
    default => sub {
        my ($self) = shift;
        FTM::Time::Model->from_json($self->_dbicrow->time_model);    
    }
);

has cached_since_date => (
    is => 'ro',
    init_arg => undef,
    default => sub { FTM::Time::Spec->now },
);

has tasks => (
    is => 'ro',
    isa => 'FTM::User::Common::TaskManager',
    init_arg => undef,
    builder => '_build_tasks',
    handles => { 'get_task' => 'get', 'search_tasks' => 'search' },
    lazy => 1,
);

has weights => (
    is => 'ro',
    isa => 'HashRef[Int]',
    auto_deref => 1,
    lazy => 1,
    default => sub {
        return from_json(shift->_dbicrow->weights);
    },
);
    
has _priorities => (
    is => 'ro',
    isa => 'HashRef[Int|Str]',
    auto_deref => 1,
    lazy => 1,
    default => sub {
        my $href = from_json(shift->_dbicrow->priorities);
        my %ret;
        while ( my ($p, $n) = each %$href ) {
            croak "priority $p redefined" if $ret{"p:$n"};
            croak "ambiguous label for priority number $n" if $ret{"n:$p"};
            @ret{ "p:$n", "n:$p" } = ($p, $n);
        }
        return \%ret; 
    },
);

has appendix => (
    is => 'rw',
    isa => 'Num',
    lazy => 1,
    default => sub { shift->_dbicrow->appendix },
    trigger => sub {
        my ($self, $value) = @_;
        $self->_dbicrow->update({ appendix => $value });
    },
);

sub get_labeled_priorities {
    my ($self) = @_;
    my $p = $self->_priorities;
    my $ret = {};
    while ( my ($label, $num) = each %$p ) {
        $label =~ s{^n:}{} or next;
        $ret->{$label} = $num;
    }
    return $ret;
}

sub modify_weights {
    my ($self,%weights) = @_;
    my $w = $self->weights;
    while ( my ($key, $value) = each %weights ) {
        die "Unknown key: $key" if !exists $w->{$key};
        die "Not an integer: $key = $value" if $value !~ /^-?\d+$/;
        $w->{$key} = $value;
    }
    return $self->_dbicrow->update({ weights => to_json($w) });
}

sub remap_priorities {
    my ($self,@priorities) = @_;
    my (%p);
    while ( my ($key, $value) = splice @priorities, 0, 2 ) {
        die "Multiple labels for priority = $value" if exists $p{$value};
        die "Not an integer: $key = $value" if $value !~ /^-?\d+$/;
        $p{$key} = $value;
    }
    delete $self->{_priorities};
    return $self->_dbicrow->update({ priorities => to_json(\%p) });
}

sub update_time_model {
    my ($self, $args) = @_;
    my $tm = $self->_time_model;
    $tm->update($args) && $self->_dbicrow->update({
        time_model => $tm->to_json
    });
};

sub _parser { shift->tasks->get_tfls_parser; }

sub _build_tasks {
    my $self = shift;
    FTM::User::Common::TaskManager->new({
        track_finder => sub {
            $self->_time_model->get_track(shift);
        }, 
        flowrank_processor => FTM::FlowRank->new_closure({
            get_weights => sub { $self->weights }
        }),
        priority_resolver => sub {
            $self->_priorities->{ +shift };
        },
        appendix => sub { $self->appendix },
        task_rs => scalar $self->_dbicrow->tasks,
    });
}

sub get_ranking {
    my ($self, $data) = @_;
    my $now;
    if ( delete $data->{keep} ) {
        use POSIX qw(strftime);
        $now = FTM::Time::Spec->now(
            delete( $data->{now} ) || strftime(
                "%Y-%m-%d %H:%M:%S", localtime time
            )
        );
    }
    else { $now = $data->{now} }
  
    my @list = $self->tasks->list(%$data); 
    $now = ref($list[0]) ? $list[0]->flowrank->_for_ts : $now;
    for my $t ( @list ) {
        next if !ref $t;
        my $d = _dump_task($t);
        $t->uncouple_dbicrow;
        $t = $d;
    }
    return {
        list => \@list, timestamp => $now,
        tasks_count_total => $self->tasks->count,
    };
}

sub get_task_data {
    my ($self, $task, $steps) = @_[0,1];

    if ( ref $task eq 'HASH' ) {
        if ( my $t = $task->{task} ) {
            $task = $self->get_task($t);
        }
        elsif ( my $tfls = $task->{lazystr} ) {
            $task = $self->_parser->($tfls)->{task_obj};
        }
        elsif ( !%$task ) {
            $steps = $task = undef;
        }
        else {
            croak "No initial data supplied to get_task_data call";
        }
    }

    if ( $task ) {
        my %steps = map { $_->name => $_->dump }
                        $task->main_step_row,
                        $task->steps
        ;
        $steps = \%steps; 
    }

    my $priodir = $self->get_labeled_priorities;
    my $priocol = $self->tasks->task_rs
        ->search({ archived_because => undef })->get_column('priority');
    @{$priodir}{'_max','_avg'} = ($priocol->max, $priocol->func('AVG') );

    return
        steps => $steps, _priodir => $priodir,
        tracks => [ $self->get_available_time_tracks ],
        id => $task && $task->name,
}

sub __legacy_form_task_data {
    my ($self, $args) = @_;

    my $task;

    if ( defined( my $lazystr = $args->{lazystr} ) ) {
        $task = _parser($self)->($lazystr)->{task_obj};
    }
    else { $task = $self->get_task($args->{task}); }

    return $self->get_task_data($task);
}

sub fast_bulk_update {
    my ($self, $args) = @_;

    my ($status, %errors, @success);

    while ( my ($task, $data) = each %$args ) {

        my $tmp_name = $task =~ s/^(_NEW_TASK_\d+)$// && $1;

        my $method = $tmp_name ? 'add'
                   : $data->{copy} || $data->{incr_name_prefix} ? 'copy'
                   : ($data->{archived_because}//q{}) eq '!PURGE!' ? 'delete'
                   : 'update';

        $data->{step} //= '';

        try {
            $task = FlowgencyTM::user->tasks->$method($task || (), $data)
                and push @success, $task->name; # except for deleted tasks
        }
        catch {

            $status = index(ref($_), "FTM::Error::") == 0
                ? $status || 400
                :            500
                ;

            $errors{ $task || $tmp_name } = $_;

        };

    }

    if ( %errors ) {
        $errors{ $_ } //= q{} for @success;
        FTM::Error::Task::MultiException->throw(
            all => \%errors, http_status => $status,
        );
    }
    else {
        return @success;
    }

}

sub open_task {
    my ($task, $user) = (pop, pop);

    if ( $user ) {
        $task = $user->get_task($task->{id});
        $task->open;
    }
    
    if ( defined($task->is_open) ) {
        my @focus_steps = $task->archived_ts
            ? [ undef, $task->main_step_row ]
            : $task->current_focus
        ;
        for my $fs ( @focus_steps ) {
            my %h;
            @h{qw/ task_name name rendered_description checks done /} =
               map { $_->task_row->name, $_->name,
                     $_->description_rendered_if_possible, $_->checks, $_->done
               } $fs->[1];
            $fs->[1] = \%h;
        }
        return { focus => \@focus_steps }

    }
    else {
        return undef
    }

}

sub get_dynamics_of_task {
    my ($user, $args) = @_;

    my $task = $user->get_task($args->{id});
    my $flowrank = $task->flowrank;
    my ($max_level, $steps_tree) = $task->main_step_row->dump_tree;
    return {
        title => $task->title,
        flowrank => $flowrank ? $flowrank->dump : {},
        progress => $steps_tree,
        max_level => $max_level,
      # TODO:
      # - progress: step hierarchy, foreach step done, checks, total_ratio, expenditure
      # - time way: stages, spans and for each: net working and still seconds elapsed/remaining
    };
    
}

sub dump_complex_settings { my ($user) = @_; return
    weights => { $user->weights },
    priorities => $user->get_labeled_priorities,
    time_model => $user->dump_time_model,
}

sub realize_settings {
    my ($self, $settings) = @_;
    if ( my $prio = $settings->{'priorities'} ) {
        my (%prio,$i);
        for my $p ( split q{,}, $prio ) {
            $i++;
            next if !length $p;
            $prio{$p} = $i;
        }
        $self->remap_priorities(%prio) if %prio;
    }

    if ( defined(my $weights = $settings->{weights}) ) {
         $self->modify_weights(%$weights);
    }

    if ( defined(my $tm = $settings->{change_time_model}) ) {
        $self->update_time_model( $tm );
    }

    return;
}

use FTM::Util::LinearNum2ColourMapper;
use List::Util qw(min);

my @basecolor = (0,0xC0,0xff);

sub _dump_task {
    my ($task) = shift;
    return $task if !ref $task;
    my ($due, $next, $active, $score, $drift, $time_position) = $task->flowrank
        ? (map { $task->flowrank->$_ } qw(
              due_in_hms next_statechange_in_hms active score drift
              time_position
          ))
        : ()
        ;

    my $dump = {
        name => $task->name,
        title => $task->title,
        score => $score,
        priority => $task->priority,
        progressbar => _progress_bar(
            $task->progress, $drift, $active
        ),
        progress_pc => {
            checked_exp => $task->progress,
            time => $time_position,
        },
        duedate => $task->due_ts,
        startdate => $task->start_ts,
        $task->is_archived
          ? (
              archiveddate => $task->archived_ts,
              archived_because => $task->dbicrow->archived_because
            )
          : (),
        due_in_hms => $due,
        active => $active,
        $next && $due ne $next ? (next_statechange_in_hms => $next) : (),
        open_since => $task->open_since,
        extended_info => open_task($task),
            
    };

    return $dump;
}

sub extend_open_task {
    my ($task) = @_;

    return undef if !defined $task->is_open;

    my @fields = qw(description done steps pos);

    my @rows = $task->archived_ts ? [ undef, $task->main_step_row ]
             :                      $task->current_focus
             ;

    for my $ref ( @rows ) {
        my ($h,$l,$r) = ({}, @$ref);
        @{$h}{@fields} = map { $r->$_() } @fields;
        $h->{parent} = $r->parent_row->name;
        $h->{level} = $l;
        $ref = $h;
    } 

    return { focus => \@rows };
}

my $blender = FTM::Util::LinearNum2ColourMapper->new({
    '1' => [255,38,76],
    '0' => \@basecolor,
    '-1' => [51,255,64],
});

my $grey = [ hex(62), hex(53), hex(53) ]; 
my $paused_blender = FTM::Util::LinearNum2ColourMapper->new({
    '1' => $grey,
    '0' => [127,127,127],
    '-1' => $grey,
});

sub _progress_bar {
    my ($done, $rel_state, $active) = @_;
    my $orient = $rel_state > 0 ? "right" : "left";
    my $other_opacity = 1 - abs($rel_state);
    my $blender = $active ? $blender : $paused_blender;
    
    return {
        primary_color => scalar $blender->blend($rel_state),
        orientation => $orient,
        primary_width => sprintf("%1.0f%%", ($rel_state > 0 ? 1-$done : $done) * 100),
        secondary_color => sprintf 'rgba(%d,%d,%d,%f)', $active ? @basecolor : @$grey, $other_opacity,
    }

}

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

=cut

package FTM::User::Common::TaskManager;
use Moose;
use Carp qw(carp croak);
use FTM::Task;
use FTM::FlowDB::Task; # calling ->columns method
use FTM::FlowDB::Step; # on DBIx::ResultSources
use FTM::Util::TreeFromLazyStr;
use List::Util qw(max);
use feature "state";

has task_rs => (
    is => 'ro',
    isa => 'DBIx::Class::ResultSet',
    required => 1,
    handles => ['search', 'count'],
);

has cache => (
    is => 'ro',
    isa => 'HashRef[FTM::Task]',
    init_arg => undef,
    default => sub {{}},
);

has ['track_finder', 'flowrank_processor', 'priority_resolver', 'appendix' ] => (
    is => 'rw', isa => 'CodeRef', required => 1,
);

sub _build_task_obj {
    my ($self, $row) = @_;
    return FTM::Task->new(
        dbicrow => $row,
        _tasks => $self,
    );
}

sub _next_unused_name {
    my ($self, $prefix) = @_;
    $prefix //= q{};
    my $min = max(
        $prefix =~ s{ 0* (\d+) \z }{}xms ? $1 : 0,
        $self->task_rs->search(
            [ \qq{rtrim(me.name,"0123456789")=='$prefix'} ],
            { select => [ \qq{CAST(replace(me.name,'$prefix','') AS INT)} ],
              as => ['number'],
            }
        )->get_column('number')->max() || 0,
    );

    return $prefix.($min+1);
    
}

sub get {
    my ($self, $name) = @_;

    return $self->cache->{$name} ||= do {
        my $t = $self->task_rs->find({ name => $name }) || return;
        $self->_build_task_obj($t);
    };
}

sub add {
    my ($self, $md_href) = @_;
    my $tasks_rs    = $self->task_rs;
    my $name = $md_href->{name} // $self->_next_unused_name(
        delete $md_href->{incr_name_prefix}
    );
    
    my $row = $tasks_rs->new({ name => $name });
    my $task = $self->cache->{$row->name}
             = $self->_build_task_obj($row);

    $md_href->{from_date} //= 'now';
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

    if ( $task->is_archived ) {
        delete $self->cache->{ $task->name };
    }

    return $task;
}

sub delete {
    my ($self, $name) = @_;
    if ( my $task = delete $self->cache->{$name} ) {
        $task->dbicrow->delete;
    }
    elsif ( my $row = $self->task_rs->find({ name => $name }) ) {
        $row->delete;
    }
    else {
        carp "no task $name to delete";
        return;
    }
    return;
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

     return wantarray ? @stages : \@stages;

}

sub _retrieve_task_step {
    my ($self, $task_id, $step_name) = @_;

    my $found = $self->task_rs->find({ name => $task_id })
        // croak "No task with ID='$task_id' found in database";

    $found = $found->steps->find({ name => $step_name })
        // croak "FTM::Task '$task_id' has no step named '$step_name'";

    return $found;

}

sub link_step_row {
    my ($self, $step, $other) = @_;
    my ($other_task, $other_step)
        = ref $other ? @{$other}{'task', 'step'} : split /[.:\/>]/, $other||'', 2;

    $other_step //= '';

    croak "task part is missing" if !$other_task;

    my $req_step = $self->_retrieve_task_step($other_task, $other_step);

    FTM::Error::Task::InvalidDataToStore->throw(
        "Step to link couldn't be resolved: $other_task/$other_step"
    ) if !$req_step;

    FTM::Error::Task::InvalidDataToStore->throw(
        "Cannot establish links between steps of same task"
    ) if $step->task_id eq $req_step->task_id;
    
    FTM::Error::Task::InvalidDataToStore->throw(
        "Can't have multiple levels of indirection/linkage"
    ) if $req_step->link_id;

    my %is_successor;
    $is_successor{ $_->name }++ for grep { !$_->link_id }  $step->and_below;
    my ($p,$ch) = ($step) x 2;
    while ( $p = $p->parent_row ) {
        my $pos = $ch->pos;
        $is_successor{ $_->name }++ for $p->substeps->search({
            link_id => undef,
            $pos ? ( pos => [ undef, { '>=' => $pos } ] ) : (),
        }, { columns => ['name'] });
    } continue { $ch = $p; }

    my @conflicts
        = grep { $is_successor{$_} } $req_step->prior_deps($step->name);
    if ( @conflicts ) {
        FTM::Error::Task::InvalidDataToStore->throw(
            "Circular or dead-locking dependency from ",
            $req_step->name, " to " . join ",", @conflicts
        );
    }

    $step->link_row($req_step);         

}    

sub recalculate_dependencies {
     my ($self, $task) = (shift, shift);
     my @links = map {[ $task->name, $_ ]} @_;

     my (%depending, $step, $link, $p, $str);

     while ( $link = shift @links ) {
         ($task,$step) = @$link;
         next if $depending{$task}++;

         $link = $self->_retrieve_task_step($task, $step);

         if ( $p = $link->parent_row ) {
             push @links, [ $p->task_row->name, $p->name ];
         }

         push @links, map {[ $_->task_row->name, $_->name ]}
                      $link->linked_by->all;

     }

     for my $task ( keys %depending ) {
         $self->get($task)->clear_progress;
     }

     return;

}

sub get_tfls_parser {
    my ($self, %opts) = @_;
    my $dry_run = delete $opts{'-dry'};
    my $common_modifier = delete $opts{'-modifier'} // sub {};
    my $parser = FTM::Util::TreeFromLazyStr->new({
        create_twig => \&_parse_taskstep_title,
        finish_twig => \&_finish_step_data,
        allowed_leaf_keys => [
            FTM::FlowDB::Task->columns, FTM::FlowDB::Step->columns,
            qw(incr_name_prefix timestages order)
        ],
        leaf_key_aliases  => { 'until' => 'timestages' },
        %opts
    });

    return $dry_run ? $parser : (), sub {
        my ($string, $modifier) = @_;
        @_ > 1 or $modifier = $common_modifier;
        my @tasks;
        my @defs = wantarray ? scalar $parser->parse($string)
                 : $parser->parse($string);
        while ( my $href = shift @defs ) {
            $modifier->() for $href;
            if ($dry_run) { push @tasks, $href; next }
            my ($name, $copy) = @{$href}{'name','copy'};
            my $task;
            if ( $copy ) {
                delete @{$href}{'name','copy'};
                $task = $self->copy( $name => $href );
            }
            elsif ( $name and $task = $self->get($name) ) {
                if ( $href->{step} ) {
                    if ( my $name = delete $href->{rename_to} ) {
                        $href->{name} = $name;
                    }
                    else { 
                        delete $href->{name};
                    }
                }
                $task->store($href);
            }
            else {
                $task = $self->add($href);
            }
            $href->{task_obj} = $task;
            push @tasks, $href;
        }
        return wantarray ? @tasks : $tasks[-1];
    };

}

sub _parse_taskstep_title {
    my ($head, $parent, $leaves) = @_;

    my %data;

    # Recognize id string for the task/step
    if ( $head =~ s{ \s* (= (\w+)) \s* }{}gxms ) {
        $data{name} = $2 if $2;
        if ( $head =~ s{ \G \. ([\w.]+) }{}xms ) {
            if ( $parent ) { $data{name} .= ".$1"; }
            else {
                $data{ 'step' } = $1;
                if ( my $name = delete $leaves->{name} ) {
                    $leaves->{rename_to} = $name;
                }
            }
        }
    }

    # Recognize a link
    if ( $head =~ s{ \G \s* (?: > (\w+) \. (\w+) ) \s* }{}xms ) {
        $data{link} = [ $1, $2 ];
    }

    # Recognize tags 
    while ( $head =~ s{ \s* \# (\p{Alpha}:?\w+) }{}gxms ) {
        push @{$data{tags}}, $1;
    }

    return { oldname => $head } if !%data and $head =~ /^[a-z]\S+$/;

    if ( $head ) {
        s/^\s+//, s/\s+$// for $head;
        my $slot = $parent || $data{step} ? 'description' : 'title'; 
        $data{$slot} = $head;
    }

    $data{parents_name} = $parent->{name} // '(anonymous parent)'
        if $parent;
    
    while ( my ($key, $leaf) = each %$leaves ) {
        croak "Key exists: $key" if exists $data{$key};
        $data{$key} = $leaf;
    }

    if ( my $o = $data{order} ) {
        $parent->{_substeps_order} = $o;
    }
    elsif ( $parent and $o = $parent->{_substeps_order} ) {
        $data{order} = $o;
    }
    else {}

    if ( my $t = $data{timestages} ) {
        my @timestages;
        for my $t ( ref $t ? @$t : $t ) {
            my ($ud, $track) = split /\s*@\s*|\s+(?!\d)/, $t;
            push @timestages, { until_date => $ud, track => $track // 'default' }
        }
        $data{timestages} = \@timestages;
    }

    return \%data;

}

sub _finish_step_data {
    my $hash = $_; shift;
   
    my (@ordered, @unordered);
    for my $part ( @_ ) {
        my $name = delete $part->{name}
                // croak "Step has no name: "
                   . ($part->{title} // $part->{description});

        # Suck and gather all descendents into a top-level hash.
        if ( my $steps = delete $part->{steps} ) {
            while ( my ($name, $data) = each %$steps ) {
                croak "Step $name defined already"
                    if exists $hash->{steps}{$name};
                $hash->{steps}{$name} = $data;
            }
        }

        my $r;
        for my $o ( lc( delete $part->{order} // 'any' ) ) {
            push @{ $o eq 'any' ? \@unordered
                  : $o eq 'nx'  ? do { $r = []; push @ordered, $r; $r } 
                  : $o eq 'eq'  ? $r : croak "unsupported order: $o"
            }, $name;
        }

        croak "Step $name defined already" if exists $hash->{steps}{$name};
        $hash->{steps}{$name} = $part;
    }
    
    if ( @ordered || @unordered ) {
        $hash->{substeps} = join ';',
                                join( q{,}, map { join q{|}, @$_ } @ordered ) || '',
                                join( q{|}, @unordered) || ()
                          ;
    }

    delete @{$hash}{qw/parents_name _substeps_order/};

    return;
}

my %MAP_FIELDS = (
    'name' => ['me.name','steps.name'],
    '*' => [qw[me.name title steps.name steps.description]],
    description => [ 'steps.description' ],
    title => [ 'title' ],
    stepname => [ 'steps.name' ],
);

for my $f ( keys %MAP_FIELDS ) {
    my $fields = $MAP_FIELDS{$f};
    while ( substr $f, -1, 1, "" ) {
        if ( delete $MAP_FIELDS{ $f } ) { next; }
        $MAP_FIELDS{$f} = $fields;
    }
}

sub list {
    my ($self, %criteria) = @_;
    
    my ($desk, $tray, $drawer, $archive, $now)
        = delete @criteria{qw[ desk tray drawer archive now ]};

    my %force_include;
    if ( my $tasknames = delete $criteria{force_include} ) {
        %force_include = map { $_ => 1 } @$tasknames;
    }

    $desk //= 1;
    if ( %criteria ) {
        $tray //= 1;
        $drawer //= 3;
        $archive //= { -not_in => [] };
    }
    else { $drawer //= 0 }

    $archive &&= ref $archive eq 'ARRAY' ? { -in => $archive }
               : ref($archive) !~ m{^($|HASH)} ?
                     croak( "archive: neither ARRAY nor HASH reference" )
               : $archive eq "1" ? { -not_in => [] }
               : $archive
               ;

    my @and_search = ({ archived_because => $archive });

    for my $hash ( _query( delete $criteria{query} // q{} ) ) {
        @criteria{ keys %$hash } = values %$hash;
    }

    while ( my ($field, $value) = each %criteria ) {
        my $fields = $MAP_FIELDS{$field} //
            croak "No field $field supported (shortened ambiguously?)";
        for my $term ( ref $value ? @$value : $value ) {
            $term = { -like => "%$term%" };
            push @and_search, [ map {{ $_ => $term }} @$fields ];
        }
    }

    $now = $now ? FTM::Time::Spec->parse_ts( $now )->fill_in_assumptions
                : FTM::Time::Spec->now;

    my $processor = $self->flowrank_processor;
    $processor->($now);
    my $rs = $self->task_rs;
    $rs->clear_cache;

    my (@on_desk, @in_tray, @upcoming, @in_archive);

    my %cond = ( -and => \@and_search );
    my $opts = { join => 'steps', distinct => '1' };

    for my $task ( $rs->search(\%cond,$opts)->get_column('name')->all ) {
        $task = eval { $self->get($task) }
                // die "Could not cache task $task: $@";
        next if !($drawer & 2) && $task->start_ts > $now;
        if ( $task->is_archived ) { push @in_archive, $task; }
        elsif ( $task->start_ts > $now ) {
            $drawer & 2 or next;
            push @upcoming, $task;
        }
        else {
            my ($f) = map { $_ && $_-- } $force_include{ $task->name };
            $processor->( $task, $f || $drawer & 1 );
        }
    }       

    my $list = $processor->();

    while ( my $task = shift @$list ) {
        if ( defined $task->is_open ) {
            push @on_desk, $desk ? @in_tray : (), $task;
            @in_tray = () if $desk;
        }
        else {
            push @in_tray, $task;
        }
    }

    if ( !$tray ) {
        if ( my $last_on_desk = $on_desk[-1] ) {
            my $top_score = $on_desk[0]->flowrank->score;
            my $lowest_score  = $last_on_desk->flowrank->score;
            my $appendix = $top_score ? $lowest_score - (
                             ( $top_score - $lowest_score )
                               * $self->appendix->()
                           )
                         : - 1;
            for ( @in_tray ) {
                 next if !(
                     $_->flowrank->score > $appendix 
                     || defined $force_include{$_->name}
                 );
                 push @on_desk, $_;
            }
        }
        else {
            # Because there are no open tasks on desk yet,
            # let's present all closed tasks so the user can
            # select the next task to open
            $tray = $desk;
        }
    }
 
    for my $task ( keys %force_include ) {
        next if !$force_include{$task};
        $task = eval { $self->get($task) }
               // die "Could not cache task $task: $@";
        push @{
            $task->start_ts > $now ? \@upcoming
          : $task->is_archived     ? \@in_archive
          : die "Task neither upcoming nor archived, nor processed by FlowRank"
        }, $task;
    }

    return $desk ? @on_desk : (),
           $tray ? @in_tray : (),
           @upcoming ? ('upcoming',
                   sort { $a->start_ts <=> $b->start_ts } @upcoming
               ) : (),
           @in_archive ? ('archived',
                   reverse sort { $a->archived_ts cmp $b->archived_ts }
                   @in_archive
               ) : ()
        ;

}

sub _query {
    my ($text) = @_;
    my %query;
    my ($QUOTES, $ANY) = (q{"'}, q{*});
    my $field = $ANY;
    my $fld_single;
    while ( length $text ) {

        my $unquoted = q{};

        if ( $text =~ m{(?<!\\)[$QUOTES]}g ) {
            $unquoted = substr $text, 0, pos($text)-1, q{};
        }
        else {
            $unquoted = $text;
            $text = '';
        }
        $unquoted =~ s{\\([$QUOTES])}{$1}g;

        for my $part ( split /(?<=\s)(?=\S)/, $unquoted ) {

            if ( $part =~ s{\A (\w+): }{}xms ) {
                $field = $1;
                $fld_single = 1;
            }

            if ( $part =~ m{(\S+)} ) {
                push @{$query{$field}}, $part;
                $field = $ANY if $fld_single;
            }
            elsif ( length $part ) {
                $fld_single = 0;
            }

        }
            
        last if !length $text;

        pos($text) = 0;

        if ( my $quoted = extract_delimited($text, $QUOTES) ) {
            substr $quoted, $_, 1, q{} for 0, -1;
            push @{$query{$field}}, $quoted;
            $field = $ANY if $fld_single;
            $fld_single = 0;
        }
        else {
            die "Syntax error in query string ($text): Mismatching quote pairs";
        }

    }

    return \%query;

}


__PACKAGE__->meta->make_immutable();

__END__

=head1 NAME

FTM::User::Tasks - Set of all tasks by a user

=head1 SYNOPSIS

 my $user = ...; # get a FlowgencyTM user object
 my $tasks = $user->tasks;
 
 my $known_task = $tasks->get("name_of_known_task");
 my $known_task = $tasks->update("name" => \%data);
 my $new_task = $tasks->add("new_name_or_prefix" => \%data);
 my $new_task = $tasks->copy("name_of_known_task" => \%data);
 $tasks->delete("name_of_known_task");

 # TODO as of Sep 9 2014:
 $tasks->list(
     desk => 0|1,     # open tasks best to do right now. default: 1
                      #   includes closed tasks more or insignificantly less 
                      #   urgent than the least urgent open task.
     tray => 0|1,     # tasks that are active but temporarily closed. default: 0
     drawer => 0-3,   # 1: paused pending tasks, 2: future tasks, 3: both
                      #   defaults to 0
     archive => 0|1,  # done, stopped or paused tasks. Defaults to 0
     $field_1 => ..., # passed through to DBIx::Class search
     $field_2 => ..., #   will switch all defaults to 1 (or 3, respectively)
 );
         
=head1 DESCRIPTION

FTM::User::Tasks enables a user to create tasks and provides access to existing ones retrieved on demand from the user's FTM::FlowDB::Task resultset. It stores FTM::Task objects along with their initialized time cursors and database objects. It can be used to update the task metadata and to delete tasks as well.

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

