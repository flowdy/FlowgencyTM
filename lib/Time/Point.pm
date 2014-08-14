#!perl
use strict;

=head1 NAME

Time::Point - Create and compare variably precise point of time specifications

=head1 PART OF DISTRIBUTION

This class is an essential core part of FlowTime, used e.g. for the ends of a Time::Span
and Time::Cursor::Stage.

=head1 SYNOPSIS

  my $german_date  = "5.4.14 12:00";     # full 1st minute of the 12th hour of April 5th
  my $iso8601_date = "2014-04-05 12:00"; # both formats are supported
  my $lazy_date    = "14-4-5 12:00";     # may omit century '20' and leading numbers, too
  my $ISO8601_daTe = "2014-04-05T12:00"; # opt. ISO-compliant 'T' separating date and time
  my $ts_with_sec  = "2014-04-05 12:00:00"; # maximal precision
  my $ts_hour      = "2014-04-05 12";    # represents full 12th hour
  my $ts_day       = "2014-04-05";       # represents full day: Minimal precision

  # All these variants are digested by timestamp parser
  $_ = Time::Point->parse_ts($_) for (
      $german_date, $iso8601_date, $lazy_date, $ISO8601_daTe,
      $ts_with_sec, $ts_hour, $ts_day
  );

  # You may have unspecified parts of a time spec filled according to the current date:
  my $ts = Time::Point->parse_ts("04-05")->fill_in_assumptions; # adds 2014

  # You may pass an already created instance as a base time for assumptions:
  my $base = Time::Point->parse_ts("2013-11-14");
  my $ts = Time::Point->parse_ts("04-05", $base); # fills in assumptions, too
  my $ts = Time::Point->parse_ts("04-05", 2013, 11, 14); # as you like

  # use fix_order to assume unspecified parts so that ts2 is after ts2
  my $ts = Time::Point->parse_ts("04-05");
  if ( $base->fix_order($ts) ) {
      # $ts->year == 2014
  }
  if ( $ts->fix_order($base) ) {
      # $ts->year == 2013 as April is before November
  }

  my $ts = Time::Point->from_epoch( time, 0, 0); # min and max position: full day
  if ( $ts < time && time < $ts ) {
      # Both conditions are met in between the first and the last second of the day:
      # In the first, $ts is the left-hand operand -> first second of denoted coverage
      # In the second, $ts is at the right hand -> last second of denoted coverage
  }

=cut

package Time::Point;
use Moose;
use Carp qw(carp croak);
use Time::Local;
use Scalar::Util 'blessed';

use overload q{""} => 'get_qm_timestamp',
            q{<=>} => 'precision_sensitive_cmp',
           q{bool} => sub { 1 };

has [qw|day month year hour min sec|] => (
     is => 'rw',
     isa => 'Int',
     trigger => \&_upd_epoch_sec
);

has [map { 'assumed_'.$_ } qw(day month year)] => (
     is => 'ro', isa => 'Int'
);

has remainder => ( is => 'ro', isa => 'Str' );

has epoch_sec => ( is => 'ro', isa => 'Int', writer => '_set_epoch_sec' );

my $TS;
sub now {
    my $class = shift;
    
    # Calls from within this package with $TS as their first argument
    # can simply return it when it is defined, otherwise preinitialized
    my $priv = @_ && \$_[0] == \$TS and shift; 
    return $TS if $TS && $priv && !@_;
    my $arg = @_  ? $_[0]
            : $TS ? goto RETURN
            :       $ENV{FLOWTIME_TODAY} // time
            ;

    if ( $arg =~ m{^\d+$}xms ) { # is positive integer
        $TS = $class->from_epoch($arg);
    }
    elsif ( ref $arg ) {
        my $isObj = blessed($arg) && $arg->isa($class);
        $TS = $class->new(
           year  => $isObj ? $arg->year  : $arg->{year},
           month => $isObj ? $arg->month : $arg->{month},
           day   => $isObj ? $arg->day   : $arg->{day},
        );
    }
    else {
        my @date = localtime(time);
        $TS = $class->parse_ts($arg, $date[5]+1900, $date[4]+1, $date[3])
            ->fill_in_assumptions;
    }

RETURN:
    if ( $TS && defined wantarray ) {
        my $v;
        return $priv ? $TS : $class->new(
            map { defined($v = $TS->$_()) ? ($_ => $v) : () }
                qw(year month day hour min sec)
        );
    }
    else { return }

}

