use strict;

package User;
use Moose;
use Time::Model;

has _dbicrow => (
    is => 'ro',
    isa => 'FlowDB::User',
    required => 1,
    handles => [qw/ id username /],
);

has _time_model => (
    is => 'ro',
    isa => 'Time::Model',
    lazy => 1,
    init_arg => undef,
    builder => '_build_time_model',
}

has weights => (
    is => 'ro',
    isa => 'HashRef[Int]',
    build => '_build_weights',
}
    
sub _build_time_model {
    my ($self) = shift;
    Time::Model->from_json($self->dbirow->time_model);    
}

sub time_model {
    my ($self, $json) = @_;
    my $model = $self->_time_model;
    if ( defined $json ) {
        $model->update_from_json($json);
        $self->_dbicrow->update({ time_model => $json });
    }
    return $model;
}

__PACKAGE->meta->make_immutable;
