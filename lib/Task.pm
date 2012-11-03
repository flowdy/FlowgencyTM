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

sub update {
    my $self = shift;
    my $args = @_ % 2 ? shift : { @_ };
 
    my $step = %$args == 1 ? do { $args = values %$args; keys %$args }
             :               delete $args->{step};

    my $row = $self->dbicrow;

    unless ( $args->{name} ||= $step || q{} ) {
        for my $field (qw(from_date until_date timeline)) {
            $row->$field(delete($args->{$field}) // next);
        }
        if ( my $cursor = $self->cursor and $row->in_storage ) {
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
        else { croak 'no cursor' if !$cursor }
    }

    my $step_rs = $self->steps;

    if ( my $p = $args->{parent} ) {

        if ( my $p_row = $step_rs->find($p) ) {

            my $pos = $args->{pos};
            my $siblings = $p_row->children;

            if ( defined $pos and $siblings->count >= $pos
              and my @later_sibs = $siblings->search({ pos=>{ '>=' => $pos } })
               ) {
                $_->update({ pos => $_->pos+1 })
                    for sort { $b->pos <=> $a->pos } @later_sibs;
            }
            else {
                $args->{pos} = $siblings->count + 1;
            }

        }
        else {
            croak "no row $p to be a child of";
        }           

    }

    my @rec_path = $args;
    my %steps;

    while ( my $current = $rec_path[-1] ) {
        my $substeps = $current->{substeps};
        my $substep;

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
            else { $attr->{pos} = ++$current->{pos}; }

            if ( $attr->{parent} ) {
                carp "{parent} is imposed from higher level - uninfluencable";
            }
            else { $attr->{parent} = $current->{name}; }

            push @rec_path, $attr;

        }
        else {

            for my $c ($steps{ delete $current->{oldname} }) {
                croak "circularly referred to or multiple entry of $c->{name}"
                    if defined $c;
                $c = $current;

            }

            pop @rec_path;

        }

    }
    
    while ( my $step = $step_rs->next ) {

        if ( my $s = delete $steps{ $step->name } ) {
            while ( my ($field, $value) each %$s ) { $step->$field($value) }
            $step->update();
        }

        else {
            # Forget all substeps unmentioned in the hierarchy
            my ($ar,$ah) = ($step,undef);
            until ( $ah ) { $ar = $ar->parent_row;
                $step->delete if ($ah = $steps{$ar->name})
                              && $ah->{substeps}
                              ;
            }
        }

    }

    for my $s ( values %steps ) {

        delete @{$s}{'substeps', 'pos'};
        my %subtask;

        for my $field (qw(timeline from_date until_date timeline priority)) {
            my $value = delete $s->{$field} // next;
            $subtask{$field} = $value;
        }

        my $s_row = $row->add_to_steps($s);
        while ( my ($field,$value) = each %subtask ) {
            $s_row->$field($value);
        }

    }

    if ( my %steps = @_ ) {
        while ( my ($step, $data) = each %steps ) {
            $self->update($step => $data)
        }
    }

    $self->_clear_done_rate; # to be recalculated next done_rate() call

    return $row->update_or_create();
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
    
    my $tension = $elapsed - $done;
    $tension /= 1 - $elapsed < $done ? $elapsed : $done;
    my $hours = int($avatime / 3600);
    my $seconds = $avatime % 3600;
    my $minutes = int( $seconds / 60 );
    $seconds %= 60;

    return {
        %time_pos,
        priority => $prio,
        remaining_time => sprintf('%d:%02d:%02d', $hours, $minutes, $seconds),
        tension => $tension,
        urgency => $elapsed == 1 ? $LONG_MAX - $done / $pri
                 : $E ** ($prio + $tension * $prio) / (1-$elapsed)
    };
}


1;
