#!perl
use strict;

package Time::Scheme;
use Moose;
use Carp qw(carp croak);
use Date::Calc;
use Time::Line;

my %schemes = ();

has dbirow => (
    is => 'ro',
    isa => 'FlowDB::TimeScheme',
    required => 1,
    handles => [qw/name title/],
);

has timeline => (
    is => 'ro',
    isa => 'Time::Line',
    writer => '_set_timeline',
    handles => [ 'respect', 'calc_slices', 'version' ],
    init_arg => undef,
);
    
has parent => (
    is => 'ro',
    isa => __PACKAGE__,
    weak_ref => 1,
);

has variations => (
    is => 'ro',
    isa => 'ArrayRef[HashRef]',
);

has children => (
    is => 'ro',
    isa => 'ArrayRef[Time::Scheme]'
);

sub BUILD {
    my ($self, $args) = @_;
    
    my $row = $self->dbirow;
    my $tl = Time::Line->new(
        fillIn => Time::Span->new(
            description => $row->title,
            week_pattern => $row->pattern,
            from_date => '1.',  # no matter what
            until_date => '1.', # no matter what
        )
    );
    $self->_set_timeline($tl);
    $self->update_variations;
}

sub update_variations {}

sub get {
    my ($self, $id) = @_;

    die 'to be implemented' if length($id);

    return $self;
}
__PACKAGE__->meta->make_immutable;

1;
