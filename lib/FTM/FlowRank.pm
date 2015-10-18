use strict;

package FTM::FlowRank;
use FTM::Types;
use Carp qw(croak);
use Moose;

has _time => (
    is  => 'rw',
    isa => 'FTM::Time::Spec',
);

has _tasks => (
    is      => 'ro',
    isa     => 'HashRef[FlowRank::Score]',
    default => sub { {} },
    lazy    => 1,
    traits  => ['Hash'],
    handles => {
        register_task       => 'set',
        no_tasks_registered => 'is_empty',
    },
);

has get_weights => (
    is => 'ro',
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
    delete @{$self}{'_tasks', '_rundata'};
}

sub _set_minmax {
    my ( $self, $which, $value ) = @_;

    return if !defined $value;

    # Reinitialize _minmax member after clearing
    my $minmax = $self->_rundata;

    # Reinitialize hash-ref with minimum and maximum if needed
    $which = $minmax->{$which} //= { maximum => $value, minimum => $value };

    # Make sure $min and $max cover our $value
    $value < $_ and $_ = $value for $which->{minimum};
    $value > $_ and $_ = $value for $which->{maximum};

    return;
}

sub new_closure {

    my $self = shift->new(@_);

    return sub {

        my ($t) = @_;
        my $t_is_time = $t && ( !ref $t || $t->isa("FTM::Time::Spec") );

        # If we are called without another task to register,
        # we return a ranked list of all registered tasks and un-cache them:
        if ( !@_ ) {

            my $list = $self->get_ranking();
            $self->clear;

            return $list;

        }

        # At the first run, when our tasks cache is yet empty, we accept
        # a timestamp to base the time-dynamic scoring criteria on
        elsif ( $self->no_tasks_registered ) {
            if ( $t_is_time ) {
                $t = FTM::Time::Spec->from( $t, $self->_time // () );
                $self->_time( $t );
                return;
            }
            elsif ( !$self->_time ) {
                $self->_time(FTM::Time::Spec->now)
            }
        }

        elsif ( $t_is_time ) {
            croak "FlowRank cache has not been cleared, ",
                "time ($t) is therefore not accepted as argument";
        }

        $self->register_task(@_);
        return;

    };
}

around register_task => sub {
    my ( $orig, $self, $task, $even_if_paused ) = @_;

    my $time = $self->_time;
    my %ctd = $task->update_cursor( $time );

    return if !($ctd{state} || $even_if_paused);

    my $score = FlowRank::Score->new({
        %ctd,
        _for_ts   => $time,
        _task     => $task,
    });

    $self->$orig( "$task" => $score );

    for my $which (qw( priority due drift open timeneed )) {
        $self->_set_minmax( $which => $score->$which() );
    }

    return $task;

};

sub get_ranking {
    my $self    = shift;
    my %rundata = %{ $self->_rundata };
    my $tasks   = $self->_tasks;
    my %weights = $self->get_weights->();

    while ( my ($key, $href) = each %rundata ) {
        $href = $rundata{$key} = {%$href};    # want my own min and max
        $href->{maximum} -= $href->{minimum}; # ... to reduce max by min
        $href->{weight} = $weights{$key}; 
    }

    $rundata{$_} = $weights{$_} for qw(shortoftime overdue);
    
    if ( keys(%$tasks) == 1 ) {
        my ($score) = values(%$tasks);
        my $task = $score->_task;
        $score->calculate_score(\%rundata);
        return [$task];
    }

    # Let's have our own sort function that maps the hash reference 
    # to the compared score value in-place to calculate it once only
    my ( @v, $r );
    my $cached_score_compare = sub {
        for $r ( @v = ( $a, $b ) ) { # copy aliases
            $r = \$tasks->{$r};
            if ( ref $$r ) {
                $$r = $$r->calculate_score( \%rundata );
            }
        }
        return ${$v[0]} <=> ${$v[1]};
    };

    my @ranked_tasks
        = reverse sort $cached_score_compare
          map { $_->_task } values %$tasks
    ;

    my $count;
    $_->flowrank->ranking_position(++$count) for values @ranked_tasks;

    return \@ranked_tasks;

}

package FlowRank::Score;
use POSIX qw(ceil);
use List::Util qw(sum min);
use Moose;

has _for_ts => (
    is => 'ro', isa => 'FTM::Time::Spec', required => 1
);

has elapsed_pres => (
    is => 'ro', isa => 'Int', required => 1
);

has due => ( is => 'ro', isa => 'Int', init_arg => 'remaining_pres', required => 1 );

has _task => (
    is => 'ro', isa => 'FTM::Task', required => 1
);

has active => (
    is => 'ro',
    traits => ['Bool'],
    init_arg => 'state',
    handles => {
       paused => 'not',
    }
);

has next_statechange_in_hms => (
    is => 'ro',
    init_arg => 'seconds_until_switch',
);

has time_position => (
    is => 'ro',
    init_arg => 'current_pos',
);

has priority => (
    is => 'ro',
    init_arg => undef,
    lazy => 1,
    default => sub { shift->_task->priority_num },
);

has drift => (
    is => 'ro',
    isa => 'Num',
    init_arg => undef,
    lazy => 1,
    builder => '_calc_drift',
);

has timeneed => (
    is => 'ro',
    isa => 'Maybe[Num]',
    init_arg => undef,
    lazy => 1,
    builder => '_calc_timeneed',
);

has open => (
    is => 'ro',
    isa => 'Num',
    init_arg => undef,
    lazy => 1,
    default => sub {
        my $self = shift;
        $self->_task->is_open( $self->elapsed_pres ) // 0
    },
);

has ranking_position => ( is => 'rw', isa => 'Num' );

has _components => (
    is => 'ro',
    isa => 'HashRef',
    lazy => 1,
    default => sub {{}},
    init_arg => undef,
);

has _rundata => (
    is => 'rw',
    isa => 'HashRef',
    init_arg => undef,
);

around BUILDARGS => sub {
    my ($orig, $self) = (shift, shift);
    
    my $args = $self->$orig(@_);
    
    for my $sus ( $args->{seconds_until_switch} // () ) {
        $sus = _render_hms( $sus );
    }       

    return $args;
};

sub _render_hms {
    my $cts = shift;
    my $neg = $cts =~ s{^(-)}{} ? $1 : ''; 
    my ($hours, $sec) = (int($cts/3600), $cts%3600);
    (my $min, $sec)   = (int($sec/60), $sec%60);
    return sprintf "%s%d:%02d:%02d", $neg, $hours, $min, $sec;
}

sub due_in_hms {
    _render_hms(shift->due);
}

sub calculate_score {

    my ( $self, $rundata_href ) = @_;

    ( delete $self->{_task} )->flowrank($self);

    $self->{timeneed} //= $rundata_href->{  shortoftime   }
                      //  $rundata_href->{timeneed}{weight}
                      ;

    if ( $self->{due} < 0 and my $overdue = $rundata_href->{overdue} ) {
        $self->{due} *= $overdue;
    }

    my $score;
    my $comps = $self->_components; 
    while ( my ( $which, $rundata ) = each %$rundata_href ) {
        my $wgh         = $rundata->{weight} || next;
        my ($min, $max) = @{ $rundata }{ 'minimum', 'maximum' };
        next if !$max; # Because min and max equal, order is irrelevant
        my $value = ($self->$which - $min) / $max - ( $wgh < 0 ? 1 : 0 );
            # as is $max reduced by min in get_ranking()
        $comps->{$which} = abs( $value ) * abs( $wgh );
    }
    continue { $score += $comps->{$which} //= 0 }

    $self->_rundata($rundata_href);
    return $score;

}

sub score { return sum 0, values %{shift->_components}; }

sub dump {
    my $self = shift;

    my ($comps, $rundata) = ($self->_components, $self->_rundata);
    my %rundata;
    while ( my ($which, $value) = each %$rundata ) {
        next if !ref $value;
        for my $r ( $rundata{$which} ) {
            $r = {%$value};
            @{$r}{'raw','weighted'} = (
                $self->$which, $comps->{$which}
            );
            $r->{maximum} += $r->{minimum};
            my $w = $r->{weight};
            if ( $w < 0 ) {
                @{$r}{'maximum', 'minimum'} = @{$r}{'minimum', 'maximum'};
                $r->{weight} = abs $w;
            }
        }
    }

    return {
       datetime => q{}.$self->_for_ts,
       state => $self->active ? 'active' : 'paused',
       components => \%rundata,
       map { $_ => $self->$_ }
           qw(score ranking_position next_statechange_in_hms elapsed_pres),
    };
}

sub _calc_timeneed {
    my $self = shift;

    my $task = $self->_task;

    my $netsec;
    if ( my $progress = $task->progress ) {
        $netsec = ceil( $self->elapsed_pres / $progress );
    }
    else {
        my $due     = $self->due;
        if ( $due < 0 ) { $due = 0; }
        $netsec = 2 * $self->elapsed_pres + $self->due;
    }

    my $start = $task->start_ts->epoch_sec;
    my ($planned_to_finish, $estimate_to_finish)
        = map { $_->last_sec - $start }
              $task->due_ts, $task->timestamp_at_net_second($netsec) // return
          ;

    return $estimate_to_finish / $planned_to_finish;

}

sub _calc_drift {
    my $self = shift;

    my $progress = $self->_task->progress;
    my $elapsed_pres = $self->elapsed_pres;
    my $time_position   = $self->time_position;

    return ( $time_position - $progress )
        / ( 1 - min($progress, $time_position) )
        ;
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::FlowRank - The ranking score for tasks between starting date and date of completion

=head1 SYNOPSIS

=head1 DESCRIPTION

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

