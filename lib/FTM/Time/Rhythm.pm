#!/usr/bin/perl
use strict;
use utf8;

package FTM::Time::Rhythm;
use Moose;
use Bit::Vector;
use FTM::Time::CalendarWeekCycle;
use FTM::Time::SlicedInSeconds;
use Carp qw(carp croak);

my %WDAYNUM; @WDAYNUM{
  qw|So Su Mo Di Tu Mi We Do Th Fr Sa |}
  = (0, 0, 1, 2, 2, 3, 3, 4, 4, 5, 6   );

has [qw|_prefix_i _suffix_i|] => (
    is => 'ro',
    isa => 'FTM::Time::CalendarWeekCycle',
    lazy => 1,
    default => sub {
         croak "I, Rhythm, am uninitialized";
    },
);

has '+_prefix_i' => ( handles => { 'from_week_day' => 'stringify' } );
has '+_suffix_i' => ( handles => { 'until_week_day' => 'stringify' } );

has description => ( is => 'ro', isa => 'Str' );

has net_seconds_per_week => ( is => 'ro', isa => 'Num' );
has pattern => (
    is => 'ro',
    isa => 'CodeRef',
);

has atoms => (
    is => 'rw',
    isa => 'Bit::Vector',
    init_arg => undef,
    default => sub { Bit::Vector->new(0) },
);
 
has hourdiv => ( is => 'ro', isa => 'Int', required => 1 );

sub from_string {
    my ($class, $week_pattern, $args) = @_;
    
    my $hour_min_rx = qr{ 0*(\d+) (?::0*(\d+))? ([ap]m)? }ixms;

    my %week_patterns;
    my @week_patterns = split /;/, $week_pattern;
    $week_patterns{ q[] } = shift @week_patterns;
    for my $wp ( @week_patterns ) {
        my ($sel, $pattern) = $wp =~ m{ \A 0*(\d+n.*?) : (.+) \z }xms
            or croak "odd succeeding pattern segment: $wp";
        $week_patterns{$sel} = $pattern;
    }

    # Detect in how many parts we have to divide the days (atoms)
    # minimum 24 (hours) over 48 (half hours) upto maximum 1440 (minutes)
    my $min_unit = _gcf_minutes(
        map { m{ : 0*(\d+) }gxms } values %week_patterns
    );

    my $hourdiv = 60 / $min_unit;
    my $daylength = $hourdiv * 24;
    my $holiday = Bit::Vector->new($daylength);
    
    for my $wp ( values %week_patterns ) {

        my @days = (undef) x 7;
        
        for my $wspan ( split /(?<=\d),(?=[A-Za-z])/, $wp ) {

            my $hours_bits = Bit::Vector->new($daylength);
            my ($wdays, $hours) = split /@/, $wspan;
            my @tmp_days;

            # Processing chains of (ranges of) week days ...
            for my $wdays ( split /,/, $wdays ) {

                if ( $wdays =~ m{ \A ([A-Z][a-z]) - ([A-Z][a-z]) \z }ixms ) {

                    my ($d1, $d2) = map { _get_number_of_wday($_) } $1, $2;

                    WDAY:
                    for (1..7) {
                        $tmp_days[$d1] = 1;
                        last WDAY if $d1 == $d2;
                        $d1 = ( $d1 + 1 ) % 7; 
                    }

                }

                else {
                    $tmp_days[ _get_number_of_wday($wdays) ] = 1;
                }

            }

            # For each selected day, if it refers to an existing bitvector, we
            # clone it so that it can modified independently from the days among
            # which it was originally defined. Otherwise, we have it refer to
            # $hours_bits.
            my %bv_copy_for; 
            WDAYNUM:
            for ( 0 .. 6 ) {
                $tmp_days[$_] or next WDAYNUM;
                my $d = \$days[$_];
                $$d = ref($$d) ? ($bv_copy_for{$$d} ||= $$d->Clone)
                    :            $hours_bits
                    ;
            }

            my $bitsetter = _get_multivec_bitsetter(
                $hours_bits, values %bv_copy_for
            );

            # Process the chain of (ranges of) hours by modifying the
            # respective bits in each bit vector.
            for my $hours ( split /,/, $hours // '0-23' ) {

                my $is_absence = $hours =~ s{^!}{};
                $hours = '0-23' if !length($hours);

                if ( $hours =~ m{ \A $hour_min_rx - $hour_min_rx \z }ixms ){

                    my ($h1, $m1, $h2, $m2) = ($1, $2||0, $4, $5); 

                    $h1 += 12 if $3 && lc($3) eq 'pm';
                    $h2 += 12 if $6 && lc($6) eq 'pm';
                    _check_hour($_) for $h1, $h2;
                    _check_minute($_) for $m1, $m2 // ();

                    $h1 = $h1 * $hourdiv + $m1 / $min_unit;

                    $m2 //= 60; # Note: In accordance to FTM::Time::Point logic
                                # the lack of minutes in the to-part means: h2+1
                    $h2 = $h2 * $hourdiv + $m2 / $min_unit;
                    $h2 %= $daylength; # so you can input 12pm meaning midnight

                    DATOM: # day atom
                    for (1..$daylength) {
                      $bitsetter->( !$is_absence, $h1 );
                      $h1 = ( $h1 + 1 ) % $daylength; # These two lines differ in
                      last DATOM if $h1 == $h2;       # order from the days' loop
                    }                                 # above!

                }

                else {
                    $hours += 12 if $hours =~ s{([ap]m)$}{}i && lc($1) eq 'pm';
                    _check_hour($hours);
                    my $h = $hours % 24 * $hourdiv;
                    $bitsetter->(!$is_absence, $h, $h+$hourdiv-1);
                }

            }

        }

        $_ ||= $holiday for @days;

        $wp = \@days;

    }
    
    @week_patterns = ([1, 0, delete $week_patterns{q[]} ]);
    for my $sel ( sort keys %week_patterns ) {
        my ($factor, $add) = $sel =~ m{ (\d+) n ([+-]\d+)? }xms;
        croak "week pattern selector malformed: $sel" if !$factor;
        $add //= 0;
        my $wp = $week_patterns{$sel};
        unshift @week_patterns, [$factor, $add, $wp];
    }

    my $sel = sub {
        my $week_num = shift;
        my $divisible;
        for my $wp ( @week_patterns ) {
            $divisible = $week_num - $wp->[1];
            next if $divisible < 0
                 || $divisible % $wp->[0];
            return @{$wp->[2]};
        }
    };

    my $net_ratio;
    for my $wnum ( 1 .. 53 ) {
        for my $pat ( $sel->($wnum) ) { 
             $net_ratio += $pat->Norm * (3600 / $hourdiv)
        }
    }
    $net_ratio /= 53;

    @{$args}{qw/hourdiv  pattern description    net_seconds_per_week/}
        = (    $hourdiv, $sel,   $week_pattern, $net_ratio        );

    return $class->new($args);

}

