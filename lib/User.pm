use strict;

package User;
use Moose;
use Time::Model;
use User::Tasks;
use FlowRank;
use JSON;

has _dbicrow => (
    is => 'ro',
    isa => 'FlowDB::User',
    required => 1,
    handles => [qw/ id username /],
    init_arg => "dbicrow",
);

has _time_model => (
    is => 'ro',
    isa => 'Time::Model',
    lazy => 1,
    init_arg => undef,
    default => sub {
        my ($self) = shift;
        Time::Model->from_json(shift->_dbicrow->time_model);    
    }
);

has tasks => (
    is => 'ro',
    isa => 'User::Tasks',
    init_args => undef,
    default => sub {
        my $self = shift;
        User::Tasks->new(
            time_profile_provider => sub {
                $self->_time_model->get_profile(shift);
            }, 
            flowrank_processor => FlowRank->new({
                get_weights => sub { $self->weights }
            })->closure;
            tasks_rs => $self->_dbicrow->tasks,
        );
    },
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
};
    
sub store_weights {
    my ($self) = @_;
}

sub update_time_model {
    my ($self, $json) = @_;
    my $model = $self->_time_model;
    if ( defined $json ) {
        $model->update_from_json($json);
        $self->_dbicrow->update({ time_model => $json });
    }
    return $model;
}

__PACKAGE->meta->make_immutable;
