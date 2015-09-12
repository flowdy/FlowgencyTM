#!/usr/bin/perl
use strict;

package FTM::Time::Variation::BorrowedRhythm;
use Moose;

extends 'FTM::Time::Variation';

has ref => (
    is => 'rw',
    isa => 'FTM::Time::Track',
    required => 1,
    weak_ref => 1,
);

sub week_pattern { shift->ref->week_pattern }

1;

__END__

=head1 NAME

FTM::Time::Variation::BorrowedRhythm – A variation using the standard rhythm of another track
