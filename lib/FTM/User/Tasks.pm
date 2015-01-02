use strict;

package FTM::User::Tasks;
use Moose;
use Carp qw(carp croak);
use FTM::Task;
use FTM::FlowDB::Task; # calling ->columns method
use FTM::FlowDB::Step; # on DBIx::ResultSources
use FTM::Util::TreeFromLazyStr;
use feature "state";

has task_rs => (
    is => 'ro',
    isa => 'DBIx::Class::ResultSet',
    required => 1,
    handles => ['search'],
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
    my $search_expr = $prefix ? { like   => "$prefix%" }
                    :           { regexp => '^[0-9]+$' }
                    ;
    my $name = $self->task_rs->search(
        { name => $search_expr }, { columns => ['name'] }
    )->get_column('name')->max() || $prefix || 0;

    $name =~ s{ (?<!\d) (\d*) \z }{ ($1||0)+1 }exms;

    return $name;
    
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
        for my $href ( $parser->parse($string) ) {
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

sub list {
    my ($self, %criteria) = @_;
    
    my ($desk, $tray, $drawer, $archive, $now)
        = delete @criteria{ 'desk', 'tray', 'drawer', 'archive', 'now' };

    $desk //= 1;
    if ( %criteria ) {
        $tray //= 1;
        $drawer //= 3;
        $archive //= ['done', 'cancelled', 'paused'];
    }
    else { $drawer //= 0 }

    $criteria{archived_because}
        = ref $archive eq 'ARRAY' ? { -in => $archive }
        : ref $archive ? croak "archive: not an array reference"
        : $archive
        ;

    $now = $now ? FTM::Time::Point->parse_ts( $now )->fill_in_assumptions
                : FTM::Time::Point->now;

    my $processor = $self->flowrank_processor;
    $processor->($now);
    my $rs = $self->task_rs;
    $rs->clear_cache;

    my (@on_desk, @in_tray, @upcoming, @in_archive);

    for my $task ( $rs->search(\%criteria)->get_column('name')->all ) {
        $task = eval { $self->get($task) }
                // die "Could not cache task $task: $@";
        next if !($drawer & 2) && $task->start_ts > $now;
        if ( $task->is_archived ) { push @in_archive, $task; }
        elsif ( $task->start_ts > $now ) {
            $drawer & 2 or next;
            push @upcoming, $task;
        }
        else { $processor->( $task, $drawer & 1 ); }
    }       

    my $list = $processor->();

    for my $task ( @$list ) {
        if ( $task->is_open ) {
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
                 $_->flowrank->score > $appendix or next;
                 push @on_desk, $_;
            }
        }
        else {
            # Because there are no open tasks on desk yet,
            # let's present all closed tasks so the user can
            # select the next task to open
            @on_desk = @in_tray;
        }
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