sub _gcf_minutes { # hour partitioner (greatest common factor)
     my $x = 60;
     while (@_) {
         my $y = shift || 60;
         ($x, $y) = ($y, $x % $y) while $y;
     }
     return $x;
}

sub _get_number_of_wday {
    my $wday = shift;
    return $WDAYNUM{ ucfirst $wday }
        // croak "Not a week day: $wday";
}

sub _check_hour {
    my $h = shift;
    $h >= 0 && $h < 25
        or croak "Not in hours range (0-24): $h";
}

sub _check_minute {
    my $m = shift;
    $m >= 0 && $m < 60
        or croak "Not in minutes range (0-59): $m";
}

sub _get_multivec_bitsetter {
    my @vec = @_;

    return sub {

        my ($bit, $start, $end) = @_;

        if ( $start == ($end//$start) ) {
            $_->Bit_Copy($start, $bit) for @vec;
        }

        elsif ( $start < $end ) {
            my $meth = 'Interval_'.( $bit ? 'Fill' : 'Empty' );
            $_->$meth( $start, $end ) for @vec;
        }

        else { die 'start index > end index' }

    };

}

sub BUILD {
    my ($self, $args) = @_;
    my @date = @{ $args->{init_day} // croak 'Missing array ref init_day' };
    $_ = $self->_get_week_cycler(@date) for @{$self}{'_prefix_i', '_suffix_i'};
    $self->_suffix_i->move_by_days(-1); $self->move_end(1);
}

sub _get_week_cycler {
    my ($self, @date) = @_;
    my $hourdiv = $self->hourdiv;
    return FTM::Time::CalendarWeekCycle->new(
        @date,
        selector => $self->pattern,
        monday_at_index => 1,
        dst_handler => sub {
            my ($bv, $h, $s) = @_;
            $bv = $bv->Clone;
            my @subst_args = $s < 0 ? ($h,  0, $h+$s, abs $s)
                           : $s > 0 ? ($h, $s,     0,      0)
                           : die '$s is zero'
                           ;
            $_ *= $hourdiv for @subst_args;
            $bv->Interval_Substitute($bv, @subst_args);
            return $bv;
        },
    );
}

sub move_start {
    my ($self, $days) = @_;
    my $s = $self->_prefix_i;
    my $atoms = $self->atoms;
    if ( $days > 0 ) { # start later
       my $units = $s->move_by_days($days);
       my $new = Bit::Vector->new(0);
       my $a_size = $atoms->Size;
       $units = $a_size if $units > $a_size;
       $new->Interval_Substitute(
           $self->atoms, 0, 0, $units, $a_size
       );  
       $self->atoms($new);
    }
    elsif ( $days < 0 ) { # start earlier
       $self->atoms(
           $atoms->Concat_List($s->move_by_days($days))
       );
    }
    return;
}

sub move_end {
    my ($self, $days) = @_;
    my $e = $self->_suffix_i;
    my $atoms = $self->atoms;
    if ( $days < 0 ) { # end earlier
       my $units = $e->move_by_days($days);
       my $new = Bit::Vector->new(0);
       my $len = $atoms->Size + $units;
       $new->Interval_Substitute(
           $self->atoms, 0, 0, 0, $len > 0 ? $len : 0
       );  
       $self->atoms($new);
    }
    elsif ( $days > 0 ) { # end later
       $self->atoms(Bit::Vector->Concat_List(
           reverse( $e->move_by_days($days) ), $atoms
         )
       );
    }
    return;
}

sub sliced {
    my ($self, $ts_start, $ts_end) = @_;

    my $hourdiv_sec = 3600 / $self->hourdiv;

    for my $ts ($ts_start, $ts_end) {
        $ts = $ts->epoch_sec if ref $ts;
        my $index = int( $ts / $hourdiv_sec );
        my $rest = $ts % $hourdiv_sec;
        $ts = [ $index, $rest, $hourdiv_sec - $rest ]; 
    }
    
    if ( !$ts_end->[1] ) {
        my ($i, $left,   $right) = \(@$ts_end);
        $$i--; ($$right, $$left) = (0, $hourdiv_sec);
    }

    my ($last_bit, @slices, $v);
    my $test = do {
        my $atoms = $self->atoms;
        my $test = $atoms->can('bit_test'); # cache resolved method
        sub { $test->($atoms, shift) }
    };
 
    for my $i ( $ts_start->[0] .. $ts_end->[0] ) {
       $v = $test->($i);
       if ( $v xor $last_bit // !$v ) {
           push @slices, $v ? $hourdiv_sec : -$hourdiv_sec;
       }
       else {
           $slices[-1] += $last_bit ? $hourdiv_sec : -$hourdiv_sec;
       }
    }
    continue { $last_bit = $v; }

    for ($slices[ 0] ) { $_ -= $_/abs($_) * $ts_start->[1] }
    for ($slices[-1]) { $_ -= $_/abs($_)  * $ts_end->[-1] }

    return \@slices;
}

sub count_absence_between_net_seconds {
    my ($self, $ts, $net_seconds, $max_abs_seconds) = @_;

    my $cursor = $self->_get_week_cycler( $ts->date_components );
    my $unit = 3600 / $self->hourdiv;
    my $day = $cursor->day_obj;
    my $ssmn = $ts->split_seconds_since_midnight;
    my $start = int $ssmn / $unit;
    my $pres = $day->bit_test($start) ? -$ssmn + $start*$unit : 0;
    my $len = $day->Size;
    my ($abs, $old_max, $min, $max) = (0,$start); 

    my $limit_reached;

    CHUNK: while ( $net_seconds > $pres  ) {

        if ( my @limits = $day->Interval_Scan_inc($start) ) {
            ($min, $max) = @limits;
            $pres += ($max - $min + 1) * $unit;
        }
        else { ($min,$max) = ($len) x 2; }

        $start = $max + 1;
        $abs += $min - $old_max;

        if ( ($max_abs_seconds//$abs) < $abs ) {
            $abs = $max_abs_seconds;
            $limit_reached++;
            last CHUNK;
        }

        if ( $start < $len ) {
            $old_max = $max+1;
        }
        else {
            ($day) = $cursor->move_by_days(1);
            ($start, $len) = (0, $day->Size);
            $old_max = $start;
        }

    }

    return $limit_reached ? ($pres, $max_abs_seconds)
                          : ($net_seconds, $abs * $unit)
                          ;

}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Time::Rhythm - Calculates seconds of working- and off-time periods in a pattern

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

