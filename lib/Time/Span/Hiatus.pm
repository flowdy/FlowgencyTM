#!/usr/bin/perl
use strict;

package Time::Span::Hiatus;
use Moose;
use Carp qw(carp croak);

extends 'Time::Span';

has '+next' => (
    is => 'rw',
    isa => 'Time::Span::Hiatus',
);

sub is_absence { 1 }

__PACKAGE__->meta->make_immutable;

1; 
