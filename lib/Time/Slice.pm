#!perl
use strict;
use utf8;

package Time::Slice;
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

__END__

sub below {}
sub Time::Slice::harmonize_sec_spans {

    return shift if @_ == 1;

    # Listenteile, deren Zahlen alle entweder positiv oder negativ sind,
    # sollen erst einmal durch Addition zu einem Element reduziert werden.
    # Da die CodeRef an List::Util::reduce nur Skalare zurückgeben darf ...
    my $same_sign_reduce = sub {
        my @out = shift;
        while ( defined(my $num = shift) ) {
            if ( $out[-1] && $num && $out[-1]<0 ^ $num<0 ) {
                push @out, $num;
            }
            else { $out[-1] += $num }
        }
        return \@out;
    };

    # Validiere und bereite Ausgangsdaten zur Weiterverarbeitung auf
    my ($i, %sums, @lists);
    for ( @_ ) {
        $i++;
        my $s; $s += abs($_) for @$_;
        push @{$sums{$s}}, $i;
        push @lists, { stack => $same_sign_reduce->(@$_) };
    }
    if ( scalar keys %sums > 1 ) {
        my @sums;
        while ( my ($sum, $lists) = each %sums ) {
            push @sums, $sum.'('.join(',', map { "\$$_" } @$lists).')';
        }
        die "Sums of magnitudes differ between the lists: ",
            join(' != ', @sums);
    }

    # Nun steppt der Bär: Wir reichen einzeln von {stack} über {remainder}
    # zu {new} durch. Jedes durchgereichte Element ist das kleinste in der
    # jeweiligen Spalte. Die {remainder} der anderen Zeilen werden um diesen
    # Betrag gegen 0 reduziert, an ihre {new}-Liste wird dieser Betrag mit dem
    # Vorzeichen des Rests angehängt.
    while (1) { 
        use List::Util qw(min);
        my @col = map { $_->{remainder} ||= shift @{$_->{stack}} } @lists;
        my $min = min( map { defined($_) ? abs($_) : () } @col );
        last if !defined $min;
        my $i = 0;
        my $list;
        for ( @col ) {
            $list = $lists[$i++];
            next if !defined;
            $_ = $_>0 ? $min : -$min;
            $list->{remainder} -= $_;
            push @{ $list->{new} }, $_;
        }
    }

    return map { $_->{new} } @lists;
   
}
sub Time::Slice::couple {
    my ($self, $to_couple) = @_;

    my $sl = $self->slicing;

    my ($predecessor, $successor, $replace_from, $replace_to);
    my $diff_start = $to_couple->position - $self->position;
    my $diff_end = $to_couple->length - ($self->length - $diff_start);

    if ( $diff_start > $self->length ) {
        return $self, undef, $to_couple;
    }
    elsif ( $diff_start < -$to_couple->length ) {
        return $self, $to_couple;
    }

    my $prepare = sub {
        my ($offset, $i_second) = @_;
        my ($i, @split) = split_pos($offset,$sl);
        shift @split if !$split[0];
        splice @$sl,            $i, 1, @split;
        splice @{$self->synth}, $i, 1, @split
            if $self->isa('Time::Slice::Coupled');
        return $i + $i_second ? $#split : 0;
    };

    if ( $diff_start < 0 ) {
        ($predecessor, $to_couple) = $to_couple->split(-$diff_start);
    }
    elsif ( $diff_start > 0 ) {
        $replace_from = $prepare->($diff_start, 1);
    }

    if ( $diff_end > 0 ) {
        ($to_couple. $successor) = $to_couple->split($diff_end);
    }
    elsif ( $diff_end < 0 ) {
        $replace_to = $prepare->($self->length + $diff_end);
    }
        
    my @replacements;
    if ( $self->span->isa('Time::Span::Hiatus') ) {
        # Hiatus-Slices cannot bind slices at indices with positive
        # numbers. That's why they occasionally fragment them.
        my $save = sub {
            push @replacements, 
        };
        my $refuse = sub {

        };
        my $i = $replace_from;
        my $signed = $sl->[$replace_from];
        my $signed0 = $signed < 0;
        my ($first_do, $second_do) = $signed0 ? ($save, $refuse)
                                   :            ($refuse, $save);
        PING: $len1 = 0; while ( $i < $replace_to ) {
             $len += abs($signed);
             $signed = $signed < 0;
             if ($signed ^ $signed0) {
                 $first_do->($to_couple, $i, $len);
                 goto PONG;
             }
        }
        continue { $signed = $sl->[$i++] }

        PONG: $len2 = 0; while ( $i < $replace_to ) {
            goto PING if !($signed ^ $signed0);
        }
        continue { $signed = $sl->[$i++] }
    }
    else {
        push @replacements, [ $replace_from, $replace_to, $to_couple ];
    }

    my @sl_new = @$sl;
    my $shorter = 0;
    my @synth = $self->calc_slicing({ traverse => 0 });
    for my $r ( @replacements ) {
        my ($from, $to, $slice) = @$r;
        my $len = $to - $from;
        my ( $slicing, $synth ) = harmonize_sec_spans(
            scalar $slice->slicing, [ @synth[$from..$to] ]
        );
        splice @sl_new, $from, $len+1, Time::Slice::Coupled->new(
            span => $slice->span,
            position => $slice->position,
            slicing => $slicing,
            base => [ @{$sl}[ $from .. $to ] ],
            synth => $synth,
        );
        $shorter += $len;
    }
    $self->slicing(\@sl_new);

    $sl = $self;
    do { $sl->upd_lengths } while $sl = $sl->below;

    return $self, $predecessor, $successor;
}

