#!/usr/bin/perl
use strict;

package Time::Span::Restricted;
use Moose;
use Carp qw(carp croak);

extends 'Time::Span';

sub is_absence { return } # so kann kein Time::Span Objekt diese Klasse via next anschließen.

__PACKAGE__->meta->make_immutable;
no Moose;
1; 


