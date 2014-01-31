use strict;

package FlowRank;
use Moose;

has time => (
    is  => 'ro',
    isa => 'Num|Time::Point',
);

has _tasks => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { {} },
    traits  => ['Hash'],
    handles => {
        clear_tasks         => 'clear',
        register_task       => 'set',
        no_tasks_registered => 'is_empty',
    },
);

has get_weights => (
    is => 'bare',
    isa => 'CodeRef',
);

has _minmax => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    clearer => 'clear_minmax',
);

sub _set_minmax {
    my ( $self, $which, $value ) = @_;

    return if !defined $value;

    # Reinitialize _minmax member after clearing
    my $minmax = $self->{_minmax} //= {};

    # Reinitialize [ $min, $max ] array-ref if needed
    $which = $minmax->{$which} //= [ 0, 0 ];

    # Make sure $min and $max cover our $value
    $value < $_ and $_ = $value for $which->[0];
    $value > $_ and $_ = $value for $which->[1];

    return $value;
}

sub new_closure {

    my $self = shift->new(@_);

    return sub {

        # If we are called without another task to register,
        # we return a ranked list of all registered tasks:
        if ( !@_ ) {

            my $list = $self->get_ranking();
            $self->clear_tasks;

            my $minmax = { %{ $self->_minmax } };
            $self->clear_minmax;

            return $minmax, $list;

        }

        # At the first run, when our tasks cache is yet empty, we accept
        # a timestamp to base the time-dynamic scoring criteria on
        elsif ( $self->no_tasks_registered ) {
            my ($t) = @_;
            if ( $t && ( !ref $t || $t->isa("Time::Point") ) ) {
                $self->_time($t);
                return;
            }
            else { $self->_time(time) } # DEFAULT: Current local time
        }

        $self->register_task(shift);

    };
}

around register_task => sub {
    my ( $orig, $self, $task ) = @_;

    my %ctd = $task->update_cursor( $self->_time );

    my $measure = $self->register(
        "$task" => {
            pri  => $task->priority,
            tpd  => $ctd{current_pos} - $task->progress,
            due  => $ctd{remaining_pres},
            open => $ctd{elapsed_pres} - $task->open_sec,
            eatn => $task->estimate_additional_time_need,
        }
    );

    while ( my ( $which, $value ) = each %$measure ) {
        $self->_set_minmax( $which => $value );
    }

    # Include also the task object itself in the hash-ref
    # It will be unwrapped on scoring:
    $measure->{task_obj} = $task;

    return $task;

};

sub calculate_score {

    my ( $minmax_href, $wgh_href, $task_href ) = @_;

    $task_href = ( delete $task_href->{task_obj} )->current_rank($task_href);

    $task_href->{eatn} //= $wgh_href->{not_enough_eatn} // $wgh_href->{eatn};

    if ( $task_href->{due} < 0 and my $overdue = $wgh_href->{overdue} ) {
        $task_href->{due} *= $overdue;
    }

    my ( $rank, $wgh, $min, $max );
    while ( my ( $which, $value ) = each %$task_href ) {
        $wgh = $wgh_href->{$which} || next;
        ($min, $max) = @{ $minmax_href->{$which} };
        $value -= $min; # as is $max reduced by min in get_ranking()
        $rank += abs($wgh) * abs( $value / $max - ( $wgh < 0 ) );
    }

    return $task_href->{FlowRank_score} = $rank;

}

sub get_ranking {
    my $self    = shift;
    my %minmax  = %{ $self->_minmax };
    my $tasks   = $self->tasks;
    my %weights = $self->get_weights->();

    for my $aref ( values %minmax ) {
        $aref = [@$aref];    # want my own min and max
        $aref->[1] -= $aref->[0];    # ... to reduce max by min
    }

    # Let's have our own sort function that maps the hash reference 
    # to the compared score value in-place to calculate it once only
    my ( @v, $r );
    my $score_and_compare = sub {
        for $r ( @v = ( $a, $b ) ) {    # copy aliases
            $r = \$tasks->{$r};
            next if !ref($$r);
            $$r = calculate_score( \%minmax, \%weights, $$r );
        }
        return $v[0] <=> $v[1];
    };

    return [ reverse sort $score_and_compare
               map { $_->{task_obj} } values %$tasks
           ];

}

