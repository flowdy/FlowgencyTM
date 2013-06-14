#!/usr/bin/perl
use strict;
use warnings;

package Time::CalendarWeekCycle;
use Moose;
use Moose::Util::TypeConstraints;
use Date::Calc qw/Week_of_Year Weeks_in_Year Day_of_Week
                  Localtime Monday_of_Week Add_Delta_Days/;

=head1 NAME

Time::CalendarWeekCycle - To infer from a date the calendar week and day in it
                          (in compliance to ISO 8601)

=head1 VERSION

2013-06-09; alpha/proof-of-concept
(cf. version of overall FlowTime project)

=head1 SYNOPSIS

 my $cycle = Time::CalendarWeekCycle->new(
     $year, $month, $day,     # initial position in calendar
     selector => $select_sub, # gets ($Calender_Week_Number, $day)
                              # returns $day properties obj.
     dst_handler => $dst_sub, # gets ($at_hour, $plus_minus_hours)
                              # returns cloned and adjusted $day
     sunday_at_index => 0     # 0 is the default, hence omittable
 );

 my ($year, $month, $day) = $cycle->date;
 my $day_of_week = $cycle->day_of_week;      # 0: Sun-, 1: Mon- ... 6: Saturday
 my $week_num    = $cycle->week_num;         # 1 .. 52±1
 my $year_th     = $cycle->year_of_thursday; # may differ from ($cycle->date)[0]

 # scalar context call: returns $cycle in case you like to chain methods
 $cycle->move_by_days(+3); 
 my $cycle2 = $cycle->another_moved_by_days(1);

 # List context call: No matter if you pass a positive or negative number,
 # first list element is the nearest day, last element is the farthest!
 my @days_obj = $cycle->move_by_days(10);
 my @same_obj = reverse $cycle->move_by_days(-10);
 
 print $cycle;                # prints e.g. "CWNo./YY, Wd" (Wd = english abbr.)
 my $pos = $cycle->stringify; # stores same string to $pos

=for Internal

Further documentation in DESCRIPTION etc. after __END__ of this file.

=cut

use Scalar::Util qw(blessed);
use Carp qw(croak);
use overload q{""} => 'stringify';

has _dow => (            
    is => 'rw',
    isa => subtype { 'Int' => where { $_ >= 0 && $_ <= 6 } },
);

has _week_num => (
    is => 'rw',
    isa => subtype { 'Int' => where { $_ > 0 && $_ <= 53 } },
);

has _year => (
    is => 'rw',
    isa => subtype { 'Int' => where { length == 4 } },
);

sub day_of_week { _dow(shift) }
sub year_of_thursday { _year(shift) }
sub week_num { _week_num(shift) }

