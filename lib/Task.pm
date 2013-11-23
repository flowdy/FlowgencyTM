use strict;

package Task;
use Moose;
use Carp qw(carp croak);

has scheme => (
    is => 'ro',
    isa => 'Time::Scheme',
    required => 1,
);
    
has cursor => (
    is => 'ro',
    isa => 'Time::Cursor',
    required => 1,
    lazy => 1,
    builder => '_build_cursor',
);

has id => (
    is => 'ro',
    isa => 'ArrayRef',
    auto_deref => 1,
    required => 1,
);

has dbicrow => (
    is => 'ro',
    isa => 'FlowDB::Task', # which again is a DBIx::Class::Row
    handles => [qw[
        from_date until_date timeline client
        name title description priority
        main_step steps
    ]],
    init_arg => undef,
    builder => sub {
        my $self = shift;
        $self->step_retriever->($self->id)->task;
    },
);

has progress => (
    is => 'ro',
    isa => 'Num',
    clearer => '_clear_progress',
    builder => sub { shift->main_step->calc_progress },
    lazy => 1,
);

has step_retriever => (
    # used to retrieve a step by task and step label from entire resultset
    is => 'ro',
    isa => 'CodeRef',
    required => 1,
);

sub update {

    my $self = shift;
    my $args = @_ % 2 ? shift : { @_ };
 
    my $root = %$args == 1
             ? do {
                   my ($k) = keys %$args;
                   ($args) = values %$args;
                   $k;
               }
             : delete $args->{step};

    $args->{oldname} = $root;

    my $steps = $self->_update_flatten_substeps_tree($args);

    $self->result_source->storage->txn_do(
        \&_update_write_to_db => $self, $steps, $root
    );

    my @to_recalc;

    while ( my ($step, $args) = each %$steps ) {
        next if !grep defined($_), @{$args}{qw{ done checks exp_oftime }};
        push @to_recalc, $step;
    }

    return {
        tasks_to_recalc => [ $self->tasks_to_recalc(@to_recalc) ]
    };
}

