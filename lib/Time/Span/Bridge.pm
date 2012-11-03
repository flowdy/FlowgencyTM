#!/usr/bin/perl
use strict;

package Time::Span::Bridge;
use Moose;
use Carp qw(carp croak);

extends 'Time::Span';

has '+subspans' => (
    trigger => sub {
        croak 'Time::Span::Bridge cannot have subspans';
    },
);

__PACKAGE__->meta->make_immutable;
no Moose;
1; 