sub parse_ts {
    my ($class, $ts, $year, $month, $day) = @_;
    if (ref $year and my $date = $year) {
        croak "Not a $class object" if !(blessed($date) && $date->isa($class));
        ($year,$month,$day) = ($date->year, $date->month, $date->day);
    }
    my %ret;
    my $base_ts = $year && $month && $day ? undef : $class->now($TS);
    $ret{assumed_year}  = $year  ||= $base_ts->year;
    $ret{assumed_month} = $month ||= $base_ts->month;
    $ret{assumed_day}   = $day   ||= $base_ts->day; 

    # Parse the date components
    if ( $ts =~ s{ \A (?:(?:(\d{4}|\d\d) - )? 0?(\d\d?) - )? 0?(\d\d?)
                   (?![.:\d]) }{}gxms
                   # look ahead to tell apart german notation or clock time
       ) {
        $ret{year} = $1 if defined $1;
        substr $ret{year}, 0, 0, 20 if length($ret{year}||q{}) == 2;
        $year = $ret{year} if defined $ret{year};
        $month = $ret{month} = $2 if defined $2;
        $day = $ret{day} = $3 if defined $3;
    }
    elsif ( $ts =~ s{ \A 0?(\d\d?)\.(?:0?(\d\d?)\.(\d{4}|\d\d)?)? (?!\d)
                    }{}gxms
    ) {
        $ret{year} = $3 if defined $3;
        substr $ret{year}, 0, 0, 20 if length($ret{year}||q{}) == 2;
        $year = $ret{year} if defined $ret{year};
        $month = $ret{month} = $2 if defined $2;
        $day = $ret{day} = $1 if defined $1;
    }
    elsif ( $ts =~ s{ \A \+ ((?i:\s*\d+[dwmy])+) }{}igxms ) {
        use Date::Calc qw(Add_N_Delta_YMD);
        my $diff = $1;
        my ($dd,$dw,$dm,$dy) = (0,0,0,0);
        while ( $diff =~ m{ (\d+) ([dwmy]) }igxms ) {
            my ($n,$u) = ($1,$2);
            if (lc($u) eq 'w') { $u = "d"; $n *= 7; }
            ( lc($u) eq 'd' ? $dd : lc($u) eq 'm' ? $dm : $dy ) += $n;
        }
        ($year, $month, $day) = @ret{qw|year month day|} =
            Add_N_Delta_YMD($year, $month, $day, $dy, $dm, $dd);
    }
    # else { croak "Kein Datum im String: $ts" } # to early
       
    croak "Could not parse date" if $ts =~ m{ \A \d* [.-] \d }xms;

    # Let us parse the time part which is always absolute:
    $ts =~ s{ \G \s* T?
        0?(\d\d?) (?: \: 0?(\d\d?) # Minutes are optional
        (?:\:0?(\d\d?))? )? # Will we need to indicate seconds someday? Horror!
    \s* | }{}xms;
    croak 'Invalid time'
        if !Date::Calc::check_time(map { $_ || 0 } $1, $2, $3);
    $ret{hour} = $1 if defined $1;
    $ret{min} = $2 if defined $2;
    $ret{sec} = $3 if defined $3;

    croak 'No date and/or time found in string (expecting one at its front)'
        if !defined( $ret{year} || $ret{month} || $ret{day} || $ret{hour} );

    $ret{remainder} = $ts;
    my $self = $class->new(\%ret);

    if ( @_ > 2 ) { $self->fill_in_assumptions }

    return $self;
   
}

