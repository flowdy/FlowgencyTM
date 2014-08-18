use strict;

package FlowRank;
use FlowTime::Types;
use Moose;

has time => (
    is  => 'ro',
    isa => 'Num|Time::Point',
);

has _tasks => (
    is      => 'ro',
    isa     => 'HashRef[FlowRank::Score]',
    default => sub { {} },
    traits  => ['Hash'],
    handles => {
        register_task       => 'set',
        no_tasks_registered => 'is_empty',
    },
);

has get_weights => (
    is => 'bare',
    isa => 'CodeRef',
);

has _rundata => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub {{}},
);

sub clear {
    my $self = shift;
    %{ $self->$_ } = () for qw( _tasks _rundata );
}

sub _set_minmax {
    my ( $self, $which, $value ) = @_;

    return if !defined $value;

    # Reinitialize _minmax member after clearing
    my $minmax = $self->_rundata;

    # Reinitialize hash-ref with minimum and maximum if needed
    $which = $minmax->{$which} //= { maximum => 0, minimum => 0 };

    # Make sure $min and $max cover our $value
    $value < $_ and $_ = $value for $which->{minimum};
    $value > $_ and $_ = $value for $which->{maximum};

    return;
}

sub new_closure {

    my $self = shift->new(@_);

    return sub {

        # If we are called without another task to register,
        # we return a ranked list of all registered tasks:
        if ( !@_ ) {

            my $list = $self->get_ranking();
            $self->clear;

            return $list;

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
        return;

    };
}

around register_task => sub {
    my ( $orig, $self, $task ) = @_;

    my %ctd = $task->update_cursor( $self->_time );

    my $score = FlowRank::Score->new({
        %ctd,
        priority  => $task->priority,
        progress  => $task->progress,
        open      => $task->open_sec($ctd{elapsed_pres}),
        _task     => $task,
    });

    $self->$orig( "$task" => $score );

    for my $which (qw( priority due drift open addtmneed )) {
        $self->_set_minmax( $which => $score->$which() );
    }

    return $task;

};

sub get_ranking {
    my $self    = shift;
    my %rundata = %{ $self->_rundata };
    my $tasks   = $self->tasks;
    my %weights = $self->get_weights->();

    while ( my ($key, $href) = each %rundata ) {
        $href = $rundata{$key} = {%$href};    # want my own min and max
        $href->{maximum} -= $href->{minimum}; # ... to reduce max by min
        $href->{weight} = $weights{$key}; 
    }

    $rundata{$_} = $weights{$_} for qw(shortoftime overdue);
    
    # Let's have our own sort function that maps the hash reference 
    # to the compared score value in-place to calculate it once only
    my ( @v, $r );
    my $score_and_compare = sub {
        for $r ( @v = ( $a, $b ) ) {    # copy aliases
            $r = \$tasks->{$r};
            next if !ref($$r);
            $$r = $$r->calculate_score( \%rundata );
        }
        return $v[0] <=> $v[1];
    };

    my $rank;
    return [ map { $_->score->rank( ++$rank ) }
               reverse sort $score_and_compare
               map { $_->_task } values %$tasks
           ];

}

package FlowRank::Score;
use POSIX qw(ceil);
use List::Util qw(min);
use Moose;

has [ qw(elapsed_pres priority) ] => (
    is => 'ro', isa => 'Int',
);

has due => ( is => 'ro', isa => 'Int', init_arg => 'remaining_pres' );

has _task => (
    is => 'ro', isa => 'Task',
);

has [qw(score rank)] => ( is => 'rw', isa => 'Num' );

sub calculate_score {

    my ( $self, $rundata_href ) = @_;

    ( delete $self->{_task} )->score($self);

    $self->{timeneed} //= $rundata_href->{  shortoftime   }
                      //  $rundata_href->{timeneed}{weight}
                      ;

    if ( $self->{due} < 0 and my $overdue = $rundata_href->{overdue} ) {
        $self->{due} *= $overdue;
    }

    my $score;
    while ( my ( $which, $rundata ) = each %$rundata_href ) {
        my $wgh         = $rundata->{weight} || next;
        my ($min, $max) = @{ $rundata }{ 'minimum', 'maximum' };
        my $value       = $self->$which() - $min;
            # as is $max reduced by min in get_ranking()
        $score         += abs( $value / $max - ( $wgh < 0 ? 1 : 0 ) )
                        * abs( $wgh )
                        ;
    }

    $self->rundata($rundata_href);
    return $self->score($score);

}

sub addtmneed {
    my $self = shift;

    my $task = $self->_task;

    my $netsec;
    if ( my $progress = $self->progress ) {
        $netsec = ceil( $self->elapsed_pres / $progress );
    }
    else {
        $netsec = 2 * $self->elapsed_pres + $self->due;
    }

    my $start = $task->start_ts->epoch_sec;
    my ($planned_to_finish, $estimate_to_finish)
        = map { $_->last_sec - $start }
              $task->due_ts, $task->timestamp_at_net_second($netsec) // return
          ;

    return $estimate_to_finish / $planned_to_finish;

}

sub drift {
    my $self = shift;

    my $progress = $self->progress;
    my $tmneed   = $self->elapsed_pres;

    return ( $progress - $tmneed )
        / ( 1 - min($progress, $tmneed) )
        ;
}

__PACKAGE__->meta->make_immutable;
