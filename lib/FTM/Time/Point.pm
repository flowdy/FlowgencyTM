#!perl
use strict;

package FTM::Time::Point;
use Moose;
use Carp qw(carp croak);
use Time::Local;
use Scalar::Util 'blessed';
use Date::Calc qw(Add_Delta_Days Add_N_Delta_YMD Add_Delta_YMDHMS Day_of_Week);

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

my %WD;
@WD{qw(mo di tu mi we do th fr sa su so)}
   = ( 1, 2, 2, 3, 3, 4, 4, 5, 6, 7, 7);

my $TS;
{ my $_last_update;
  sub now {
    my $class = shift;
    
    # Calls from within this package with $TS as their first argument
    # can simply return it when it is defined, otherwise preinitialized
    my $priv = @_ && \$_[0] == \$TS and shift; 
    goto RETURN if $TS && $priv && !@_;
    my $arg = @_  ? $_[0]
            : $TS ? goto RETURN
            :       $ENV{FLOWTIME_TODAY} // time
            ;

    if ( ref $arg ) {
        my $isObj = blessed($arg) && $arg->isa($class);
        $TS = $class->new(
           year  => $isObj ? $arg->year  : $arg->{year},
           month => $isObj ? $arg->month : $arg->{month},
           day   => $isObj ? $arg->day   : $arg->{day},
        );
    }
    else {
        my @date = localtime(time);
        $TS = $class->from($arg, $date[5]+1900, $date[4]+1, $date[3])
            ->fill_in_assumptions;
    }

RETURN:

    my $time = time;
    if ( my $seconds_since_last_call = $time - ($_last_update // $time) ) {
        $TS->move($seconds_since_last_call);
    }

    $_last_update = $time;

    if ( $TS && defined wantarray ) {
        return $priv ? $TS : $TS->copy
    }
    else { return }

}}

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
    elsif ( $ts =~ s{ \A ( [+-](?=[\d>]) (?i:\s*-?\d+[dwmy])* (>\w+)? ) }{}igxms ) {
        @ret{qw|year month day|} = ($year, $month, $day);
        (my $diff = $1) =~ s/^\+//;
        move(\%ret, $diff);
        ($year, $month, $day) = @ret{qw|year month day|};
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

sub copy {
    my ($class, $from) = shift;
    if ( my $pkg = ref $class ) {
        ($from, $class) = ($class, $pkg);
    }
    my $v;
    $class->new({
        map { defined($v = $from->$_()) ? ($_ => $v) : () }
            qw(year month day hour min sec)
    });
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

sub from {
    my ($class,$arg) = (shift, shift);
    if ( $arg =~ /^\d+$/ && $arg > 31 ) {
        return $class->from_epoch($arg);
    }
    else {
        return $class->parse_ts( $arg, @_ );
    }
}

sub move {
    my ($href, $diff) = @_;

    my @fields = qw(year month day hour min sec);

    my ($neg, %args);
    if ( !ref $diff ) {
        $neg = $diff =~ s{ ^ ([+-]) }{}xms && $1 eq q{-};
        if ( $diff =~ /\D/ ) {
            my (%long);
            @long{qw{y m d h M s}} = @fields;
            while ( $diff =~ m{ \s* (-?) (\d+) ([ymwdhMs]) }gxms ) {
                my ($s, $n, $u) = ($1, $2, $3);
                if ( $u eq 'w' ) { $u = 'd'; $n *= 7 }
                $args{ $long{$u} } += $n * ( ($s xor $neg) ? -1 : 1 );
            }
        }
        else {
            %args = ( sec => $diff );
        }
    }

    my @ymdhms = Add_Delta_YMDHMS(
        map { $_ //= 0 } map { @{$_}{ @fields } } $href, \%args
    );

    if ( $diff =~ m{ > (\w\w) \w* \z }xms ) {
        my $day = Day_of_Week(@ymdhms[0..2]);
        my $pos = $WD{ lc $1 } // croak "Not a week day: $1";
        $day = ( $pos - $day ) % ( $neg ? -7 : 7 );
        @ymdhms[0..2] = Add_Delta_Days(@ymdhms[0..2], $day);
    }
    
    my ($i, %fields) = (0, ());
    for my $f ( @fields ) {
        $href->{$f} // $args{$f} // next;
        $href->{$f} = $ymdhms[$i];
    }
    continue { $i++ }

    return $href;
}

sub fix_order {
    my ($from_date, $until_date) = @_;

    # 2a. Make sure that $from_date does not follow $until_date:
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

    # 2b. Make sure that $until_date does not preceed $from_date:
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

    return $from_date <= $until_date;

}

sub _upd_epoch_sec {
    my $self = shift;
    my @components = @{$self}{ qw|sec min hour day month year| };
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

sub date_components { @{$_[0]}{qw{ year month day }} }
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
    $epoch_sec += !defined($self->hour) ? do { # no, not always 24*3600-1
                     my @date = Add_Delta_Days($self->date_components, 1);
                     $date[1]--;
                     timelocal(0,0,0,reverse @date) - $epoch_sec - 1;
                  }
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
    return FTM::Time::Point->from_epoch( $epoch_sec, $prec, $prec);
}

sub predecessor {
    my ($self) = @_;
    my $epoch_sec = $self->epoch_sec - 1;
    my $prec = $self->get_precision;
    return FTM::Time::Point->from_epoch( $epoch_sec, $prec, $prec);
}

sub is_future {
    my ($self) = @_;
    return $self > FTM::Time::Point->now($TS);
}

sub is_past {
    my ($self) = @_;
    return $self < FTM::Time::Point->now($TS);
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Time::Point - Create and compare variably precise point of time specifications

=head1 SYNOPSIS

  my $german_date  = "5.4.14 12:00";     # full 1st minute of the 12th hour of April 5th
  my $iso8601_date = "2014-04-05 12:00"; # both formats are supported
  my $lazy_date    = "14-4-5 12:00";     # may omit century '20' and leading numbers, too
  my $ISO8601_daTe = "2014-04-05T12:00"; # opt. ISO-compliant 'T' separating date and time
  my $ts_with_sec  = "2014-04-05 12:00:00"; # maximal precision
  my $ts_hour      = "2014-04-05 12";    # represents full 12th hour
  my $ts_day       = "2014-04-05";       # represents full day: Minimal precision

  # All these variants are digested by timestamp parser
  $_ = FTM::Time::Point->parse_ts($_) for (
      $german_date, $iso8601_date, $lazy_date, $ISO8601_daTe,
      $ts_with_sec, $ts_hour, $ts_day
  );

  # You may have unspecified parts of a time spec filled according to the current date:
  my $ts = FTM::Time::Point->parse_ts("04-05")->fill_in_assumptions; # adds 2014

  # You may pass an already created instance as a base time for assumptions:
  my $base = FTM::Time::Point->parse_ts("2013-11-14");
  my $ts = FTM::Time::Point->parse_ts("04-05", $base); # fills in assumptions, too
  my $ts = FTM::Time::Point->parse_ts("04-05", 2013, 11, 14); # as you like

  # assume unspecified parts so that ts2 is after ts2
  my $ts = FTM::Time::Point->parse_ts("04-05");
  if ( $base->fix_order($ts) ) {
      # $ts->year == 2014
  }
  if ( $ts->fix_order($base) ) {
      # $ts->year == 2013 as April is before November
  }

  my $ts = FTM::Time::Point->from_epoch( time, 0, 0); # min and max position: full day
  if ( $ts < time && time < $ts ) {
      # Both conditions are met in between the first and the last second of the day:
      # In the first, $ts is the left-hand operand -> first second of denoted coverage
      # In the second, $ts is at the right hand -> last second of denoted coverage
  }

  my $copy_of_now = Time::Point->now();
  
  Time::Point->now($string_or_unix_epoch_seconds);
      # Set date of now. Caution: assumptions of new instances base on this date!
      # The date advances with the time, second by second.

=head1 DESCRIPTION

This class is an essential core part of FlowgencyTM, used e.g. for the ends of a FTM::Time::Span and FTM::Time::Cursor::Stage.

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