sub from_epoch {
    my ($class, $sec_since_epoch, $min_precision, $max_precision) = @_;
    
    my %date;
    if ( !defined $sec_since_epoch ) {
        croak "from_epoch missing first argument: seconds since epoch"
    }
    @date{qw|sec min hour day month year|} = localtime $sec_since_epoch;
    $date{month}++; $date{year} += 1900;

    $_ //= 3 for $min_precision, $max_precision;
    croak 'arg 2 not in range 0..3: 1=must have hour, 2=minutes, 3=seconds'
        if $min_precision < 0 || $min_precision > 3;
    croak 'arg 3 not in range 0..3: 0=ignore hour, 1=minute, 2=second part'
        if $min_precision < 0 || $min_precision > 3;
    croak 'minimal precision greater than maximal precision - contradiction'
        if $min_precision > $max_precision;

    my %keep_precision = ( hour=>1, min=>2, sec=>3 );
    while ( my ($part,$keep_at) = each %keep_precision ) {
        delete $date{$part} if $date{$part} ? $max_precision < $keep_at
                             : $min_precision < $keep_at
                             ;
    }
    if ( defined $date{sec} ) { $_ //= 0 for @date{'min','hour'} }
    elsif ( defined $date{min} ) { $date{hour} //= 0 }

    return $class->new(%date);

}

sub fix_order {
    my ($from_date, $until_date) = @_;

    # 2a. Sicher stellen, dass $from_date nicht nach $until_date kommt:
    if ( !$from_date->month && $until_date->month) {
        my $mon = $until_date->month - (
            $from_date->day > $until_date->day ? 1 : 0
        );
        $from_date->year(
             ($until_date->year || $until_date->assumed_year)
           - ( $mon ? 0 : do { $mon=12; 1 })
        );
        $from_date->month($mon);
            
    }
    elsif ( !$from_date->year && $until_date->year) {
        $from_date->year($until_date->year - (
            $from_date->month > $until_date->month ? 1 : 0
        ));
    }
    else {
        $from_date->fill_in_assumptions;
    }

    # 2b. Wir stellen sicher, dass $until_date nicht vor $from_date kommt:
    if ( !$until_date->month ) {
        my $mon = $from_date->month + (
            $from_date->day > $until_date->day ? 1 : 0
        );
        $until_date->year($from_date->year + ($mon==13 ? do { $mon=1 } : 0));
        $until_date->month($mon);    
    }
    elsif ( !$until_date->year ) {
        $until_date->year($from_date->year + (
            $from_date->month > $until_date->month ? 1 : 0
        ));
    }

    #$_->_upd_epoch_sec for $from_date, $until_date;

    return $from_date <= $until_date;

}

sub _upd_epoch_sec {
    my $self = shift;
    my @components = map { $self->$_() } qw|sec min hour day month year|;
    return if (grep { defined $_ } @components[3,4,5]) < 3;
    $_ //= 0 for @components[0..2];
    $components[4]--;
    $components[5] %= 1900;
    if ( !defined($components[2]) && defined($components[1]) ) {
        carp "minutes cannot be respected when hour is undefined.";
        $components[1] = 0;
    }
    if ( !defined($components[1]) && defined($components[0]) ) {
        carp "seconds cannot be respected when minute and/or hour is undefined.";
        $components[0] = 0;
    }
    return $self->_set_epoch_sec(timelocal(@components));
}

sub fill_in_assumptions {
    my $self = shift;
    $self->year($_)  if !defined($self->year)  and $_ = $self->assumed_year;
    $self->month($_) if !defined($self->month) and $_ = $self->assumed_month;
    $self->day($_)   if !defined($self->day)   and $_ = $self->assumed_day;
    return $self;
}

sub precision_sensitive_cmp {
    my ($tsa,$tsb,$swap) = @_;
    ($tsa,$tsb) = ($tsb, $tsa) if $swap;
    
    my $ntsa = ref($tsa) ? $tsa->epoch_sec : $tsa;
    my $ntsb = ref($tsb) ? $tsb->epoch_sec : $tsb;
    # Timestamps differ by at least 24h so we can safely compare
    return $ntsa <=> $ntsb if abs($ntsa-$ntsb) > 86399;

    my $stsa = ref($tsa) ? $tsa->get_qm_timestamp : get_std_timestamp($tsa); 
    my $stsb = ref($tsb) ? $tsb->get_qm_timestamp : get_std_timestamp($tsb); 
    return 0 if $stsa eq $stsb; # equality, also in regard to precision

    my ($shorter, $longer, $limsec) = length($stsa) > length($stsb)
         ? ($stsb, $stsa, sub { get_std_timestamp($tsb->last_sec) })
         : ($stsa, $stsb, sub {
              ref $tsa ? get_std_timestamp($tsa->epoch_sec) : $stsa,
           })
         ;

    return index($longer, $shorter) == 0
        ? ( $longer eq $limsec->() ? 0 : -1 )
        : ( $stsa cmp $stsb );

}

sub date_components { map { $_[0]->$_() } qw{ year month day } }
sub time_components { map { $_[0]->$_() } qw{ hour min sec } }

sub get_std_timestamp {
    use POSIX;
    my $ts = ref($_[0]) ? shift->epoch_sec : shift;
    return POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime $ts);
}

sub get_qm_timestamp {
    my ($self) = @_;
    my @vals;
    for (map { $self->$_() } qw(year month day hour min sec)) {
        push @vals, length($_) ? sprintf('%02d', $_) : '??';
    }
    my $t = sprintf '%s-%s-%s %s:%s:%s', @vals;
    $t =~ s{\D+$}{};
    return $t;
}

sub last_sec {
    my ($self) = @_;
    my $epoch_sec = $self->epoch_sec
       // croak "last_sec requires all date components to be defined";
    $epoch_sec += !defined($self->hour) ? 86399
                : !defined($self->min)  ?  3599
                : !defined($self->sec)  ?    59
                : 0
                ;
    return $epoch_sec;
}

sub split_seconds_since_midnight {
    my ($self) = @_;
    my $epoch_sec = $self->epoch_sec
       // croak "split_seconds_since_midnight requires all date components to be defined";
    my $ssm = ($self->sec // 0)
            + 60*($self->min // 0)
            + 3600*($self->hour // 0)
            ;    
    $epoch_sec -= $ssm;
    return $epoch_sec, $ssm;
}

sub get_precision {
    my ($self) = @_;
    my $cd = 3;
    defined($_) ? last : $cd-- for reverse $self->time_components;
    return $cd;
}

sub successor {
    my ($self) = @_;
    my $epoch_sec = $self->last_sec + 1;
    my $prec = $self->get_precision;
    return Time::Point->from_epoch( $epoch_sec, $prec, $prec);
}

sub predecessor {
    my ($self) = @_;
    my $epoch_sec = $self->epoch_sec - 1;
    my $prec = $self->get_precision;
    return Time::Point->from_epoch( $epoch_sec, $prec, $prec);
}

__PACKAGE__->meta->make_immutable;
1;