sub _update_flatten_substeps_tree {
    my ($self, $args) = @_;

    $args->{_level} = 0;
    my @rec_path = $args;
    my %steps;
    my $steps_rs = $self->steps;
    my $is_ancestor = { _ancestor => 1 };

    { my $p = $args->{parent};
      my $n = $args->{oldname};

      my $pr = $p ? $steps_rs->find({ name => $p })
                 || croak "$n: No step $p to be a child of"
             : $steps_rs->find({ name => $n })->parent_row
             ;

      while ( $pr ) {
          $pr->name ne $n or croak "Cannot descend from myself: $n";
          $steps{$pr->name} = $is_ancestor;
      } continue { $pr = $pr->parent_row; }

    }

    while ( my $current = $rec_path[-1] ) {

        if ( my $attr = shift @{ $current->{substeps} // [] } ) {

            if ( !ref($attr) ) {
                $attr = { oldname => $attr };
            }

            $attr->{name} //= $attr->{oldname};
            my $substep = $attr->{oldname} // $attr->{name};

            if ( $substep and my $seen = $steps{$substep} ) {
                croak $seen->{_ancestor}
                    ? "$substep can't be ancestor and descendent at once"
                    : "$substep already subordinated to "
                      . ($seen->{parent} || "ROOT node")
                    ;
            }

            $steps{$substep} = $is_ancestor;

            croak "No step $substep associated to task ".$self->name
                if $substep and !$steps_rs->find($substep);

            if ( $attr->{pos} ) {
                carp "{position} is determined by position in substeps array"
            }
            else { $attr->{pos} = ++$current->{_substeps_processed}; }

            if ( $attr->{parent} ) {
                carp "{parent} is imposed from higher level - uninfluencable";
            }
            else { $attr->{parent} = $current->{name}; }

            $attr->{_level} = $current->{_level} + 1;

            push @rec_path, $attr;

        }
        else {

            if ( my $link = delete $current->{link} ) {
                $current->{link_row} = $self->step_retriever->($link);
            }

            for (qw( from_date until_date timeline client priority )) {
                my ($field,$value) = ($_, delete($current->{$_}) // next);
                $current->{subtask_row}{$field} = $value;
            }

            for my $c ( $steps{ delete $current->{oldname} } ) {
                croak "circularly referred to or multiple entry of $c->{name}"
                    if defined($c) && $c != $is_ancestor;
                $c = $current;
            }

            pop @rec_path;

        }

    }

    return \%steps;

}
    
sub _update_write_to_db {
    my ($self, $steps_upd_data, $root_step) = @_;

    my $row = $self->dbicrow;
    my $steps_rs = $row->steps;
    my %new_parents;

    my %steps2; # working copy to be rebuild on reentry
                # (e.g. database reconnection)
    while ( my ($step, $properties) = each %$steps_upd_data ) {
        $steps2{$step} = { %$properties };
    }

    my $root = $steps2{$root_step};

    if ( !length($root_step) ) {
        my $str = delete $root->{subtask_row};
        $row->update($str) if $str && %$str;
        croak "root step cannot have a parent"
            if $root->{parent};
    }
    elsif ( my $p = $root->{parent} ) {
        my $p_row = $steps_rs->find($p);
        my $pos = $root->{pos};
        my $siblings = $p_row->substeps;
        my $num_siblings = $siblings->count;
        if ( defined($pos) && $num_siblings >= $pos ) {
            my @later_sibs = $siblings->search({ pos=>{ '>=' => $pos } });
            $_->update({ pos => $_->pos+1 })
                for sort { $b->pos <=> $a->pos } @later_sibs;
        }
        else {
            $root->{pos} = $num_siblings + 1;
        }
    }
    else { die "No parent" }

    my @NON_DB_FIELDS = qw/ substeps _ancestor _level _substeps_processed /;

    while ( my $step = $steps_rs->next ) {

        if ( my $s = delete $steps2{ $step->name } ) {

            for my $p ($s->{parent}) {
                last if $steps_rs->find($s->{parent});

                # can't have a nonexisting row as a parent,
                # so let's reset it to NULL temporarily
                push @{$new_parents{$p}}, $step->name;
                $p = undef;

            }

            delete @{$s}{@NON_DB_FIELDS};
                # If we kept emptied array-ref substeps here, DBIx::Class
                # would think $step hasn't any and erase what has just been
                # or is yet to be updated.
                # _level is needed for rows to insert only (s.b)

            $step->update($s);

        }

        else {
            # Forget all substeps unmentioned in the hierarchy
            # given that DBIx::Class will delete their descendents with
            # cascade_delete => 1 set.
    
            my ($ar,$ah) = ($step,undef);
            until ( $ah ) { $ar = $ar->parent_row;
                $step->delete if ($ah = $steps2{$ar->name})
                              && $ah->{substeps}
                              ;
            }
    
        }
    
    }

    # In order to not violate foreign key constraint (task,parent/name)
    # we insert new steps one level after another.
    for my $s ( sort { $a->{_level} <=> $b->{_level} } values %steps2 ) {
        delete @{$s}{@NON_DB_FIELDS};
        $row->add_to_steps($s);
    }

    while ( my ($name,$substeps) = %new_parents ) {
        $steps_rs->search({ name => { in => $substeps } })
                ->update({ parent => $name })
                ;
    }

    is_link_valid($_) for $steps_rs->search({ link => { '!=' => undef }});

    $row->main_step_row( $steps_rs->find({ name => '' }) );

    if ( $row->in_storage ) {
        use Time::Point;
        
        my $cursor = $self->cursor->alter_coverage(
            $row->from_date, $row->until_date
        );

        $self->_clear_progress; # to be recalculated on next progress() call
        return $row->update;
    }
    elsif ( $self->cursor ) {
        return $row->insert;
    }
    else { die }

}

sub tasks_to_recalc {
     my $self = shift;
     my @links = @_;

     my $get_step = $self->step_retriever;
     my (%depending, $task, $step, $link, $p, $str);

     while ( $link = shift @links ) {
         ($task,$step) = @$link;
         next if $depending{$task}{$step}++;

         $link = $get_step->($task, $step);

         if ( $p = $link->parent_row ) {
             push @links, [ $p->task, $p->name ];
             if ( $str = $link->subtask_row ) {
                 $depending{$str->name}++;
             }
         }

         push @links, map {[ $_->task, $_->name ]}
                      $link->linked_by->all;

     }

     return keys %depending;

}

sub is_link_valid {
    my ($self) = @_;

    my $req_step = $self->link_row // return;

    croak "Steps may not be subtasks and links at the same time"
        if $self->subtask_row;

    croak "Can't have multiple levels of indirection/linkage"
        if $req_step->link;

    my %is_successor;
    $is_successor{ $_->name }++ for grep !$_->link, $self->and_below;
    my ($p,$ch) = ($self, $self);
    while ( $p = $p->parent_row ) {
        $is_successor{ $_->name }++ for $p->substeps->search({
            link => undef,
            pos => { '>=' => $ch->pos }
        }, { columns => ['name'] });
    } continue { $ch = $p; }

    my @conflicts = grep $is_successor{$_}, $req_step->prior_deps($self->name);
    if ( @conflicts ) {
        croak "Circular or dead-locking dependency in ",
            $self->dbicrow->name, " from ", $req_step->name, " to ",
            join ",", @conflicts;
    }

    return;         
}

sub __deprecated_calc_urgency { # DEPRECATED!
    use POSIX qw(LONG_MAX);
    my ($self,$time) = @_;

    my $E = 2.71828182845904523536028747135266249775724709;
        # Dunno why Euler's number, after all it is fascinating:
        # used as a base in the urgency scaler algorithm below
        # The higher the value you choose instead, the more tension and/or
        # the less remaining time lower prioritized tasks must have in order
        # to be ranked over those of higher priority.  

    my $done = $self->progress;
    my $prio = $self->priority;

    my %time_pos = $self->cursor->update($time//time);
    my $elapsed = $time_pos{pres_elapsed};
    my $avatime = $time_pos{pres_remaining};
    $elapsed /= $elapsed + $avatime;

    my $tension = $elapsed - $done;
    $tension /= 1 - $elapsed < $done ? $elapsed : $done;

    my $hours = int($avatime / 3600);
    my $seconds = $avatime % 3600;
    my $minutes = int( $seconds / 60 );
    $seconds %= 60;

    return {
        %time_pos,
        priority => $prio,
        elapsed => $elapsed,
        done => $done,
        remaining_time => sprintf('%d:%02d:%02d', $hours, $minutes, $seconds),
        tension => $tension,
        urgency => $elapsed == 1 ? LONG_MAX - $done / $prio
                 : $E ** ($prio + $tension * $prio) / (1-$elapsed)
        
    };
}

sub from_string {
    my ($self, $string, $num) = @_;
    my ($head, @substeps) = do {
        my $num = $num + 1;
        split /\s*\|$num\|\s*/, $string;
    };
    my ($ti, @md) = split /\s*\|\|\s*/, $head;
    my %md = from_string_parse_head($ti);
    for my $md ( @md ) {
        my $key = $md =~ s{ \A (\w+) : \s+ }{}xms ? $1
                : croak "Missing key in line \"$md\"";
        croak "Value for key $key already defined: $md{$key} at \"$md\""
            if defined $md{$key};
        $md =~ s{\\(\S+)}{"\"\\$1\""}eeg;
        my @multi = split / (?<!\d) \s* \| \s* (?!\d) /xms, $md; 
        $md{$key} = @multi == 1 ? $multi[0] : \@multi;
    }
    $md{substeps} = [ map { from_string($self, $_, $num+1) } @substeps ];
    return $num ? \%md : $self->update(%md);
}

sub from_string_parse_head {
    my ($head) = @_;

    my %data;

    # Recognize id string for the task
    if ( $head =~ s{ \s* = (\w+) }{}xms ) {
        $data{name} = $1;
    }

    # Recognize tags 
    if ( $head =~ s{ \s* \B # (\p{Alpha}\w+) }{}xms ) {
        push @{$data{tags}}, $1;
    }

    # Recognize from-date, time profile (or contiguous pairs of both) and the
    # deadline after all.
    my $date_rx = qr{\d[.\-\d]{,8}[\d.]\b};
    if ( $head =~
           s{ ( [a-z] \w+                   # id string of a time profile (tp)
              | $date_rx                    # date to be parsed by Time::Point
              | (?:,?(?:$date_rx:[^,\s]+))+ # ","-sep. pairs of from-date and tp
              )? --? ($date_rx)             # deadline date
            }{}xms
    ) {

        my @components = split /,/, $1//q{};
        if ( @components > 1 ) {
            for ( split /,/, $1 ) {
                my ($date, $tplabel) = split /:/, $_;
                $data{timeprofile_from}{$date} = $tplabel;
            }
        }
        elsif ( my $single = shift @components ) {
            if ( $single =~ /^\d/ ) {
                $data{timeprofile_from}{$single} = "DEFAULT";
            }
            else {
                $data{timeprofile} = $single;
            }
        }
    }
    
    $data{title} = $head;
    return %data;

}

sub _build_cursor {
    use Time::Cursor;
    my ($self) = @_;
    my $dbicrow = $self->dbicrow;
    my $timeline = $self->scheme->get($dbicrow->timeline);
    my $cursor = $timeline->get_cached_cursor($dbicrow->name);
    if ( !$cursor ) {
        $cursor = Time::Cursor->new({
            timeline => $timeline,
            run_from => $dbicrow->from_date, run_until => $dbicrow->until_date,
        });
        $cursor->timeline->register_cursor($dbicrow->name, $cursor);
    }
    return $cursor;
}
1;