sub _dow_week_year {
    my $self = shift;
    return map { $self->$_(shift//()) } qw/_dow _week_num _year/ ;
}

sub _move_by_days {
    my ($dow, $week_num, $year, $days) = @_;
    my $maybe_self;

    if (ref $dow) { # if first argument is class instance, we'll read from it
        ($maybe_self,$days) = ($dow, $week_num);
        ($dow, $week_num, $year) = $maybe_self->_dow_week_year;
    }

    # arrange so that if ($days<0) Mo=-6 ... So=0 or ($days>0) Mo=1 ... So=7
    ($dow, my $pos) = $days>0 ? ($dow || 7, 1)
                   :  $dow    ? ($dow  - 7, 0)
                   :            (        0, 0)
                   ;
    $dow += $days;

    $week_num += int( ($dow-$pos) / 7 );

    until ( $week_num < 53 ) {
        $week_num = $week_num - Weeks_in_Year($year) || last;
        $year++;
    }
    until ( $week_num > 0 ) { $week_num += Weeks_in_Year(--$year); }

    $dow %= 7;

    if ( $maybe_self ) {
        my @v = $maybe_self->_dow_week_year($dow, $week_num, $year);
        return @v, $maybe_self; # in scalar context, returns object only.
                                # cf. perldoc "comma operator"
    }
    else { return $dow, $week_num, $year; }
}

has _selector => ( is => 'ro', isa => 'CodeRef', init_arg => undef );
has dst_handler => ( is => 'ro', isa => 'CodeRef' );

around BUILDARGS => sub {
    my ($orig, $class, @args) = @_;
    
    if ( grep(!/\D/, @args[0..2]) == 3 ) {
        my @date = splice @args, 0, 3;
        my ($week_num, $year) = Week_of_Year(@date);
        push @args, (
            _dow => Day_of_Week(@date)%7,
            _week_num => $week_num,
            _year => $year,
        );
    }

    $class->$orig(@args);
};

sub BUILD {
    my ($self, $args) = @_;

    my ($sel, $week, @pattern) = ($args->{selector} // return, 0);

    my $sunday = $args->{sunday_at_index} // 0;

    $self->{_selector} = sub {
        my ($week_num) = @_;
        return $sel     if !@_;
        return @pattern if $week == $week_num;
        @pattern = $sel->($week = $week_num);
        push @pattern, splice @pattern, 0, $sunday;
    };

}

sub stringify {
    my $self = shift;
    my ($week, $year, $day) = map { $self->$_ }
                              qw/_week_num _year _dow/; 
    return sprintf '%d/%d, %s',
        $week, substr($year, 2, 2), [qw|Su Mo Tu We Th Fr Sa|]->[$day]
    ;
}

sub day_obj {
    my ($self) = shift;
    my ($sel, $week_num, $dow)
        = map { $self->$_ } qw/_selector week_num _dow/;
    my $obj = $sel->($week_num)->[$dow];
    my ($cb, $hr, $shift);
    return $cb->($obj, $hr, $shift) if $cb = $self->dst_handler
                                   and ($hr, $shift) = $self->dst_adjustment
                                    ;
    return $obj;
    
        
}

sub move_by_days {
    my ($self, $days) = @_;

    if ( !wantarray ) {
        &_move_by_days;
        return $self;
    }

    my $sel = $self->_selector
        // croak 'list context mode not supported - no selector';

    my $step = $days/abs($days);
    my (@day_patterns);
    my ($dow, $week_num, $year);

    while ( $days ) {
        $self->_move_by_days($step);
        push @day_patterns, $self->day_obj;
    }
    continue {
        $days -= $step;
    }

    return @day_patterns;
}

sub another_moved_by_days {
    my $self = shift;
    my ($dow, $week_num, $year) = _move_by_days(
        $self->_dow_week_year, shift
    );
    return (blessed $self)->new(
        _dow => $dow, _week_num => $week_num, _year => $year,
        selector => $self->_selector->()
    );
}

sub date {
    my ($self) = @_;
    return Add_Delta_Days(
        Monday_of_Week($self->week_num, $self->year_of_thursday),
        ($self->day_of_week||7)-1
    );
}

sub dst_adjustment {
    my $self = shift;
    my @date = &date;
    my $t1 = Localtime(@date, 0, 0, 0);
    my $t2 = Localtime(Add_Delta_Days(@date, 1), 0, 0, 0);
    my $shift = 24 - ($t2 - $t1) / 3600;
    return if !$shift;
    my $i;
    for $i ( 0 .. 23 ) {
        last if localtime($t1 + ($i-$shift) * 3600)
             eq localtime($t1 +  $i         * 3600);
    }
    return $i, $shift;
}

__PACKAGE__->meta->make_immutable;

return 1 if caller;

package main;

use Test::More;

my @initial_date = (2013, 5, 25);
my $cw = Time::CalendarWeekCycle->new(
    @initial_date,
    selector => sub { qw(Mo Di Mi Do Fr Sa So) },
    dst_handler => sub {
        my ($wd, $hr, $shift) = @_;
        "$wd\[$hr, $shift\]"
    },
    sunday_at_index => 6,
);
is_deeply [$cw->date], \@initial_date, "round-trip check";
is $cw->week_num, 21, 'day of the week, initial check';
$cw->move_by_days(-9);
is $cw->week_num, 20, 'move into previous week';
is $cw->day_of_week, 4, 'day of the week is Thursday (num. 4)';
my $cw2 = $cw->another_moved_by_days(9);
is $cw2->day_of_week, 6, 'return safe: copy has day of week Saturday (6)';
is $cw2->week_num, 21, 'return safe: copy has orig. week number';
$cw->move_by_days(-1233);
is_deeply [$cw->_dow_week_year], [3,53,2009],
    'going back to a week no. 53';
$cw->move_by_days(4);
is $cw->day_of_week, 0, 'day method says we have Sunday (which is in 2010)';
is $cw->year_of_thursday, 2009, 'but year() outputs the year covering the Thursday of the week in question';
$cw = Time::CalendarWeekCycle->new(2013,5,25)->move_by_days(953);
is_deeply [map { $cw->$_() } qw/day_of_week week_num year_of_thursday/], [0,53,2015],
    'going forward to a week no. 53';

done_testing;

__END__

=head1 DESCRIPTION

Personal time management sometimes needs do be kept in line with
a staff roster of whatever kind. For instance, such a roster might
define that one is on duty Mondays of I<even> weeks 9 to 13 o'clock.
To map this to the raw number of seconds yielded by the system clock
is not trivial at all. Think of the leap year: February has
one more day. Note also that not all years cover 52 weeks, but some ±1
according to the calendar. When using this module, the time manager
probably is bound to local time vs. Greenwich Mean Time, meaning you
must keep track of daylight save time shift. Thus, one day in spring has
effectively 23, one day in fall 25 hours. As the cost of calculating
hour and direction of DST shift is small in this module, you can use it to have
a callback triggered with day object, hour 0-23 and shift length(±)
parameters, so you can take special actions for those days.

Note, however: To associate which weeks to which patterns of duty/non-duty or
whatever times is beyond the scope of this class. You simply pass a callback
that gets the respective calender week number. Its return value is expected to be an array ref containing the objects for the days of that week (you define the class and constructions of these objects), with the Sunday expected at index 0. The references to the objects are cached and returned "as is" by move_by_days() method. Also note that for the DST affected days they are passed "as is" to your DST handler which is responsible for cloning the object prior to any modification. Otherwise, these modifications would affect the same day in other weeks as well.

=for FlowTimeDoc

=head1 THIS CLASS IN RELATION TO OTHER FlowTime::Time CLASSES

Time::Span, class of each link of the Time::Profile chain specifying when the user plans to work and when not (thus limiting the increase of the time-dynamic dimensions of a task's urgency to certain areas in the calendar) serves the purpose of telling apart work and leisure for every portion of every day between the timestamps delimiting the span. A portion can be an hour, half an hour etc. up to a minute, depending on the resolution of the user-defined pattern. Time::Rhythm is what defines the interior of Time::Span. It is basically simply a pair of Time::CalendarWeekCycle instances accessing the same week pattern selector.

The day patterns are realized with Bit::Vector, where each bit denotes work (1) or leisure (0). These bits are copied into another, span-wide Bit::Vector, member "_atoms" of the Time::Rhythm instance, serving as cache from which Time::Slice instances are generated to map those portions of a day back to clusters of net or leisure seconds. These slices are then scanned when calculating the net working time progress of a task, which is needed again to figure out how near the deadline effectively is, or how much and in which direction it diverge from the substantive progress. For both it is very important to ignore the leisure phases of the time between start and deadline, so FlowTime can help reducing disposition to ponder about work stuff during leasure.

=head1 DEPENDENCIES

=over 4

=item Date::Calc

=item localtime() system-call with DST sensitivity 
