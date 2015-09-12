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

1;

__END__

=head1 NAME

FTM::Time::Variation::DifferentRhythm – Track variation using the specified rhythm pattern instead

