#!/usr/bin/perl
use strict;

package FTM::Time::Variation::BorrowedRhythm;
use Moose;

extends 'FTM::Time::Variation';

has week_pattern_of_track => (
    is => 'rw',
    isa => 'FTM::Time::Track',
    required => 1,
    trigger => \&FTM::Time::Variation::_change_ref_track,
    weak_ref => 1,
);

sub week_pattern { shift->week_pattern_of_track->fillIn->rhythm }

sub _specific_fields { return 'week_pattern_of_track' }

augment like => sub {
    my ($self, $other) = @_;
    
    return $self->week_pattern_of_track
        == $other->week_pattern_of_track
        && ( ref($self) eq __PACKAGE__ || inner() );
        ;
};

sub DEMOLISH {
    my $self = shift;
    if ( my $track = $self->week_pattern_of_track ) {
        $track->_drop_ref_child( $self );
    }
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 NAME

FTM::Time::Variation::BorrowedRhythm – A variation using the standard rhythm of another track
