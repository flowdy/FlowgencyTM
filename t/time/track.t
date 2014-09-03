#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
use Test::Exception;
use FindBin qw($Bin);

use Time::Track;
use FlowTime::TestUtil qw(run_tests);
use Scalar::Util qw(weaken);

exit run_tests(@ARGV);

sub test_week_pattern {
    my $tspan;

    $tspan = Time::Span->new( from_date => '1.1.13', until_date => '31.3.', week_pattern => 'Mo-So@!;2n:Mo-Mi@9-17;2n+1:Mi-Fr@9-17;3n-2:Mo-Di,Do-Fr@7-15' );
    is $tspan->rhythm->atoms->to_Enum,
         q{7-15,55-63,79-87,}                        #  1. KW,    Di    Do Fr
        .q{153-161,177-185,201-209,}                 #  2. KW, Mo Di Mi
        .q{369-377,393-401,417-425,}                 #  3. KW,       Mi Do Fr 
        .q{487-495,511-519,559-567,583-591,}         #  4. KW, Mo Di    Do Fr
        .q{705-713,729-737,753-761,}                 #  5. KW,       Mi Do Fr
        .q{825-833,849-857,873-881,}                 #  6. KW, Mo Di Mi
        .q{991-999,1015-1023,1063-1071,1087-1095,}   #  7. KW, Mo Di    Do Fr
        .q{1161-1169,1185-1193,1209-1217,}           #  8. KW, Mo Di Mi
        .q{1377-1385,1401-1409,1425-1433,}           #  9. KW,       Mi Do Fr
        .q{1495-1503,1519-1527,1567-1575,1591-1599,} # 10. KW, Mo Di    Do Fr
        .q{1713-1721,1737-1745,1761-1769,}           # 11. KW,       Mi Do Fr
        .q{1833-1841,1857-1865,1881-1889,}           # 12. KW, Mo Di Mi
        .q{1999-2007,2023-2031,2071-2079,2095-2103}, # 13. KW, Mo Di    Do Fr
        "different week patterns according to calendar week numbers"
    ;
}

sub test_timespans {
    lives_ok {
        Time::Span->new(
            from_date => '2030-12-31',
            week_pattern => 'Mo-So',
            until_date => '+1d'
       );
    } "Time span with absolute from_date and relative until_date";
}

sub test_atoms {
    my $tspan = Time::Span->from_string('21.5.2012--5.8.:Mo-Fr@9-16');
    is $tspan->rhythm->atoms->to_Enum, '9-16,33-40,57-64,81-88,105-112,'
      .'177-184,201-208,225-232,249-256,273-280,345-352,369-376,393-400,'
      .'417-424,441-448,513-520,537-544,561-568,585-592,609-616,681-688,'
      .'705-712,729-736,753-760,777-784,849-856,873-880,897-904,921-928,'
      .'945-952,1017-1024,1041-1048,1065-1072,1089-1096,1113-1120,1185-1192,'
      .'1209-1216,1233-1240,1257-1264,1281-1288,1353-1360,1377-1384,1401-1408,'
      .'1425-1432,1449-1456,1521-1528,1545-1552,1569-1576,1593-1600,1617-1624,'
      .'1689-1696,1713-1720,1737-1744,1761-1768,1785-1792'
      ,'Time span 21.5.--5.8.:Mo-Fr@9-16: rhythm';
    my $tspan_bin = $tspan->rhythm->atoms->to_Bin;
    $tspan->until_date('10.8. 11');
    like $tspan->rhythm->atoms->to_Bin, qr{ \A ( 0{7}1{8}0{9} ){5} 0{24} }xms,
        'tspan expanded by 5 days at the end';
    $tspan->until_date('5.8.');
    is $tspan->rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible';
    $tspan->until_date('3.8.');
    like $tspan->rhythm->atoms->to_Bin, qr{ \A 0{7} 1 }xms,
        'tspan truncated by 2 days at the end'
    ;
    $tspan->until_date('5.8.');
    is $tspan->rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible';
    $tspan->from_date('19.5.');
    like $tspan->rhythm->atoms->to_Bin, qr{ 1 0{57} \z }xms,
        'tspan expand by -2 days at the beginning';
    $tspan->from_date('21.5.');
    is $tspan->rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible';
    $tspan->from_date('26.5.');
    like $tspan->rhythm->atoms->to_Bin, qr{ 1 0{57} \z }xms,
        'tspan expand by +5 days at the beginning';
    $tspan->from_date('21.5.');
    is $tspan->rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible';
    my $tspan2 = Time::Span->from_string('21.5.--5.8.:Mo-Fr@9-17:30');
    is $tspan2->rhythm->hourdiv, 2,
       'another tspan with end of business day 17:30';
    is length($tspan2->rhythm->atoms->to_Bin), length($tspan_bin)*2,
       'double-sized rhythm';
    like $tspan2->rhythm->atoms->to_Bin, qr{ 0 1{17} 0{18} \z }xms,
       'additional half an hour respected at atom level';
}

