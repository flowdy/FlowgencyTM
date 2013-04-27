#!/usr/bin/perl
use strict;
use utf8;

package Time::Rhythm;
use Moose;
use Bit::Vector;
use Carp qw(carp croak);

my %WDAYNUM; @WDAYNUM{
  qw|So Su Mo Di Tu Mi We Do Th Fr Sa |}
  = (0, 0, 1, 2, 2, 3, 3, 4, 4, 5, 6   );

has [qw|_prefix_i _suffix_i|] => ( is => 'rw', isa => 'Int' );

has description => ( is => 'ro', isa => 'Str' );

has pattern => (
    is => 'ro',
    isa => 'ArrayRef',
    traits => ['Array'],
    handles => {
        loop_size => 'count',
    },
);

has atoms => (
    is => 'rw',
    isa => 'Bit::Vector',
    init_arg => undef,
    default => sub { Bit::Vector->new(0) },
);
 
has hourdiv => ( is => 'ro', isa => 'Int', required => 1 );

sub from_string {
    my ($class, $week_pattern) = @_;
    
    my @week_pattern = split /;/, $week_pattern;
    my @week_multipliers
        = map { s{ (\d+) \* }{}xms ? $1 : 1 } @week_pattern;
    # Spanne ergibt sich aus Wochenmultiplikatoren

    my $min_unit = gcf_minutes( map { m{ : 0* (\d+) }gxms } @week_pattern );
    my $hourdiv = 60 / $min_unit;
    my $daylength = $hourdiv * 24;
    my $default_hours = Bit::Vector->new($daylength);
    
    my @pattern;

    WEEK: for ( @week_pattern ) {
        my @days = (undef) x 7;
        
        PART_OF_THE_WEEK: for my $wspan ( split /(?<=\d),(?=[A-Za-z])/ ) {

            my $hours_bits = Bit::Vector->new($daylength);
            my ($days, $hours) = split /@/, $wspan;
            my @tmp_days;

            DAY_HOURS_ASSOC: for ( split /,/, $days ) {
                if ( m{ \A ([A-Z][a-z]) - ([A-Z][a-z]+) }ixms ) {
                    my $d1 = $WDAYNUM{ucfirst $1} // croak "Not a week day: $1";
                    my $d2 = $WDAYNUM{ucfirst $2} // croak "Not a week day: $2";
                    my $dd = $d1;
                    # cf. perldoc perlop, "Range operators" in scalar context
                    my $week = 7;
                    while ( $dd == $d1 .. $dd == $d2 ) {
                        $tmp_days[$dd] = 1;
                        last if !--$week;
                    } continue { $dd = ($dd+1)%7 }
                }
                else {
                    my $d = $WDAYNUM{$_} // croak "Not a week day (Ww): $_";
                    $tmp_days[$d] = 1;
                }
            }

            my %bv_copy_for; for ( grep $tmp_days[$_], 0 .. 6 ) {
                my $d = \$days[$_];
                if ( ref $$d ) { $$d = $bv_copy_for{$$d} ||= $$d->Clone; }
                else { $$d = $hours_bits; }
            }

            my @vec = ($hours_bits, values %bv_copy_for);
            my $bitsetter = sub {
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

            HOUR: for ( split /,/, $hours // '0-23' ) {
                my $is_absence = s{^!}{};
                $_ = '0-23' if !length;
                if ( m{ \A 0*(\d+) (?::0*(\d+))? ([ap]m)?
                     - 0*(\d+) (?::0*(\d+))? ([ap]m)? \z }ixms
                   ){

                    # Stunde  # Minute  - # Stunde  # Minute(mglw. undef.)
                    # Achtung: Zur Wahrung der Konsistenz mit den Zeitstempeln
                    # bedeutet das Fehlen der Minutenangabe im Bisteil: h2+1
                    my ($h1,$m1,$h2,$m2) = ($1, $2||0, $4, $5); 
                    $h1 += 12 if $3 && lc($3) eq 'pm';
                    croak "Keine Stunde (0-24): $h1" if !($h1 >= 0 && $h1 < 25);
                    croak "Keine Minute (0-59): $m1" if !($m1 >= 0 && $m1 < 60);
                    $h1 = ($h1%24)*$hourdiv+$m1/$min_unit;

                    $h2 += 12 if $6 && lc($6) eq 'pm';
                    croak "Keine Stunde (0-24): $h2" if !($h2 >= 0 && $h2 < 25);
                    croak "Keine Minute (0-59): $m2"
                        if defined($m2) && !($m2 >= 0 && $m2 < 60);
                    $h2 = ($h2*$hourdiv+($m2//60)/$min_unit)%$daylength;

                    my $hh = $h1;
                    do { $bitsetter->( !$is_absence, $hh );
                         $hh = ($hh+1)%$daylength;
                       } until $hh == $h2
                       ;

                }
                else {
                    $_ += 12 if s{([ap]m)$}{}i && lc($1) eq 'pm';
                    die "Keine Stunde (0-24): $_" if !($_ >= 0 && $_ < 25);
                    my $h = $_ % 24 * $hourdiv;
                    $bitsetter->(!$is_absence, $h, $h+$hourdiv-1);
                }
            }

        }

        $_ ||= $default_hours for @days;
        push @pattern, (@days) x shift @week_multipliers;

    }
    
    return $class->new({
        hourdiv => $hourdiv,
        pattern => \@pattern,
        description => $week_pattern,
    });

}

sub gcf_minutes { # hour partitioner
     my $x = 60;
     while (@_) {
         my $y = shift || 60;
         ($x, $y) = ($y, $x % $y) while $y;
     }
     return $x;
}

sub move_start {
    my ($self, $days) = @_;
    my $s = $self->_prefix_i // 0;
    my $atoms = $self->atoms;
    my $daylength = $self->hourdiv * 24;
    if ( $days > 0 ) { # start later
       ($s += $days) %= $self->loop_size;
       my $new = Bit::Vector->new(0);
       my $a_size = $atoms->Size;
       $days = $a_size if $days > $a_size;
       $new->Interval_Substitute(
           $self->atoms, 0, 0, map { $_*$daylength } $days, $a_size
       );  
       $self->atoms($new);
    }
    elsif ( $days < 0 ) { # start earlier
       my $pattern = $self->pattern;
       my @days_vec;
       for ( my $i = 0; $i > $days; $i-- ) {
            push @days_vec, $pattern->[ ($s+$i) % @$pattern ];
       }
       $self->atoms($atoms->Concat_List(@days_vec));
       ($s += $days) %= @$pattern;
    }
    $self->_prefix_i($s);
    $self->_suffix_i( ++$s % $daylength ) if !$self->atoms->Size;
    return;
}

sub move_end {
    my ($self, $days) = @_;
    my $e = $self->_suffix_i // 0;
    my $atoms = $self->atoms;
    my $daylength = $self->hourdiv * 24;
    if ( $days < 0 ) { # end earlier
       ($e += $days) %= $self->loop_size;
       my $new = Bit::Vector->new(0);
       my $len = $atoms->Size - $daylength * -$days;
       $new->Interval_Substitute(
           $self->atoms, 0, 0, 0, $len > 0 ? $len : 0
       );  
       $self->atoms($new);
    }
    elsif ( $days > 0 ) { # end later
       my $pattern = $self->pattern;
       my @days_vec;
       for ( my $i = 0; $i < $days; $i++ ) {
           unshift @days_vec, $pattern->[ ($e+$i) % @$pattern ];
       }
       $self->atoms(Bit::Vector->Concat_List(@days_vec,$atoms));
       ($e += $days) %= @$pattern;
    }
    else { return }
    $self->_suffix_i($e);
    $self->_prefix_i( --$e % $daylength ) if !$self->atoms->Size;
    return;
}

sub slice {
   my ($self, $start, $end) = @_;
 
   my $test = do {
      my $atoms = $self->atoms;
      my $test = $atoms->can('bit_test'); # cache resolved method
      my $size = $atoms->Size;
      sub { $test->($atoms, shift) }
   };
 
   my ($last_bit, @slices, $v);
   my $hourdiv_sec = 3600 / $self->hourdiv;
   for my $i ( $start .. $end ) {
       $v = $test->($i);
       if ( $v xor $last_bit // !$v ) {
           push @slices, $v ? $hourdiv_sec : -$hourdiv_sec;
       }
       else {
           $slices[-1] += $last_bit ? $hourdiv_sec : -$hourdiv_sec;
       }
   }
   continue { $last_bit = $v; }

   return @slices;

}

__PACKAGE__->meta->make_immutable;
