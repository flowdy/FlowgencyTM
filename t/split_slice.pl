#!/usr/bin/perl
use strict;

use Carp qw(croak);

sub split_pos {
    my ($offset, $list) = @_;
    croak "negative offset" if $offset < 0;
    my ($i, $lof, $fos) = 0;
    for my $n (@$list) {
        $offset -= abs $n;
        if ( $offset < 0 ) {
            $fos = -$offset;
            $lof = abs($n) + $offset;
            if ( $n < 0 ) { $_ = -$_ for $fos, $lof }
            last;
        }
    } continue { $i++ }
    croak "offset too large" if $offset > 0;
    return $i, $lof, $fos;
}

sub split_slice {
    my ($offset, @head) = @_;
    my ($i, $lof, $fos) = split_pos($offset, \@head);
    my @tail = splice @head, $i;
    push @head, $lof;
    $tail[0] = $fos;
    return \@head, \@tail;
}

1;
