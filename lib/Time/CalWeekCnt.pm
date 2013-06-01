#!/usr/bin/perl
use strict;

package Time::CalWeekCnt;
use Moose;
use Date::Calc qw/Week_of_Year Weeks_in_Year Day_of_Week/;
use POSIX qw(floor);
use Scalar::Util qw(blessed);
use Carp qw(croak);

has [qw/dow week_num year/] => ( is => 'ro', isa => 'Int' );

has _selector => ( is => 'ro', isa => 'CodeRef', init_arg => undef );

around BUILDARGS => sub {
    my ($orig, $class, @args) = @_;
    
    if ( grep(!/\D/, @args[0..2]) == 3 ) {
        my @date = splice @args, 0, 3;
        my ($week_num, $year) = Week_of_Year(@date);
        push @args, (
            dow => Day_of_Week(@date)%7,
            week_num => $week_num,
            year => $year,
        );
    }

    $class->$orig(@args);
};

sub BUILD {
    my ($self, $args) = @_;

    my ($sel, $week, $pattern) = ($args->{selector} // return, 0, undef);

    $self->{_selector} = sub {
        my ($week_num) = @_;
        return $sel     if !@_;
        return $pattern if $week == $week_num;
        return $pattern = $sel->($week = $week_num);
    };

}

sub stringify {
    my $self = shift;
    my ($week, $year, $day) = map { $self->$_ } qw/week_num year dow/; 
    return sprintf '%d/%d, %s',
        $week, substr($year, 2, 2), [qw|Su Mo Tu We Th Fr Sa|]->[$day]
    ;
}

sub move_by_days {
    my ($self, $days) = @_;

    if ( !wantarray ) {
        @{$self}{qw/dow week_num year/} = &_move_by_days;
        return $self;
    }

    my $sel = $self->_selector
        // croak 'list context mode not supported - no selector';
    my $step = $days/abs($days);
    my (@day_patterns);

    while ( $days ) {
        @{$self}{qw/dow week_num year/} = _move_by_days($self, $step);
        push @day_patterns, $sel->($self->{week_num})->[$self->{dow}];
    }
    continue {
        $days -= $step;
    }

    return @day_patterns;
}

sub another_moved_by_days {
    my ($dow, $week_num, $year) = &_move_by_days;
    my $self = shift;
    return (blessed $self)->new(
        dow => $dow, week_num => $week_num, year => $year,
        selector => $self->_selector
    );
}

sub _move_by_days {
    my ($self, $days) = @_;
    my $dow      = $self->dow + $days;
    my $week_num = $self->week_num + floor($dow/7);
    my $year     = $self->year;
    until ( $week_num < 53 ) {
        $week_num -= Weeks_in_Year($year)
            or do { $week_num = 53; last };
    } continue { $year++ }
    until ( $week_num > 0 ) {
        $week_num += Weeks_in_Year(--$year);
    }
    $dow %= 7;
    return $dow, $week_num, $year;
}

__PACKAGE__->meta->make_immutable;

return 1 if caller;

package main;

use Test::More;

my $cw = Time::CalWeekCnt->new(2013,5,25);
is $cw->week_num, 21, 'day of the week, initial check';
$cw->move_by_days(-9);
is $cw->week_num, 20, 'move into previous week';
is $cw->dow, 3, 'day of the week is Thursday (num. 3)';
my $cw2 = $cw->another_moved_by_days(9);
is $cw2->dow, 5, 'return safe: copy has day of week Saturday (5)';
is $cw2->week_num, 21, 'return safe: copy has orig. week number';
$cw->move_by_days(-1233);
is_deeply [map { $cw->$_() } qw/dow week_num year/], [2,53,2009],
    'going back to a week no. 53';
$cw->move_by_days(4);
is $cw->dow, 6, 'day method says we have Sunday (which is in 2010)';
is $cw->year, 2009, 'but year() outputs the year covering the Thursday of the week in question';
$cw = Time::CalWeekCnt->new(2013,5,25)->move_by_days(953);
is_deeply [map { $cw->$_() } qw/dow week_num year/], [6,53,2015],
    'going forward to a week no. 53';

done_testing;
