#!perl
use strict;
use utf8;

package FTM::Time::SlicedInSeconds;
use Carp qw(carp croak);
use List::Util qw(min);

use Moose;

has position => ( is => 'ro', isa => 'Int', required => 1 );

has length => (
    is => 'ro', writer => '_set_length', isa => 'Int', init_arg => undef,
);

has presence => (
    is => 'ro', writer => '_set_presence', isa => 'Int', init_arg => undef,
);

has absence => (
    is => 'ro', writer => '_set_absence', isa => 'Int', init_arg => undef,
);

has span => (
    is => 'ro',
    isa => 'FTM::Time::Span',
    required => 1,
    weak_ref => 1,
);

has slicing => (
    is => 'rw', isa => 'ArrayRef[Int]', required => 1, auto_deref => 1,
);

sub upd_lengths {
    my ($self) = @_;
    my ($presence,$absence) = (0,0);
    my $sl = $self->slicing;
    ($_ > 0 ? $presence : $absence) += abs $_ for @$sl;
    $self->_set_presence( $presence );
    $self->_set_absence(  $absence );
    $self->_set_length($presence + $absence );
}

*BUILD = \&upd_lengths;

sub calc_slicing {
    my ($self, $opts) = @_;

    if (!($opts->{traversal}//1)) {
        return $self->slicing;
    }
    else {
        return map { ref($_) ? $_->calc_slicing($opts) : $_ }
                   $self->slicing
        ;
    }
}
    
sub calc_pos_data {
    my ($self, $time, $store) = @_;
    $store //= {};

    my $first_sec = $self->position;
    my $last_sec = $first_sec + $self->length;

    if ( $time < $first_sec ) {
        $store->{ remaining_pres } += $self->presence;
        $store->{ remaining_abs  } += $self->absence;
    }
    elsif ( $time > $last_sec ) {
        $store->{ elapsed_pres } += $self->presence;
        $store->{ elapsed_abs  } += $self->absence;
    }
    else {

        my @s = $self->slicing;
        my $cursec = $first_sec;
        my $s;

        my @loop = (
            \$store->{elapsed_pres}, \$store->{elapsed_abs},
                $time - $first_sec,
            \$store->{remaining_pres}, \$store->{remaining_abs},
                $last_sec - $time,
        );
        PART: while ( my ($pres,$abs,$len) = splice @loop, 0, 3 ) {
            while ( @s ) {
                $s = \$s[0];
                my $sec = min( abs($$s), $len );
                $_   += $sec for $cursec, $$s < 0 ? $$abs : $$pres;  
                $len -= $sec;
                $$s  -= $$s / abs($$s) * $sec;
            }
            continue { shift @s if !$$s; next PART if !$len; }      
        }
        continue {
            last if !@loop; # so block is run only once between iter. 1 + 2
            $store->{span} = $self->span;
            $store->{seconds_until_switch} = abs($$s);
            $store->{state} = ($$s || (ref $s[0] ? $s[1] : $s[0])) > 0 || 0;
        } 
    }

    return $store;
}

sub absence_in_presence_tail {
    my ($self, $presence) = @_;
    my $sl = $self->slicing;
    my ($val, $pres, $abs, $i) = (0) x 4;

    while ( $pres < $presence ) {
        $val = $sl->[--$i]
            // croak "Not enough presence seconds found in sliced time";
        ($val > 0 ? $pres : $abs) += abs $val;
    }

    return $abs;
}

sub splice {
    my ($self, $offset_ref, $len_ref) = @_;
    my @ret;
    my @s = $self->slicing;
    if ( $$offset_ref > $self->length ) {
        $$offset_ref -= $self->length;
        return [];
    }
    elsif ( $$offset_ref ) {
        my ($i, $first) = (_split_pos($$offset_ref, \@s))[0,2];
        @s = splice @s, $i if $i;
        $s[0] = $first;
        $$offset_ref = 0;
    }
    for my $s ( @s ) {
        my $sec = min( abs($s), $$len_ref );
        $$len_ref -= $sec;
        push @ret, $s / abs($s) * $sec;
        last if !$$len_ref;
    }
    return \@ret;
}

sub _split_pos {
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


__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Time::SlicedInSeconds - chunks of evaluated time rhythms

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 COPYRIGHT

(C) 2012-2014 Florian Hess

=head1 LICENSE

This file is part of FlowgencyTM.

FlowgencyTM is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowgencyTM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowgencyTM. If not, see <http://www.gnu.org/licenses/>.

