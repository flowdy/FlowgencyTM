#!/usr/bin/perl
use strict;
use warnings;
use utf8;

package FTM::Time::CalendarWeekCycle;
use Moose;
use Moose::Util::TypeConstraints;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use overload q{""} => 'stringify';
use Date::Calc qw/Week_of_Year Weeks_in_Year Day_of_Week
                  Mktime Monday_of_Week Add_Delta_Days/;

=for comment
Further documentation in DESCRIPTION etc. after __END__ of this file.

=cut

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

sub day_of_week { _dow(shift)+1 }
sub year_of_thursday { _year(shift) }
sub week_num { _week_num(shift) }

sub _dow_week_year {
    my $self = shift;
    return map { $self->$_(shift//()) } qw/_dow _week_num _year/ ;
}

=for comment
TODO: Consider making day, month and year members of the instance, hence we could use simply Date::Calc::Week_of_Year to calculate the week number on demand instead of going the other way round. That could impose a performance penalty, though, whereas how it is, this is only the case if DST checking is done.  

=cut

sub _move_by_days {

    my ($dow, $week_num, $year, $days) = @_;
    my $maybe_self;

    if (ref $dow) { # if first argument is class instance, we'll read from it
        ($maybe_self,$days) = ($dow, $week_num);
        ($dow, $week_num, $year) = $maybe_self->_dow_week_year;
    }

    # For $days being negative (going back in the calendar), we have to make
    # precautions: Monday be then -6, Tuesday -5, ..., Sunday still being 0. 
    my $plus1 = 0;
    if ( $days < 0 ) { ($dow,$plus1) = ($dow - 7, 1); }
    $dow += $days;

    $week_num += int( ($dow+$plus1) / 7 );
    $dow %= 7;

    until ( $week_num < 53 ) {
        $week_num = $week_num - Weeks_in_Year($year) || last;
        $year++;
    }
    until ( $week_num > 0 ) { $week_num += Weeks_in_Year(--$year); }

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
            _dow => Day_of_Week(@date)-1,
            _week_num => $week_num,
            _year => $year,
        );
    }

    $class->$orig(@args);
};

