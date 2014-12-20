#!/usr/bin/perl
use strict;

use FTM::TestUtil qw(run_tests);
use Test::More;
use FTM::Time::Track;
use FTM::Time::Cursor;

run_tests(@ARGV);

sub test_progressing_cursor {
    my $curprof = FTM::Time::Track->new(
        name => 'testrack',
        fillIn => FTM::Time::Span->new(
            description => 'regular office hours',
            from_date => '3.10.2012',
            until_date => '3.10.',
            week_pattern => 'Mo-Fr@9-17',
        ),
    );
    my $cursor = FTM::Time::Cursor->new(
        start_ts => FTM::Time::Point->parse_ts('27.6.2012'),
        timestages => [{ track => $curprof, until_date => '15.7.' }]
    );

    is $cursor->start_ts.q{}, '2012-06-27', 'cursor adjusted from date';
    my $ts = FTM::Time::Point->parse_ts('7.7.2012');
    my $pos = $cursor->update($ts->epoch_sec);
    $ts = FTM::Time::Point->from_epoch($ts->epoch_sec+43200);
    my $pos2 = $cursor->update($ts);
    is $pos, $pos2, 'elapsed presence time should not increase until '.$ts;
    $ts = FTM::Time::Point->from_epoch($ts->epoch_sec+162000);
    my %pos2 = $cursor->update($ts->epoch_sec);
    is $pos, $pos2{current_pos}, 'it does neither at '.$ts;
    $pos2 = $cursor->update($ts->epoch_sec+1);
    cmp_ok $pos, '<', $pos2, 'but just a second later, at 9:00:01am, it grows';

    my $tspan = FTM::Time::Span->from_string('21.5.2012--5.8.:Mo-Fr@9-16');
    my $tspan2 = $tspan->new_shared_rhythm( '8.' => '21.8.2012' );
    is $tspan2->rhythm->atoms->bit_test(83), 0,
       'copied and moved tspan, test 1';
    is $tspan2->rhythm->atoms->bit_test(63), 1,
       'copied and moved tspan, test 2';

    my $ts2 = FTM::Time::Point->parse_ts('2012-05-21 17:00:00');
    $cursor->start_ts(FTM::Time::Point->parse_ts('12.5.'));
    $cursor->update($ts);
    my %pos = $cursor->update($ts2);
    $curprof->couple($tspan);
    %pos2 = $cursor->update($ts2->epoch_sec+3601);

    is $pos{elapsed_pres}, $pos2{elapsed_pres},
       'there is a difference after coupling a new tspan into the timetrack';
    is $pos2{old}{elapsed_pres} - $pos2{elapsed_pres}, 3600,
       "Subhash 'old' on first FTM::Time::Cursor->update() call after the couple()";

    ok !$pos{overdue}, "cursor before due-date";

    %pos = $cursor->update(FTM::Time::Point->parse_ts('5.8.2012'));
    ok $pos{remaining_pres} < 0, "cursor past due-date";
}

sub test_multitrack_cursor {

    use Date::Calc qw(Today Monday_of_Week Week_of_Year
                      Day_of_Week Add_Delta_Days
                     );

    my $track1 = FTM::Time::Track->new({ name => 'First', week_pattern => 'Mo-Fr@9-17,!12' });

    my $track2 = FTM::Time::Track->new({
        name => 'Second',
        week_pattern => 'Mo-Fr@9-12',
        successor => $track1,
    });

    for my $ydiff ( -1, 0, 1 ) {
        my @date = Today();
        $date[0] += $ydiff; # increment/decrement year
        my @monday = Monday_of_Week( Week_of_Year(@date) );
        my $week_end = sprintf "%d-%02d-%02d", Day_of_Week(@date)>5 ? @date
                                             : Add_Delta_Days(@monday, 5)
                                             ;
        my @friday1_md = Add_Delta_Days(@monday, 4);
        my @friday2_md = Add_Delta_Days(@monday, 18); # 2 wk track 2

        my $monday = sprintf "%4d-%02d-%02d",@monday;
        my ($friday, $fr_plus2w)
            = map { sprintf("%4d-%02d-%02d", @$_) } \@friday1_md, \@friday2_md
        ;

        my $fr_plus1w = sprintf "%4d-%02d-%02d", Add_Delta_Days(@monday, 11);
        $track2->until_latest($fr_plus1w);

        my $cursor = FTM::Time::Cursor->new(
            start_ts => FTM::Time::Point->parse_ts($monday),
            timestages => [
                { track => $track1, until_date => $friday },
                { track => $track2, until_date => $fr_plus2w },
            ]
        );

        my $pos = $cursor->update( FTM::Time::Point->parse_ts("$week_end 12:00") );
        is $pos, 0.4, "cursor from $monday over a track until $friday, then "
                    . "over another with successor until $fr_plus2w";

        my $wednesday = FTM::Time::Point->parse_ts(
            sprintf "%4d-%02d-%02d 12:30", Add_Delta_Days(@monday, 2)
        );
        my ($wednesday_2w, $wednesday_3w)
            = map {
                  sprintf "%4d-%02d-%02d 11:00:00",
                      Add_Delta_Days(@monday, $_)
              } 16, 16+7
            ;

        my $estim_ts = $cursor->timestamp_of_nth_net_second_since(
            59 * 3600, $wednesday
        );
        is "$estim_ts", $wednesday_2w, "estimation over two weeks";

        $estim_ts = $cursor->timestamp_of_nth_net_second_since(
            99 * 3600, $wednesday
        );
        is "$estim_ts", $wednesday_3w, "estimation over three weeks";

    }

}

