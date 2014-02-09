#!/usr/bin/perl
use strict;

use FlowTime::TestUtil qw(run_tests);
use Test::More;
use Time::Track;
use Time::Cursor;

run_tests(@ARGV);

sub test_progressing_cursor {
    my $curprof = Time::Track->new(
        name => 'testrack',
        fillIn => Time::Span->new(
            description => 'regular office hours',
            from_date => '3.10.2012',
            until_date => '3.10.',
            week_pattern => 'Mo-Fr@9-17',
        ),
    );
    my $cursor = Time::Cursor->new(
        start_ts => Time::Point->parse_ts('27.6.2012'),
        timestages => [{ track => $curprof, until_date => '15.7.' }]
    );

    is $cursor->start_ts.q{}, '2012-06-27', 'cursor adjusted from date';
    my $ts = Time::Point->parse_ts('7.7.2012');
    my $pos = $cursor->update($ts->epoch_sec);
    $ts = Time::Point->from_epoch($ts->epoch_sec+43200);
    my $pos2 = $cursor->update($ts->epoch_sec);
    is $pos, $pos2, 'elapsed presence time should not increase until '.$ts;
    $ts = Time::Point->from_epoch($ts->epoch_sec+162000);
    my %pos2 = $cursor->update($ts->epoch_sec);
    is $pos, $pos2{current_pos}, 'it does neither at '.$ts;
    $pos2 = $cursor->update($ts->epoch_sec+1);
    cmp_ok $pos, '<', $pos2, 'but just a second later, at 9:00:01am, it grows';

    my $tspan = Time::Span->from_string('21.5.2012--5.8.:Mo-Fr@9-16');
    my $tspan2 = $tspan->new_shared_rhythm( '8.' => '21.8.2012' );
    is $tspan2->rhythm->atoms->bit_test(83), 0,
       'copied and moved tspan, test 1';
    is $tspan2->rhythm->atoms->bit_test(63), 1,
       'copied and moved tspan, test 2';

    my $ts2 = Time::Point->parse_ts('2012-05-21 17:00:00');
    $cursor->start_ts(Time::Point->parse_ts('12.5.'));
    $cursor->update($ts);
    my %pos = $cursor->update($ts2);
    $curprof->couple($tspan);
    %pos2 = $cursor->update($ts2->epoch_sec+3601);

    is $pos{elapsed_pres}, $pos2{elapsed_pres},
       'there is a difference after coupling a new tspan into the timetrack';
    is $pos2{old}{elapsed_pres} - $pos2{elapsed_pres}, 3600,
       "Subhash 'old' on first Time::Cursor->update() call after the couple()";
}

sub test_multitrack_cursor {

    use Date::Calc qw(Today Monday_of_Week Week_of_Year Day_of_Week Add_Delta_Days);

    my $track1 = Time::Track->new('Mo-Fr@9-17,!12', { name => 'First' });
    my $track2 = Time::Track->new('Mo-Fr@9-12', {
        name => 'Second',
        successor => $track1,
    });

    for ( -1, 0, 1 ) {
        my @date = Today();
        $date[0] += $_; # increment/decrement year
        my @monday = Monday_of_Week( Week_of_Year(@date) );
        my $week_end = sprintf "%d-%02d-%02d", Day_of_Week(@date)>5 ? @date
                                             : Add_Delta_Days(@monday, 5)
                                             ;
        (undef, my @friday1_md) = Add_Delta_Days(@monday, 4);
        (undef, my @friday2_md) = Add_Delta_Days(@monday, 18); # 2 wk track 2

        my $monday = sprintf "%4d-%02d-%02d",@monday;
        my ($friday, $fr_plus2w)
            = map { sprintf("%02d-%02d", @$_) } \@friday1_md, \@friday2_md
        ;

        my $fr_plus1w = sprintf "%4d-%02d-%02d", Add_Delta_Days(@monday, 11);
        $track2->until_latest($fr_plus1w);

        my $cursor = Time::Cursor->new(
            start_ts => Time::Point->parse_ts($monday),
            timestages => [
                { track => $track1, until_date => $friday },
                { track => $track2, until_date => $fr_plus2w },
            ]
        );

        $DB::single++;
        my $pos = $cursor->update( Time::Point->parse_ts("$week_end 12:00") );
        is $pos, 0.4, "cursor from $monday over a track until $friday, then "
                    . "over another with successor until $fr_plus2w";

    }
}

