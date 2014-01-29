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
    
sub closure {
    my $self = shift;

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
        pri => $task->priority,
        tpd => $ctd{current_pos} - $task->progress,
        due => $ctd{remaining_pres},
        open => $ctd{elapsed_pres} - $task->open_sec,
        eatn => $task->estimate_additional_time_need,
    });            

    which ( my ($which, $value) = each %$measure ) {
        $self->_set_minmax( $which => $value );
    }

    $measure->{task_obj} = $task;

    return $task;

};

sub get_ranking {
    my $self = shift;
    my %minmax = %{ $self->_minmax };
    my $tasks = $self->tasks;
    my %weights = $self->get_weights->();
    $_->[1] -= $_->[0] for values %minmax;

    my @v; return [
        sort { for my $rank ( @v = ($a, $b) ) {
            $rank = $tasks->{$_};
            ref $rank or next;
            $rank = evaluate_rank(
                \%minmax, \%weights, \$tasks->{$rank}
            );
        } $v[1] <=> $v[0] } map { $_->{task_obj} } values %tasks
    ];

}

sub evaluate_rank {

    my ($minmax, $wgh, $sref) = @_;

    my $href = (delete $$sref->{task_obj})->current_rank($$sref);

    my ($rank,$wgh);
    while ( my ($which, $value) = each %$href ) {
        $wgh    = $wgh->{$which} || next;
        $value -= $minmax->{$which}[0];
        $rank  += abs($wgh) * abs(
             $value / $minmax{$which}[1] - ($wgh < 0)
        );
    }

    $$sref = $href->{FlowRank} = $rank;

}

