use strict;

package User;
use Moose;
use Time::Scheme;

has _dbicrow => (
    is => 'ro',
    isa => 'FlowDB::User',
    required => 1,
    handles => [qw/ id username /],
);

has _time_scheme => (
    is => 'ro',
    isa => 'Time::Scheme',
    lazy => 1,
    init_arg => undef,
    builder => '_build_time_scheme',
}

has weights => (
    is => 'ro',
    isa => 'HashRef[Int]',
    build => '_build_weights',
}
    
sub _build_time_scheme {
    my ($self) = shift;
    Time::Scheme->from_json($self->dbirow->time_scheme);    
}

sub time_scheme {
    my ($self, $json) = @_;
    my $scheme = $self->_time_scheme;
    if ( defined $json ) {
        $scheme->update_from_json($json);
        $self->_dbicrow->update({ time_scheme => $json });
    }
    return $scheme;
}

__PACKAGE->meta->make_immutable;