sub test_track_respect_tspan {

    my $defaultRhythm = Time::Span->new(
        week_pattern => 'Mo-Fr@9-17:30',
        from_date => '30.9.12',
        until_date => '30.9.12',
        description => 'my fill-in, normal time rhythm'
    );

    my $tp = Time::Track->new( name => 'test1', fillIn => $defaultRhythm );

    ok $tp->isa('Time::Track'), "new time track constructed";

    my $span1 = Time::Span->new(from_date => '23.9.12', until_date => '3.10.', week_pattern => 'Mo-Th@10-14:30,15:15-19', description => 'only Monday to Thursday');

    $tp->couple($span1); # [ 2012-09-23 only Monday to Thursday 2012-10-03 ]

    is $tp->start, $span1, 'integrated span #1: start points on it';
    is $tp->end, $span1, 'integrated span #1: end points on it';

    my $span2 = Time::Span->new(from_date => '17.10.12', until_date => '30.10.',
       week_pattern => 'Mo-We@7:30-13:00,Th-Sa@13-18:30', description => 'different working times for different days of the week');
    
    $tp->couple($span2); # | 2012-09-23 only Monday to Thursday 2012-10-03 [ 2012-10-04 00:00:00 my fill-in, normal time rhythm 2012-10-16 23:59:59 | 2012-10-17 different working times for different days of the week 2012-10-30 ]

    is $tp->start, $span1, 'start still references span #1 but';
    is $tp->end, $span2, 'end points to span #2 now';
    my $fillIn1 = $tp->start->next;
    ok $fillIn1->pattern == $defaultRhythm->pattern,
        "in between there is a default rhythm bridge";
 
    my $span3 = Time::Span->new( from_date => '27.8.12', until_date => '15.9.12', week_pattern => 'Mo-Su@!', description => 'holidays' );

    $tp->detect_circular;
    $tp->couple($span3); # [ 2012-08-27 holidays 2012-09-15 | 2012-09-16 00:00:00 my fill-in, normal time rhythm 2012-09-22 23:59:59 ] 2012-09-23 only Monday to Thursday 2012-10-03 | 2012-10-04 00:00:00 my fill-in, normal time rhythm 2012-10-16 23:59:59 | 2012-10-17 different working times for different days of the week 2012-10-30 |
    $tp->detect_circular;

    is $span3, $tp->start, 'another span #3 to the beginning'; 
    ok $span3->next->pattern == $fillIn1->pattern, 'spanning another bridge to span #1';
    isnt $span3->next, $fillIn1, 'however, it is not the one between span #2 and #3';

    my $span4 = Time::Span->new(description => 'partial holidays', from_date => '20.8.12', until_date => '31.8.', week_pattern => 'Mo-Fr@7:30-11;2n:Mo-Th@7-10:30');

    $tp->couple($span4); # [ 2012-08-20 partial holidays 2012-08-31 ] 2012-09-01 holidays 2012-09-15 | 2012-09-16 00:00:00 my fill-in, normal time rhythm 2012-09-22 23:59:59 | 2012-09-23 only Monday to Thursday 2012-10-03 | 2012-10-04 00:00:00 my fill-in, normal time rhythm 2012-10-16 23:59:59 | 2012-10-17 different working times for different days of the week 2012-10-30 |

    is $span4, $tp->start, 'partial holidays';
    is $span4->next, $span3, 'transition to holidays';
    is $span3->from_date->get_qm_timestamp, '2012-09-01', 'span #3 now begins later';

    my $span5 = Time::Span->new(from_date => '7.9.12', until_date => '8.9.', week_pattern => 'Mo-Su@10-10', description => 'non-holidays in holidays');

    $tp->couple($span5); # 2012-08-20 partial holidays 2012-08-31 | 2012-09-01 holidays 2012-09-06 [ 2012-09-07 non-holidays in holidays 2012-09-08 ] 2012-09-09 holidays 2012-09-15 | 2012-09-16 00:00:00 my fill-in, normal time rhythm 2012-09-22 23:59:59 | 2012-09-23 only Monday to Thursday 2012-10-03 | 2012-10-04 00:00:00 my fill-in, normal time rhythm 2012-10-16 23:59:59 | 2012-10-17 different working times for different days of the week 2012-10-30 |

    is $span5, $span4->next->next, 'non-holidays in holidays integriert';
    is $span4->next->pattern, $span5->next->pattern, 'spans before and after had once been identical';

    my $span6 = Time::Span->new(from_date => '22.', until_date => '24.9.12', week_pattern => 'Mo-Su@17-17', description => 'standing in for someone over the week-end');

    $tp->couple($span6); # 2012-08-20 partial holidays 2012-08-31 | 2012-09-01 holidays 2012-09-06 | 2012-09-07 non-holidays in holidays 2012-09-08 | 2012-09-09 holidays 2012-09-15 | 2012-09-16 00:00:00 my fill-in, normal time rhythm 2012-09-21 23:59:59 [ 2012-09-22 standing in for someone over the week-end 2012-09-24 ] 2012-09-25 only Monday to Thursday 2012-10-03 | 2012-10-04 00:00:00 my fill-in, normal time rhythm 2012-10-16 23:59:59 | 2012-10-17 different working times for different days of the week 2012-10-30 |

    is $span6, $span5->next->next->next, 'integrated span #6';
    is $span5->next->next->until_date->get_qm_timestamp, '2012-09-21', 'adaption of the until_date of the fill-in bridge before';
    is $span6->next->from_date->get_qm_timestamp, '2012-09-25', 'adaption of the from_date of the span after';
    ok $span3->next->pattern != $span6->next->pattern, 'spans before and after had always been different';

    my $span7 = Time::Span->new(description => 'coverage of a nice co-worker\'s night-shift', from_date => '30.10.', until_date => '31.10.2012', week_pattern => 'Mo-Fr@21:30-22,0-4:30');

    $tp->couple($span7); # 2012-08-20 partial holidays 2012-08-31 | 2012-09-01 holidays 2012-09-06 | 2012-09-07 non-holidays in holidays 2012-09-08 | 2012-09-09 holidays 2012-09-15 | 2012-09-16 00:00:00 my fill-in, normal time rhythm 2012-09-21 23:59:59 | 2012-09-22 standing in for someone over the week-end 2012-09-24 | 2012-09-25 only Monday to Thursday 2012-10-03 | 2012-10-04 00:00:00 my fill-in, normal time rhythm 2012-10-16 23:59:59 | 2012-10-17 different working times for different days of the week 2012-10-29 [ 2012-10-30 coverage of a nice co-worker's night-shift 2012-10-31 ]

    is $span7, $span2->next, 'integrated night-shift';
    is $span7, $tp->end, 'night-shift at the end';

    # TODO: Deckungsgleiche Abgrenzungen
    # TODO: Wenn neue Spannen mehrere bestehende Spannen überdecken, müssen diese im Speicher freigegeben werden.
    is $span2->until_date->get_qm_timestamp, '2012-10-29', 'adaption of until_date to the span before';
    ok !$span7->next, 'nothing succeeds span #7';

    my $s5next = $span5->next;
    weaken($_) for $span3, $span4, $span5, $s5next;

    my $span8 = Time::Span->new(description => 'overwriting', week_pattern => 'Mo-Su@!0-23', from_date => '20.8.', until_date => '19.9.12');

    $tp->couple($span8); # [ 2012-08-20 overwriting 2012-09-19 ] 2012-09-20 00:00:00 my fill-in, normal time rhythm 2012-09-21 | 2012-09-22 standing in for someone over the week-end 2012-09-24 | 2012-09-25 only Monday to Thursday 2012-10-03 | 2012-10-04 00:00:00 my fill-in, normal time rhythm 2012-10-16 23:59:59 | 2012-10-17 different working times for different days of the week 2012-10-29 [ 2012-10-30 coverage of a nice co-worker's night-shift 2012-10-31 ]

    is $span3, undef, 'span #8 has overwritten (deleted) span #3';
    is $span4, undef, '... and span #4';
    is $span5, undef, '... und span #5';
    is $s5next, undef, '... and the second part of span #3';
    is $span8, $tp->start, 'span #8 at the start';

    my $s8next = $span8->next;
    weaken($s8next); # [ 2012-08-20 overwriting 2012-09-19 ] 2012-09-20 00:00:00 my fill-in, normal time rhythm 2012-09-21 23:59:59 | 2012-09-22 standing in for someone over the week-end 2012-09-24 | 2012-09-25 only Monday to Thursday 2012-10-03 | 2012-10-04 00:00:00 my fill-in, normal time rhythm 2012-10-16 23:59:59 | 2012-10-17 different working times for different days of the week 2012-10-29 | 2012-10-30 coverage of a nice co-worker's night-shift 2012-10-31 |
    my $span9 = Time::Span->new( description => 'overwriting II', from_date => '20.9.', until_date => '2012-09-21', week_pattern => 'Mo-Fr@13' );

    $tp->couple($span9); # | 2012-08-20 overwriting 2012-09-19 [ 2012-09-20 overwriting II 2012-09-21 ] 2012-09-22 standing in for someone over the week-end 2012-09-24 | 2012-09-25 only Monday to Thursday 2012-10-03 | 2012-10-04 00:00:00 my fill-in, normal time rhythm 2012-10-16 23:59:59 | 2012-10-17 different working times for different days of the week 2012-10-29 | 2012-10-30 coverage of a nice co-worker's night-shift 2012-10-31 |

    is $span8->next, $span9, 'span #9 replaces my fill-in, normal time rhythm';
    is $span9->next, $span6, '  precisely';
    is $s8next, undef, 'my fill-in, normal time rhythm overwritten, i.e. deleted';

    my @expected_state = (
     {
       'description' => 'overwriting',
       'from_date' => '2012-08-20',
       'rhythm' => {
          'atomic_enum' => '',
          'description' => 'Mo-Su@!0-23',
          'from_week_day' => '34/12, Mo',
          'mins_per_unit' => 60,
          #'patternId' => 189380856,
          'until_week_day' => '38/12, We',
       },
       'until_date' => '2012-09-19',
     },{
       'description' => 'overwriting II',
       'from_date' => '2012-09-20',
       'rhythm' => {
          'atomic_enum' => '13,37',
          'description' => 'Mo-Fr@13',
          'from_week_day' => '38/12, Th',
          'mins_per_unit' => 60,
          #'patternId' => 189336500,
          'until_week_day' => '38/12, Fr',
       },
       'until_date' => '2012-09-21',
     },{
       'description' => 'standing in for someone over the week-end',
       'from_date' => '2012-09-22',
       'rhythm' => {
          'atomic_enum' => '17,41,65',
          'description' => 'Mo-Su@17-17',
          'from_week_day' => '38/12, Sa',
          'mins_per_unit' => 60,
          #'patternId' => 189397092,
          'until_week_day' => '39/12, Mo',
       },
       'until_date' => '2012-09-24',
     },{
       'description' => 'only Monday to Thursday',
       'from_date' => '2012-09-25',
       'rhythm' => {
          'atomic_enum' => '40-57,61-79,136-153,157-175,232-249,253-271,616-633,637-655,712-729,733-751,808-825,829-847',
          'description' => 'Mo-Th@10-14:30,15:15-19',
          'from_week_day' => '39/12, Tu',
          'mins_per_unit' => 15,
          #'patternId' => 189382776,
          'until_week_day' => '40/12, We',
       },
       'until_date' => '2012-10-03',
     },{
       'description' => 'my fill-in, normal time rhythm',
       'from_date' => '2012-10-04',
       'rhythm' => {
          'atomic_enum' => '18-34,66-82,210-226,258-274,306-322,354-370,402-418,546-562,594-610',
          'description' => 'Mo-Fr@9-17:30',
          'from_week_day' => '40/12, Th',
          'mins_per_unit' => 30,
          #'patternId' => 189383304,
          'until_week_day' => '42/12, Tu',
       },
       'until_date' => '2012-10-16',
     },{
       'description' => 'different working times for different days of the week',
       'from_date' => '2012-10-17',
       'rhythm' => {
          'atomic_enum' => '15-25,74-84,122-132,170-180,255-265,303-313,351-361,410-420,458-468,506-516,593-603', # last enum: shifted +2x30min. DST adj.
          'description' => 'Mo-We@7:30-13:00,Th-Sa@13-18:30',
          'from_week_day' => '42/12, We',
          'mins_per_unit' => 30,
          #'patternId' => 189383984,
          'until_week_day' => '44/12, Mo',
       },
       'until_date' => '2012-10-29',
     },{
       'description' => 'coverage of a nice co-worker\'s night-shift',
       'from_date' => '2012-10-30',
       'rhythm' => {
          'atomic_enum' => '0-8,43-45,48-56,91-93',
          'description' => 'Mo-Fr@21:30-22,0-4:30',
          'from_week_day' => '44/12, Tu',
          'mins_per_unit' => 30,
          #'patternId' => 189383924,
          'until_week_day' => '44/12, We',
       },
       'until_date' => '2012-10-31',
     }
    );

    is_deeply
        [grep { delete $_->{rhythm}{patternId} } $tp->dump],
        \@expected_state,
        "over-all state after all couplings";

    my $ts0 = Time::Point->parse_ts('25.10.12 12:00:00');
    subtest_seek_last_net_second_timestamp(
        $tp, $ts0, 19800 => '2012-10-26 13:00:00',
        'first second of work-day at full hour'
    );
    subtest_seek_last_net_second_timestamp(
        $tp, $ts0, 90_000 => '2012-10-30 03:00:00',
        'final timestamp covered by slice'
    );
    
    my $tspan90 = Time::Span->from_string('25.:Mo-Su@15');
    my $ts1 = Time::Point->parse_ts("14:00")->fill_in_assumptions;
    is $tspan90->rhythm->count_absence_between_net_seconds($ts1, 1), 3600,
       "count absence before one net seconds";
    is $tspan90->rhythm->count_absence_between_net_seconds($ts1, 3600), 3600,
       "count absence among net seconds over an hour";
    is $tspan90->rhythm->count_absence_between_net_seconds($ts1, 3601), 86400,
       "count absence among net seconds over a day";
    subtest_seek_last_net_second_timestamp(
        $tp, $ts0, 130_000 => '2012-11-01 11:06:40',
         '... or, respectively, in the fill-in'
    );

    my $ts2 = Time::Point->parse_ts("30.10.12 23");
    subtest_seek_last_net_second_timestamp(
        $tp, $ts2, 0 => '2012-10-31 00:00:00',
        "leisure seconds equal to next net_second",
    );

    
    my $tspan91 =  Time::Span->from_string('25.:Mo-Su@23-0');
    my $ts3 = Time::Point->parse_ts("23:15")->fill_in_assumptions;
    is $tspan91->rhythm->count_absence_between_net_seconds($ts3, 6300), 0,
       "net seconds transition from one day to the other";
    is $tspan91->rhythm->count_absence_between_net_seconds($ts3, 6301), 79200,
       " ... plus one net second again in the night";

    #  TODO: {
    #      local $TODO = 'Time::Track->lock(), unlock(), demand_protect() und '
    #                  . 'release_protection() noch zu entwickeln';
    #  }

    #  TODO: {
    #      local $TODO = 'Time::Slice::VerticalScanner noch nicht implementiert';
    #      require_ok 'Time::Slice::VerticalScanner';
    # }

    my @spans; my $next = $tp->start;
    $tp->detect_circular;
    do { push @spans, weaken($next) } while $next = $next->next; 
    $tp->reset;
    my $num =()= grep !defined, @spans;
    ok $num <= 1, 'timeline reset';
}
sub subtest_seek_last_net_second_timestamp {
    my ($tp, $ts, $n, $end_ts, $test_name) = @_;
    $ts = $tp->timestamp_of_nth_net_second_since($n, $ts);
    is $ts &&= $ts.q{}, $end_ts, $test_name; 
}

