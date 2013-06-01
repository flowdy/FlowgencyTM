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

has [qw|_prefix_i _suffix_i|] => (
    is => 'ro',
    isa => 'Time::CalWeekCnt',
    lazy => 1,
    default => sub {
         croak "I, Rhythm, am uninitialized";
    },
);

has '+_prefix_i' => ( handles => { 'from_week_day' => 'stringify' } );
has '+_suffix_i' => ( handles => { 'until_week_day' => 'stringify' } );

has description => ( is => 'ro', isa => 'Str' );

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
    
    my %week_patterns;
    ($week_patterns{''}, my @week_patterns) = split /;/, $week_pattern;
    for ( @week_patterns ) {
        my ($sel, $pattern) = m{ \A 0*(\d+n.*?) : (.+) \z }xms
            or croak "odd succeeding pattern segment: $_";
        $week_patterns{$sel} = $pattern;
    }

    my $min_unit = gcf_minutes(
        map { m{ : 0*(\d+) }gxms } values %week_patterns
    );
    my $hourdiv = 60 / $min_unit;
    my $daylength = $hourdiv * 24;
    my $default_hours = Bit::Vector->new($daylength);
    
    WEEK: for my $wp ( values %week_patterns ) {
        my @days = (undef) x 7;
        
        PART_OF_THE_WEEK:
        for my $wspan ( split /(?<=\d),(?=[A-Za-z])/, $wp ) {

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
        $wp = \@days;

    }
    
    my $last = do {
        my $fp = delete $week_patterns{''}; sub { $fp };
    };
    for my $sel ( sort { $a cmp $b } keys %week_patterns ) {
        my ($factor, $add) = $sel =~ m{ (\d+) n ([+-]\d+)? }xms;
        croak "week pattern selector malformed: $sel" if !$factor;
        $add //= 0;
        my $wp = $week_patterns{$sel};
        my $next = $last;
        my $func = sub {
            my $divisible = $_[0] - $add;
            goto $next if $divisible < 0
                       || $divisible % $factor;
            return $wp;
        };
        $last = $func;
    }

    @{$args}{qw/hourdiv pattern description/}
        = ($hourdiv, $last, $week_pattern);

    return $class->new($args);

}

sub gcf_minutes { # hour partitioner (greatest common factor)
     my $x = 60;
     while (@_) {
         my $y = shift || 60;
         ($x, $y) = ($y, $x % $y) while $y;
     }
     return $x;
}

sub BUILD {
    use Time::CalWeekCnt;
    my ($self, $args) = @_;
    my @date = @{ $args->{init_day} // croak 'Missing array ref init_day' };
    $_ = Time::CalWeekCnt->new(@date, selector => $self->pattern)
        for @{$self}{'_prefix_i', '_suffix_i'};
    $self->_suffix_i->move_by_days(-1);
    $self->move_end(1);
    return $self;
}

sub move_start {
    my ($self, $days) = @_;
    my $s = $self->_prefix_i;
    my $atoms = $self->atoms;
    my $daylength = $self->hourdiv * 24;
    if ( $days > 0 ) { # start later
       $s->move_by_days($days);
       my $new = Bit::Vector->new(0);
       my $a_size = $atoms->Size / $daylength;
       $days = $a_size if $days > $a_size;
       $new->Interval_Substitute(
           $self->atoms, 0, 0, map { $_*$daylength } $days, $a_size
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
    my $daylength = $self->hourdiv * 24;
    if ( $days < 0 ) { # end earlier
       $e->move_by_days($days);
       my $new = Bit::Vector->new(0);
       my $len = $atoms->Size - $daylength * -$days;
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
        $ts = [ $index, $hourdiv_sec - $rest, $rest ]; 
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

    for ($slices[ 0] ) { $_ -= $_/abs($_) * $ts_start->[-1] }
    for ($slices[-1]) { $_ -= $_/abs($_)  * $ts_end->[ 1] }

    return \@slices;
}

__PACKAGE__->meta->make_immutable;