sub BUILD {
    my ($self, $args) = @_;

    my ($sel, $week, @pattern) = ($args->{selector} // return, 0, ());

    my $monday = $args->{monday_at_index} // 0;

    $self->{_selector} = sub {
        my ($week_num) = @_;
        return $sel     if !@_;
        return \@pattern if $week == $week_num;
        @pattern = $sel->($week = $week_num);
        push @pattern, splice @pattern, 0, $monday;
        return \@pattern;
    };

}

sub stringify {
    my $self = shift;
    my ($week, $year, $day) = map { $self->$_ }
                              qw/_week_num _year _dow/; 
    return sprintf '%d/%d, %s',
        $week, substr($year, 2, 2), [qw|Mo Tu We Th Fr Sa Su|]->[$day]
    ;
}

sub day_obj {
    my ($self) = shift;
    my ($sel, $week_num, $dow)
        = map { $self->$_ } qw/_selector week_num _dow/;
    my $obj = $sel->($week_num)->[$dow];
    my ($cb, $hr, $shift);
    return $cb->($obj, $hr, $shift) # we rely on $obj being cloned
        if $cb = $self->dst_handler # before modification!
       and ($hr, $shift) = detect_dst_clockface_sector($self->date)
        ;
    return $obj;
    
        
}

sub move_by_days {
    my ($self, $days) = @_;

    my $wantarray = wantarray;
    if ( !defined $wantarray ) {
        &_move_by_days;
        return;
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

    if ( $wantarray ) {
        return @day_patterns;
    }
    else {
        my $len;
        $len += $_->Size for @day_patterns;
        return $step*$len;
    }

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
        $self->day_of_week - 1
    );
}

sub detect_dst_clockface_sector {

    my $t1 = Mktime(@_, 0, 0, 0);
    my $t2 = Mktime(Add_Delta_Days(@_, 1), 0, 0, 0);
    my $shift = 24 - ($t2 - $t1) / 3600;
    return if !$shift;

    my ($i, $it1, $it2) = 0;
    while ( $i < 24 ) {
        $it2 = $t1 + $i * 3600;
        $it1 = $it2 - 1;
        $_ = (localtime($_))[2] for $it1, $it2;
        last if $it2 == ($it1+$shift+1) % 24;
    }
    continue { $i++; }
    if ( $i < 24 ) {
        return $i, $shift;
    }
    else {
        die "Couldn't figure out position of $shift dst-affected hours";
    }
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Time::CalendarWeekCycle - To infer from a date the week and the day
                          (complies to ISO 8601, relying on Date::Calc)

=head1 SYNOPSIS

 my $cycle = FTM::Time::CalendarWeekCycle->new(
     $year, $month, $day,     # initial position in calendar
     selector => $select_sub, # gets ($Calender_Week_Number, $day)
                              # returns $day properties obj.
     dst_handler => $dst_sub, # gets ($at_hour, $plus_minus_hours)
                              # returns cloned and adjusted $day
     monday_at_index => 0     # 0 is the default, hence omittable
 );

 my ($year, $month, $day) = $cycle->date;
 my $day_of_week = $cycle->day_of_week;      # 1=Mo to 7=
 my $week_num    = $cycle->week_num;         # 1 .. 52+/-1
 my $year_th     = $cycle->year_of_thursday; # may differ from $year

 # Scalar context: returns $cycle in case you like to chain methods
 $cycle->move_by_days(+3); 
 my $cycle2 = $cycle->another_moved_by_days(1);

 # List context: No matter if you pass a positive or negative number,
 # first list element is the nearest day, last element is the farthest!
 my @days_obj = $cycle->move_by_days(10);
 my @same_obj = reverse $cycle->move_by_days(-10);
 
 print $cycle;                # prints e.g. "CWNo./YY, Wd" (Wd = english abbr.)
 my $pos = $cycle->stringify; # stores same string to $pos

=head1 DESCRIPTION

Personal time management sometimes needs do be kept in line with a staff roster
of whatever kind. For instance, such a roster might define that one is on duty
Mondays of I<even> weeks 9 to 13 o'clock.  To map this to the raw number of
seconds yielded by the system clock is not trivial at all. Think of the leap
year: February has one more day. Note also that not all years cover 52 weeks,
but some have one more or less according to the calendar. When using this
module, the time manager probably is bound to local time vs. Greenwich Mean
Time, meaning you must keep track of daylight save time shift. Thus, one day
in spring has effectively 23 hours, one day in fall 25. As the cost of
calculating hour and direction of DST shift is small in this module, you
can use it to have a callback triggered with day object, hour 0-23 and positive
or negative shift width parameters, so you can take special actions for those
days.  

Note, however: To associate which weeks to which patterns of duty/non-duty or
whatever times is beyond the scope of this class. You simply pass a callback
that gets the respective calender week number. Its return value is expected
to be an array ref containing the objects for the days of that week (you define
the class and constructions of these objects), with the Sunday expected at
index 0. The references to the objects are cached and returned "as is" by
C<move_by_days()> method. Also note that for the DST affected days they are
passed "as is" to your DST handler which is responsible for cloning the object
prior to any modification. Otherwise, these modifications would affect the
same day in other weeks as well.  

=begin comment

=head1 THIS CLASS IN RELATION TO OTHER FTM::Time CLASSES

By a C<FTM::Time::Track> users can specify when they plan to work and when not, thus limiting the increase of the time-dynamic dimensions of a task's urgency to certain areas in the calendar. It is merely a chain of C<FTM::Time::Span> instances that serve the purpose of telling apart work and leisure for every portion of every day between two C<FTM::Time::Spec>'s delimiting the span. A portion can be an hour, half an hour etc. up to a minute, depending on the resolution of the user-defined pattern. C<FTM::Time::Rhythm> is what really defines the interior of C<FTM::Time::Span>. It is basically simply a pair of C<FTM::Time::CalendarWeekCycle> instances bound to the same week pattern selector. These instances have to be kept in sync with the FTM::Time::Spec instances forming the from and until ends of the span. While moving through the calendar, they have to deliver for every day the right object. That object is modified because of daylight saving time adjustment twice in a year (the first covers 23 hours, the second 25).

The day patterns are realized with Bit::Vector. Each bit denotes work (1) or leisure (0). They are copied into another, span-wide Bit::Vector, part of the FTM::Time::Rhythm instance, serving as cache from which FTM::Time::SlicedInSeconds instances are generated to map those portions of a day again to clusters of net or leisure seconds, just to represent the changes between in resolution of seconds. These slices are scanned by FTM::Time::Cursor objects associated with a FTM::Task object, in order to calculate the net working time progress of the task, which is needed to figure out how near the deadline effectively is, and how much, additionally in which direction it diverges from the progress of the task itself. For both measurements it is very important to ignore the leisure phases between start and deadline, so FlowgencyTM can lessen the disposition to ponder about working stuff even when absent from duty (which is considered one of the factors causing the burnout syndrome). Tasks of which the cursor knows they are currently in leisure status are put into the virtual drawer that designed to be opened just when the user explicitly says so.

=end comment

=head1 DEPENDENCIES

=over 4

=item Date::Calc

=item localtime() system-call with DST sensitivity 

=item up-to-date time-zone information

=back

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