sub test_time_calendarweekcycle {
    use Time::CalendarWeekCycle;

    my %callbacks = (
        selector => sub { qw(Mo Di Mi Do Fr Sa So) },
        dst_handler => sub {
            my ($wd, $hr, $shift) = @_;
            "$wd\[$hr, $shift\]"
        },
        monday_at_index => 0,
    );

    my @initial_date = (2013, 5, 25);
    my $cw = Time::CalendarWeekCycle->new(
        @initial_date,
        %callbacks,
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
    is_deeply [$cw->_dow_week_year], [2,53,2009],
        'going back to a week no. 53';
    $cw->move_by_days(4);
    is $cw->day_of_week, 7, 'day method says we have Sunday (which is in 2010)';
    is $cw->year_of_thursday, 2009, 'but year() outputs the year covering the Thursday of the week in question';
    $cw = Time::CalendarWeekCycle->new(@initial_date, %callbacks)->move_by_days(953);
    is_deeply [map { $cw->$_() } qw/day_of_week week_num year_of_thursday/], [7,53,2015],
        'going forward to a week no. 53';
    $cw->move_by_days(-70);
    is $cw->day_obj, "So[3, -1]", "daylight saving time adjustment in Fall";
    $cw->move_by_days(-210);
    is $cw->day_obj, "So[2, 1]", "daylight saving time adjustment in Spring";
}

