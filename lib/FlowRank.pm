use strict;

package FlowRank;
use Moose;

has time => (
    is => 'ro',
    isa => 'Num|Time::Point',
);

has _tasks => (
    is => 'ro',
    isa => 'HashRef',
    default => sub {{}},
    traits => ['Hash'],
    handles => {
        clear_tasks => 'clear',
        register_task => 'set',
        no_tasks_registered => 'is_empty',
    },
);

has get_weights => ( is => 'bare', isa => 'CodeRef' );

has _minmax => (
    is => 'ro',
    isa => 'HashRef',
    lazy => 1,
    clearer => 'clear_minmax',
);

sub _set_minmax {
    my ($self, $which, $value) = @_;
    return if !defined $value;
    my $minmax = $self->{_minmax} //= {};
    $which = $minmax->{$which} //= [0,0];
    $value < $_ and $_ = $value for $which->[0];
    $value > $_ and $_ = $value for $which->[1];
    return $value;
}
    
sub new_closure {

    my $self = shift->new(@_);
    
    return sub {

         if (!@_) {
             my $list = $self->get_ranking();
             $self->clear_tasks;
             $self->clear_minmax;
             return {%{ $self->_minmax }}, $list;
         }

         elsif ( $self->no_tasks_registered ) {
             my ($t) = @_;
             if ( $t && ( !ref $t || $t->isa("Time::Point") ) ) {
                 $self->_time($t); return;
             }
             else { $self->_time(time) }              
         }

         $self->register_task(shift);

    };    
}

around register_task => sub {
    my ($orig, $self, $task) = @_;

    my %ctd = $task->update_cursor( $self->_time );

    my $measure = $self->register("$task" => {
        pri  => $task->priority,
        tpd  => $ctd{current_pos} - $task->progress,
        due  => $ctd{remaining_pres},
        open => $ctd{elapsed_pres} - $task->open_sec,
        eatn => $task->estimate_additional_time_need,
    });            

    while ( my ($which, $value) = each %$measure ) {
        $self->_set_minmax( $which => $value );
    }

    $measure->{task_obj} = $task;

    return $task;

};

sub evaluate_rank {

    my ($minmax_href, $wgh_href, $task_href) = @_;

    $task_href = (delete $task_href->{task_obj})->current_rank($task_href);

    $task_href->{eatn} //= $wgh_href->{not_enough_eatn} // $wgh_href->{eatn};

    if ( $task_href->{due} < 0 and my $od = $wgh_href->{overdue} ) {
        $task_href->{due} *= $od;
    }

    my ($rank, $wgh, $minmax);
    while ( my ($which, $value) = each %$task_href ) {
        $wgh   = $wgh_href->{$which} || next;
        $minmax = $minmax_href->{$which};
        $value -= $minmax->[0];
        $rank  += abs($wgh) * abs(
             $value / $minmax->[1] - ($wgh < 0)
        );
    }

    return $task_href->{FlowRank} = $rank;

}

sub get_ranking {
    my $self = shift;
    my %minmax = %{ $self->_minmax };
    my $tasks = $self->tasks;
    my %weights = $self->get_weights->();

    for ( values %minmax ) {
         $_       = [ @$_ ]; # copy min and max
         $_->[1] -= $_->[0]; # reduce max by min
    }

    my (@v, $r);
    my $cmp_ranks = sub {
        for $r ( @v = ($a, $b) ) { # copy aliases
            $r = \$tasks->{$r};
            next if !ref($$r);
            $$r = evaluate_rank( \%minmax, \%weights, $$r );
        }
        return $v[0] <=> $v[1];
    };

    return [ reverse
             sort   $cmp_ranks
             map    { $_->{task_obj} }
             values %$tasks
    ];

}

