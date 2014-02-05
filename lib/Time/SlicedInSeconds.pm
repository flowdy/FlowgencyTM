#!perl
use strict;
use utf8;

package Time::SlicedInSeconds;
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
    isa => 'Time::Span',
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
    if ( ref $time && $time->isa('Time::Point') ) {
        $time = $time->epoch_sec;
    }

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
        my ($orig,$lenh,$s);

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
                $lenh = $lenh && $lenh-1;
            }
            continue { shift @s if !$$s; next PART if !$len; }      
        }
        continue {
            last if !@loop; # so block is run only once between iter. 1 + 2
            $store->{span} = $lenh && $$s < 0 ? $orig : $self->span;
            $store->{changed} = $cursec + $$s + 1;
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

sub split {
    my ($self, $offset) = @_;
    my $sl = $self->slicing;
    my ($i, $lof, $fos) = split_pos($offset, $sl);
    my @tail = splice @$sl, $i;
    push @$sl, $lof;
    $tail[0] = $fos;
    $self->upd_lengths;
    return $self, $self->new(
        slicing => \@tail,
        position => $self->position + $offset,
        span => $self->span,
    );
}

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


__PACKAGE__->meta->make_immutable;

