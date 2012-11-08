use strict;

package Task;
use Moose;
use Carp qw(carp croak);

has scheme => (
    is => 'ro',
    isa => 'Time::Scheme'
    required => 1,
}
    
has cursor => (
    is => 'ro',
    isa => 'Time::Cursor',
    required => 1,
    lazy => 1,
    builder => sub {
        use Time::Cursor;
        my $dbicrow = $self->dbicrow;
        return Time::Cursor->new({
            timeline => $self->scheme->get($dbicrow->timeline)->timeline,
            run_from => $dbicrow->from_date, run_until => $dbicrow->until_date,
        });
    }
);

has dbicrow => (
    is => 'ro',
    isa => 'FlowDB::Task', # which again is a DBIx::Class::Row
    required => 1,
    handles => [qw[
        from_date until_date timeline client
        name title description priority
        main_step steps
    ]],
);

has done_rate => (
    is => 'ro',
    isa => 'Num',
    clearer => '_clear_done_rate',
    builder => sub { shift->main_step->done_rate }
    lazy => 1,
);

has step_retriever => (
    # used to retrieve a step by task and step label from entire resultset
    is => 'ro',
    isa => 'CodeRef',
    required => 1,
}

sub update {
    my $self = shift;
    my $args = @_ % 2 ? shift : { @_ };
 
    my $step = %$args == 1
             ? do {
                   my ($k) = keys %$args;
                   ($args) = values %$args;
                   $k;
               }
             : delete $args->{step};

    my $row = $self->dbicrow;
    my @TASK_COLUMNS = qw(from_date until_date timeline client priority);
    $args->{oldname} = $step;

    unless ( $args->{name} ||= $step || q{} ) {

        for my $field (@TASK_COLUMNS) {
            $row->$field(delete($args->{$field}) // next);
        }

        if ( $row->in_storage and my $cursor = $self->cursor ) {
            use Time::Point;
            my %ts;
            $ts{$_} = Time::Point->parse_ts($row->$_)
               for qw(from_date until_date);
            if ( $ts{from_date}->fix_order($ts{until_date}) ) {
                $cursor->run_from($ts{from_date});
                $cursor->run_until($ts{until_date});
            }
            else {
                $cursor->run_until($ts{until_date});
                $cursor->run_from($ts{from_date});
            }
        }

        else { croak 'No cursor' if !$cursor }

    }

    my $step_rs = $self->steps;

    if ( my $p = $args->{parent} ) {

        if ( my $p_row = $step_rs->find($p) ) {

            my $pos = $args->{pos};
            my $siblings = $p_row->substeps;
            my $num_siblings = $siblings->count;
            if ( defined $pos and $num_siblings >= $pos
              and my @later_sibs = $siblings->search({ pos=>{ '>=' => $pos } })
               ) {
                $_->update({ pos => $_->pos+1 })
                    for sort { $b->pos <=> $a->pos } @later_sibs;
            }
            else {
                $args->{pos} = $num_siblings + 1;
            }

        }
        else {
            croak "No row $p to be a child of";
        }           

    }

    $args->{_level} = 0;
    my @rec_path = $args;
    my %steps;

    while ( my $current = $rec_path[-1] ) {
        my $substeps = $current->{substeps};
        my $substep;

        for my $l ($current->{link}//()) {
            $l &&= $self->get_noncircular_link_rowid($l, \@rec_path);
        }

        if ( $substeps and $substep = shift @$substeps ) {

            if ( my $seen = $steps{$substep} ) {
                croak "$substep already subordinated to ".$seen->{parent};
            }

            my $attrs = ref $substeps->[0] ? shift @$substeps : {};
            croak "No step $substep associated to task ".$self->name
                if !%$attrs and !$step_rs->find($substep);

            $attr->{oldname} = $substep;
            $attr->{name} //= $attr->{oldname};

            if ( $attr->{pos} ) {
                carp "{position} is determined by position in substeps array"
            }
            else { $attr->{pos} = ++$current->{_substeps_processed}; }

            if ( $attr->{parent} ) {
                carp "{parent} is imposed from higher level - uninfluencable";
            }
            else { $attr->{parent} = $current->{oldname}; }

            $attr->{_level} = $current->{_level} + 1;

            push @rec_path, $attr;

        }
        else {

            for ( @TASK_COLUMNS ) {
                my ($field,$value) = ($_, delete($current->{$_}) // next);
                $current->{subtask_row}{$field} = $value;
            }

            delete $current->{_substeps_processed};

            for my $c ( $steps{ delete $current->{oldname} } ) {
                croak "circularly referred to or multiple entry of $c->{name}"
                    if defined $c;
                $c = $current;
            }

            pop @rec_path;

        }

    }
    
    my %new_parents;

    while ( my $step = $step_rs->next ) {

        if ( my $s = delete $steps{ $step->name } ) {

            for my $p ($s->{parent}) {
                next if $steps_rs->find($s->{parent});

                # can't have a nonexisting row as a parent,
                # so let's reset it to NULL temporarily
                push @{$new_parents{$p}}, $step->name;
                $p = undef;

            }
            delete @{$s}{'substeps', '_level'};
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
                $step->delete if ($ah = $steps{$ar->name})
                              && $ah->{substeps}
                              ;
            }

        }

    }

    # In order to not violate foreign key constraint (task,parent/name)
    # we insert new steps one level after another.
    for my $s ( sort { $a->{_level} <=> $b->{_level} } values %steps ) {

        if ( $s->{substeps} and my @rem = @{$s->{substeps}} ) {
            die "Eh? There are substeps left unprocessed: ", join ',', @rem;
        }

        delete @{$s}{'substeps', '_substeps_processed', '_level'};
        $row->add_to_steps($s);

    }

    while ( my ($name,$substeps) = %new_parents ) {
        $step_rs->search({ name => { in => $substeps } })
                ->update({ parent => $name })
                ;
    }

    $self->_clear_done_rate; # to be recalculated next done_rate() call

    return $row->update_or_create();
}

sub get_noncircular_link_rowid {
    my ($self, $link, $path) = @_;
 
    my ($ftask, $fstep) = m{ \A (\w+) (?:\W (\w+))? \z }xms;

    my $req_step = $self->step_retriever->($ftask, $fstep);

    croak "Can't have multiple levels of indirection/linkage"
        if $req_step->link;

    my %is_successor;
    $is_successor{ $_ } = 1 for map {
        my $c = $_->{substeps};
        $c ? map { $_->{oldname} // () } @$c : ();
    } reverse @$path;

    if ( my $p = $path->[0]->{parent} ) {
        $p = $step_rs->find($p)
            // die "Parent not found (should've been checked for)";
        $is_successor{ $_->name } = 1
            for map { $_->and_below() } $p->substeps->search(
                { link => undef, pos => { '>' => $path->[0]->{pos} } }
            )
        ;
    }

    my @conflicts = grep $is_successor{$_}, $req_step->prior_deps($task->name);
    if ( @conflicts )
        croak "Refuse to build circular dependency in ",
            $self->dbicrow->name, " from ", $req_step->name, " to ",
            join ",", @conflicts;
    }

    return $req_step->ROWID;         
}

sub calc_urgency {
    use POSIX qw(LONG_MAX);
    my ($self,$time) = @_;

    # Dunno why Euler's number, after all it is fascinating:
    # used as a base in the urgency scaler algorithm below
    my $E = 2.71828182845904523536028747135266249775724709;

    my $done = $self->done_rate;
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
        urgency => $elapsed == 1 ? $LONG_MAX - $done / $pri
                 : $E ** ($prio + $tension * $prio) / (1-$elapsed)
        
    };
}


1;
