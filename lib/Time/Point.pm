#!perl
use strict;
use utf8;

package Time::Point;
use Moose;
use Carp qw(carp croak);
use Time::Local;

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

sub from_plain_ts {
    my ($class, $ts) = @_;
    return $class->new( epoch_sec => $ts );
}

sub parse_ts {
    use Scalar::Util 'blessed';
    my ($class, $ts, $year, $month, $day) = @_;
    if (ref $year and my $date = $year) {
        croak "Not a $class object" if !(blessed($date) && $date->isa($class));
        ($year,$month,$day) = ($date->year, $date->month, $date->day);
    }
    my @date = localtime(time);
    my %ret;
    $ret{assumed_year} = $year ||= $date[5]+1900;
    $ret{assumed_month} = $month ||= $date[4]+1;
    $ret{assumed_day} = $day ||= $date[3]; 

    # Parsen wir den Datumsteil
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

    # Parsen wir nun den Zeitteil. Der ist immer absolut:
    $ts =~ s{ \G \s* T?
        0?(\d\d?) (?: \: 0?(\d\d?) # Minuten sind optional
        (?:\:0?(\d\d?))? )? # Braucht man eines Tages Sekunden? Horror!
    \s* | }{}xms;
    croak 'Invalid time'
        if !Date::Calc::check_time(map { $_ || 0 } $1, $2, $3);
    $ret{hour} = $1 if defined $1;
    $ret{min} = $2 if defined $2;
    $ret{sec} = $3 if defined $3;

    croak 'No date and/or time found in string (expecting one at its front)'
        if !defined( $ret{year} || $ret{month} || $ret{day} || $ret{hour} );

    $ret{remainder} = $ts;
    return $class->new(\%ret);
   
}

sub from_epoch {
    my ($class, $sec_since_epoch, $min_precision, $max_precision) = @_;
    
    my %date;
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
    $self->year($_) if !defined($self->year) and $_ = $self->assumed_year;
    $self->month($_) if !defined($self->month) and $_ = $self->assumed_month;
    $self->day($_) if !defined($self->day) and $_ = $self->assumed_day;
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

    my ($shorter,$longer) = sort { length($a) <=> length($b) } $stsa, $stsb;
    return $longer =~ s{^ \Q$shorter\E }{}xms ? -1 : ($stsa cmp $stsb);

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