package Time::Slice::Coupled;
use Moose;

extends 'Time::Slice';

has ['base','synth'] => (
    is => 'ro',
    isa => 'ArrayRef[Int]',
    required => 1,
    auto_deref => 1,
);

has below => (
    is => 'ro',
    isa => 'Time::Slice',
    required => 1,
    weak_ref => 1,
);
    
override calc_slicing => sub {
    my ($self, $opts) = @_;

    my @sl = $self->slicing;
    my @sy = $self->synth;
    my @out;
    
    my $is_signed = $self->span->isa('Time::Span::Hiatus')
        ? sub { $_[0] < 0 || $_[1] > 0 }
        : sub { $_[0] < 0 && $_[1] < 0 }
        ;
    
    while ( my ($x, $y) = (shift @sl, shift @sy) ) {
        if ( ref $x ) {
            push @out, $opts->{flatten} // 1
                ? $x->calc_slicing($opts)
                : $x;
            shift @sy for 2 .. @{$x->base};
            next;
        }
        elsif ( abs($x) == abs($y) ) {
            push @out, ($is_signed->($x, $y) ? -1 : 1) * abs($x);
        }
        else {
            die 'Oops, out of sync - magnitudes differ';
        }
    }

    return @out;
};

__PACKAGE__->meta->make_immutable;
1;


__END__

has nfi => ( is => 'rw', isa => 'Int' );

has finished => (
     is => 'ro', isa => 'Bool', writer => 'finish', init_arg => undef,
);


sub swallow_hiatus_slice {
    # substitute any positive segments by according segments from hiatus slice
    my ($self,$hiatus) = @_;
    my $first_sec = $self->position;
    my $last_sec = $first_sec + $self->length;
    my $h_start = $hiatus->position;
    my $h_end = $h_start + $hiatus->length;

    my @hsl = $hiatus->slicing;
    my $hval;

    my $hiatus_segment = sub {
        my ($pos,$len) = @_; my (@ret,@inv);
        if ( $pos < $h_start ) {
            my $spare = $h_start - $pos; ($len -= $spare) < 0 or return $len;
            push @ret, $spare; $pos = $h_start; 
        }
        elsif ( $pos > $h_end ) { $hiatus->finish(1); return $len; }
        
        $pos -= $h_start + $hval;
        my ($hs,$in);

        for my $v ( $pos, $len ) {
            while ( $v and @hsl ) {
                $hs = \$hsl[0]; my $sec = min(abs($$hs),$v);
                if ( $in ) { push @inv, -$$hs/abs($$hs) * $sec; }
                $$hs -= $$hs/abs($$hs) * $sec; $hval += $sec; $v -= $sec;
            }
            continue { shift @hsl if !$$hs; }
            $in++;
        }

        push @ret, [ $self->span, scalar @inv ], $len || ();
        $hiatus->finish( $hval == $hiatus->length() );
            
        return @ret;

        
    };
    
    if ( $first_sec > $h_end ) {
        $hiatus->finish(1);
    }
    elsif ( $last_sec < $h_start ) {
        $self->finish(1);
    }
    else {

        my $nfi = $self->nfi // 0;
        my $sl  = $self->slicing;
        my $pos = $first_sec;

        HIATUS: while ( $nfi < @$sl ) {
            my $nfival;
            until ( $nfival = $sl->[$nfi++] and !ref $nfival && $nfival > 0 ) {
                next if ref $nfival; $pos += -$nfival;
            }
            continue { defined $sl->[$nfi] or last HIATUS; }
            my @seg = $hiatus_segment->($pos, $nfival);
            splice @$sl, $nfi, 1, @seg;
            $pos += $nfival;
            my $add2nfi = @seg;
            shift @seg if !ref $seg[0];
            $add2nfi-- if $seg[0][1] == @seg-2;
            $nfi += $add2nfi;
            last if $hiatus->finished;
        }

        $self->nfi($nfi);
        $self->finish( $nfi == @$sl );

    }
}
