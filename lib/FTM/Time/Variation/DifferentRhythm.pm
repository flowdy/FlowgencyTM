#!/usr/bin/perl
use strict;

package FTM::Time::Variation::DifferentRhythm;
use Moose;
use FTM::Types;
use FTM::Time::Span;

extends 'FTM::Time::Variation';

has week_pattern => (
    is => 'rw',
    isa => 'FTM::Time::Rhythm',
    coerce => 1,
);

sub _specific_fields { return 'week_pattern' }

augment like => sub {
    my ($self, $other) = @_;
    
    return $self->week_pattern->description
        eq $other->week_pattern->description
        && ( ref($self) eq __PACKAGE__ || inner() );
        ;
};

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 NAME

FTM::Time::Variation::DifferentRhythm – Track variation using the specified rhythm pattern instead

