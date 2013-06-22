#!/usr/bin/perl
use strict;
use warnings;

use Test::More;

use lib qw(../lib/);
use Time::Slice;
use Time::Profile;
use Time::Cursor;
use Scalar::Util qw(weaken);

exit run_tests(@ARGV);

sub run_tests {
    my @args  = @_;

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                unless my $func = __PACKAGE__->can( 'test_' . $name );
            $func->();
        }

        done_testing;
        return 0;
    }

    no strict 'refs';
    &$_() for grep /^test_/, keys %{main::};
         
    done_testing;
    return 0;
}

sub test_week_pattern {
    my $tspan;

    $tspan = Time::Span->new( from_date => '1.1.13', until_date => '31.3.', week_pattern => 'Mo-So@!;2n:Mo-Mi@9-17;2n+1:Mi-Fr@9-17;3n-2:Mo-Di,Do-Fr@7-15' );
    is $tspan->_rhythm->atoms->to_Enum,
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
        "verschiedene Wochenmuster je nach Nummer der Kalenderwoche"
    ;
}

sub test_atoms {
    my $tspan = Time::Span->from_string('21.5.2012--5.8.:Mo-Fr@9-16');
    is $tspan->_rhythm->atoms->to_Enum, '9-16,33-40,57-64,81-88,105-112,'
      .'177-184,201-208,225-232,249-256,273-280,345-352,369-376,393-400,'
      .'417-424,441-448,513-520,537-544,561-568,585-592,609-616,681-688,'
      .'705-712,729-736,753-760,777-784,849-856,873-880,897-904,921-928,'
      .'945-952,1017-1024,1041-1048,1065-1072,1089-1096,1113-1120,1185-1192,'
      .'1209-1216,1233-1240,1257-1264,1281-1288,1353-1360,1377-1384,1401-1408,'
      .'1425-1432,1449-1456,1521-1528,1545-1552,1569-1576,1593-1600,1617-1624,'
      .'1689-1696,1713-1720,1737-1744,1761-1768,1785-1792'
      ,'Time span 21.5.--5.8.:Mo-Fr@9-16: rhythm';
    my $tspan_bin = $tspan->_rhythm->atoms->to_Bin;
    $tspan->until_date('10.8. 11');
    like $tspan->_rhythm->atoms->to_Bin, qr{ \A ( 0{7}1{8}0{9} ){5} 0{24} }xms,
        'tspan expanded by 5 days at the end';
    $tspan->until_date('5.8.');
    is $tspan->_rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible';
    $tspan->until_date('3.8.');
    like $tspan->_rhythm->atoms->to_Bin, qr{ \A 0{7} 1 }xms,
        'tspan truncated by 2 days at the end'
    ;
    $tspan->until_date('5.8.');
    is $tspan->_rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible';
    $tspan->from_date('19.5.');
    like $tspan->_rhythm->atoms->to_Bin, qr{ 1 0{57} \z }xms,
        'tspan expand by -2 days at the beginning';
    $tspan->from_date('21.5.');
    is $tspan->_rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible';
    $tspan->from_date('26.5.');
    like $tspan->_rhythm->atoms->to_Bin, qr{ 1 0{57} \z }xms,
        'tspan expand by +5 days at the beginning';
    $tspan->from_date('21.5.');
    is $tspan->_rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible';
    my $tspan2 = Time::Span->from_string('21.5.--5.8.:Mo-Fr@9-17:30');
    is $tspan2->_rhythm->hourdiv, 2,
       'another tspan with end of business day 17:30';
    is length($tspan2->_rhythm->atoms->to_Bin), length($tspan_bin)*2,
       'double-sized rhythm';
    like $tspan2->_rhythm->atoms->to_Bin, qr{ 0 1{17} 0{18} \z }xms,
       'additional half an hour respected at atom level';
}

sub test_progressing_cursor {
    my $curprof = Time::Profile->new(
        fillIn => Time::Span->new(
            description => 'reguläre Bürozeiten',
            from_date => '3.10.2012',
            until_date => '3.10.',
            week_pattern => 'Mo-Fr@9-17',
        ),
    );
    my $cursor = Time::Cursor->new(
        timeprofile => $curprof,
        run_from => Time::Point->parse_ts('27.6.2012'),
        run_until => Time::Point->parse_ts('15.7.'),
    );

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
    is $tspan2->_rhythm->atoms->bit_test(83), 0,
       'copied and moved tspan, test 1';
    is $tspan2->_rhythm->atoms->bit_test(63), 1,
       'copied and moved tspan, test 2';

    my $ts2 = Time::Point->parse_ts('2012-05-21 17:00:00');
    $cursor->run_from(Time::Point->parse_ts('12.5.'));
    $cursor->update($ts);
    my %pos = $cursor->update($ts2);
    $curprof->respect($tspan);
    %pos2 = $cursor->update($ts2->epoch_sec+3601);

    is $pos{elapsed_pres}, $pos2{elapsed_pres},
       'Unterschied nach Integration einer variierten Zeitspanne';
    is $pos2{old}{elapsed_pres} - $pos2{elapsed_pres}, 3600,
       "Subhash 'old' beim ersten Time::Curso->update()-Aufruf nach einem Respect.";
}

sub test_profile_respect_tspan {
    my $defaultRhythm = Time::Span->new(
        week_pattern => 'Mo-Fr@9-17:30',
        from_date => '30.9.12',
        until_date => '30.9.12',
        description => 'Lückenfüller'
    );

    my $tp = Time::Profile->new( name => 'test1', fillIn => $defaultRhythm );

    ok $tp->isa('Time::Profile'), "Zeitlinie erstellt";

    my $span1 = Time::Span->new(from_date => '23.9.12', until_date => '3.10.', week_pattern => 'Mo-Do@10-14:30,15:15-19', description => 'nur Montags bis Donnerstags');

    $tp->respect($span1); # [ 2012-09-23 nur Montags bis Donnerstags 2012-10-03 ]

    is $tp->start, $span1, 'Span 1 integriert: start-Zeiger zeigt darauf';
    is $tp->end, $span1, 'Span 1 integriert: end-Zeiger zeigt darauf';

    my $span2 = Time::Span->new(from_date => '17.10.12', until_date => '30.10.',
       week_pattern => 'Mo-Mi@7:30-13:00,Do-Sa@13-18:30', description => 'Für verschiedene Tage der Woche verschiedene Arbeitszeiten');
    
    $tp->respect($span2); # | 2012-09-23 nur Montags bis Donnerstags 2012-10-03 [ 2012-10-04 00:00:00 Lückenfüller 2012-10-16 23:59:59 | 2012-10-17 Für verschiedene Tage der Woche verschiedene Arbeitszeiten 2012-10-30 ]

    is $tp->start, $span1, 'Span1 bleibt auf Start, während';
    is $tp->end, $span2, 'Span2 nun den Schluss markiert';
    my $fillIn1 = $tp->start->next;
    ok $fillIn1->pattern == $defaultRhythm->pattern,
       "Dazwischen ist eine Brücke mit dem Standardrhythmus";
 
    my $span3 = Time::Span->new( from_date => '27.8.12', until_date => '15.9.12', week_pattern => 'Mo-So@!', description => 'Urlaub' );

    $tp->detect_circular;
    $tp->respect($span3); # [ 2012-08-27 Urlaub 2012-09-15 | 2012-09-16 00:00:00 Lückenfüller 2012-09-22 23:59:59 ] 2012-09-23 nur Montags bis Donnerstags 2012-10-03 | 2012-10-04 00:00:00 Lückenfüller 2012-10-16 23:59:59 | 2012-10-17 Für verschiedene Tage der Woche verschiedene Arbeitszeiten 2012-10-30 |
    $tp->detect_circular;

    is $span3, $tp->start, 'Weitere Span3 an den Anfang'; 
    ok $span3->next->pattern == $fillIn1->pattern, 'Zur Span1 eine weitere Brücke';
    isnt $span3->next, $fillIn1, 'Es handelt sich aber nicht um die zwischen Span2 und Span3';

    my $span4 = Time::Span->new(description => 'Urlaubsteilzeit', from_date => '20.8.12', until_date => '31.8.', week_pattern => 'Mo-Fr@7:30-11;2n:Mo-Do@7-10:30');

    $tp->respect($span4); # [ 2012-08-20 Urlaubsteilzeit 2012-08-31 ] 2012-09-01 Urlaub 2012-09-15 | 2012-09-16 00:00:00 Lückenfüller 2012-09-22 23:59:59 | 2012-09-23 nur Montags bis Donnerstags 2012-10-03 | 2012-10-04 00:00:00 Lückenfüller 2012-10-16 23:59:59 | 2012-10-17 Für verschiedene Tage der Woche verschiedene Arbeitszeiten 2012-10-30 |

    is $span4, $tp->start, 'Urlaubsteilzeit';
    is $span4->next, $span3, 'Übergang zu Urlaub';
    is $span3->from_date->get_qm_timestamp, '2012-09-01', 'Span3: Beginn später';

    my $span5 = Time::Span->new(from_date => '7.9.12', until_date => '8.9.', week_pattern => 'Mo-So@10-10', description => 'Urlaubspause');

    $tp->respect($span5); # 2012-08-20 Urlaubsteilzeit 2012-08-31 | 2012-09-01 Urlaub 2012-09-06 [ 2012-09-07 Urlaubspause 2012-09-08 ] 2012-09-09 Urlaub 2012-09-15 | 2012-09-16 00:00:00 Lückenfüller 2012-09-22 23:59:59 | 2012-09-23 nur Montags bis Donnerstags 2012-10-03 | 2012-10-04 00:00:00 Lückenfüller 2012-10-16 23:59:59 | 2012-10-17 Für verschiedene Tage der Woche verschiedene Arbeitszeiten 2012-10-30 |

    is $span5, $span4->next->next, 'Urlaubspause integriert';
    is $span4->next->pattern, $span5->next->pattern, 'Vorspanne und Nachspanne waren mal identisch';

    my $span6 = Time::Span->new(from_date => '22.', until_date => '24.9.12', week_pattern => 'Mo-So@17-17', description => 'Mal kurz eingesprungen übers Wochenende');

    $tp->respect($span6); # 2012-08-20 Urlaubsteilzeit 2012-08-31 | 2012-09-01 Urlaub 2012-09-06 | 2012-09-07 Urlaubspause 2012-09-08 | 2012-09-09 Urlaub 2012-09-15 | 2012-09-16 00:00:00 Lückenfüller 2012-09-21 23:59:59 [ 2012-09-22 Mal kurz eingesprungen übers Wochenende 2012-09-24 ] 2012-09-25 nur Montags bis Donnerstags 2012-10-03 | 2012-10-04 00:00:00 Lückenfüller 2012-10-16 23:59:59 | 2012-10-17 Für verschiedene Tage der Woche verschiedene Arbeitszeiten 2012-10-30 |

    is $span6, $span5->next->next->next, 'Span6 integriert';
    is $span5->next->next->until_date->get_qm_timestamp, '2012-09-21', 'Anpassung des Enddatums der Defaultspanne davor';
    is $span6->next->from_date->get_qm_timestamp, '2012-09-25', 'Anpassung des Anfangsdatums der Spanne danach';
    ok $span3->next->pattern != $span6->next->pattern, 'Spannen davor und danach immer verschieden gewesen';

    my $span7 = Time::Span->new(description => '1 Nachtschicht für die nette Kollegin', from_date => '30.10.', until_date => '31.10.2012', week_pattern => 'Mo-Fr@21:30-22,0-4:30');

    $tp->respect($span7); # 2012-08-20 Urlaubsteilzeit 2012-08-31 | 2012-09-01 Urlaub 2012-09-06 | 2012-09-07 Urlaubspause 2012-09-08 | 2012-09-09 Urlaub 2012-09-15 | 2012-09-16 00:00:00 Lückenfüller 2012-09-21 23:59:59 | 2012-09-22 Mal kurz eingesprungen übers Wochenende 2012-09-24 | 2012-09-25 nur Montags bis Donnerstags 2012-10-03 | 2012-10-04 00:00:00 Lückenfüller 2012-10-16 23:59:59 | 2012-10-17 Für verschiedene Tage der Woche verschiedene Arbeitszeiten 2012-10-29 [ 2012-10-30 1 Nachtschicht für die nette Kollegin 2012-10-31 ]

    is $span7, $span2->next, 'Nachtschicht integriert';
    is $span7, $tp->end, 'Nachtschicht am Schluss';

    # TODO: Deckungsgleiche Abgrenzungen
    # TODO: Wenn neue Spannen mehrere bestehende Spannen überdecken, müssen diese im Speicher freigegeben werden.
    is $span2->until_date->get_qm_timestamp, '2012-10-29', 'Anpassung des Enddatum der vorhergehenden Spanne';
    ok !$span7->next, 'Nach Span7 kommt nichts mehr';

    my $s5next = $span5->next;
    weaken($_) for $span3, $span4, $span5, $s5next;

    my $span8 = Time::Span->new(description => 'Überschreiben', week_pattern => 'Mo-So@!0-23', from_date => '20.8.', until_date => '19.9.12');

    $tp->respect($span8); # [ 2012-08-20 Überschreiben 2012-09-19 ] 2012-09-20 00:00:00 Lückenfüller 2012-09-21 | 2012-09-22 Mal kurz eingesprungen übers Wochenende 2012-09-24 | 2012-09-25 nur Montags bis Donnerstags 2012-10-03 | 2012-10-04 00:00:00 Lückenfüller 2012-10-16 23:59:59 | 2012-10-17 Für verschiedene Tage der Woche verschiedene Arbeitszeiten 2012-10-29 [ 2012-10-30 1 Nachtschicht für die nette Kollegin 2012-10-31 ]

    is $span3, undef, 'Span8 hat Span3 überschrieben, also gelöscht';
    is $span4, undef, '... und Span4';
    is $span5, undef, '... und Span5';
    is $s5next, undef, '... und den zweiten Teil von Span3';
    is $span8, $tp->start, 'Span8 steht am Anfang';

    my $s8next = $span8->next;
    weaken($s8next); # [ 2012-08-20 Überschreiben 2012-09-19 ] 2012-09-20 00:00:00 Lückenfüller 2012-09-21 23:59:59 | 2012-09-22 Mal kurz eingesprungen übers Wochenende 2012-09-24 | 2012-09-25 nur Montags bis Donnerstags 2012-10-03 | 2012-10-04 00:00:00 Lückenfüller 2012-10-16 23:59:59 | 2012-10-17 Für verschiedene Tage der Woche verschiedene Arbeitszeiten 2012-10-29 | 2012-10-30 1 Nachtschicht für die nette Kollegin 2012-10-31 |
    my $span9 = Time::Span->new( description => 'Überschreiben II', from_date => '20.9.', until_date => '2012-09-21', week_pattern => 'Mo-Fr@13' );

    $tp->respect($span9); # | 2012-08-20 Überschreiben 2012-09-19 [ 2012-09-20 Überschreiben II 2012-09-21 ] 2012-09-22 Mal kurz eingesprungen übers Wochenende 2012-09-24 | 2012-09-25 nur Montags bis Donnerstags 2012-10-03 | 2012-10-04 00:00:00 Lückenfüller 2012-10-16 23:59:59 | 2012-10-17 Für verschiedene Tage der Woche verschiedene Arbeitszeiten 2012-10-29 | 2012-10-30 1 Nachtschicht für die nette Kollegin 2012-10-31 |

    is $span8->next, $span9, 'Span9 ersetzt Lückenfüller';
    is $span9->next, $span6, 'passgenau';
    is $s8next, undef, 'Lückenfüller überschrieben, also gelöscht';

    my @expected_state = (
     {
       'description' => 'Überschreiben',
       'from_date' => '2012-08-20',
       'rhythm' => {
          'atomic_enum' => '',
          'description' => 'Mo-So@!0-23',
          'from_week_day' => '34/12, Mo',
          'mins_per_unit' => 60,
          #'patternId' => 189380856,
          'until_week_day' => '38/12, We',
       },
       'until_date' => '2012-09-19',
     },{
       'description' => 'Überschreiben II',
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
       'description' => 'Mal kurz eingesprungen übers Wochenende',
       'from_date' => '2012-09-22',
       'rhythm' => {
          'atomic_enum' => '17,41,65',
          'description' => 'Mo-So@17-17',
          'from_week_day' => '38/12, Sa',
          'mins_per_unit' => 60,
          #'patternId' => 189397092,
          'until_week_day' => '39/12, Mo',
       },
       'until_date' => '2012-09-24',
     },{
       'description' => 'nur Montags bis Donnerstags',
       'from_date' => '2012-09-25',
       'rhythm' => {
          'atomic_enum' => '40-57,61-79,136-153,157-175,232-249,253-271,616-633,637-655,712-729,733-751,808-825,829-847',
          'description' => 'Mo-Do@10-14:30,15:15-19',
          'from_week_day' => '38/12, Tu',
          'mins_per_unit' => 15,
          #'patternId' => 189382776,
          'until_week_day' => '39/12, We',
       },
       'until_date' => '2012-10-03',
     },{
       'description' => 'Lückenfüller',
       'from_date' => '2012-10-04',
       'rhythm' => {
          'atomic_enum' => '18-34,66-82,210-226,258-274,306-322,354-370,402-418,546-562,594-610',
          'description' => 'Mo-Fr@9-17:30',
          'from_week_day' => '39/12, Th',
          'mins_per_unit' => 30,
          #'patternId' => 189383304,
          'until_week_day' => '41/12, Tu',
       },
       'until_date' => '2012-10-16',
     },{
       'description' => 'Für verschiedene Tage der Woche verschiedene Arbeitszeiten',
       'from_date' => '2012-10-17',
       'rhythm' => {
          'atomic_enum' => '15-25,74-84,122-132,170-180,255-265,303-313,351-361,410-420,458-468,506-516,591-601',
          'description' => 'Mo-Mi@7:30-13:00,Do-Sa@13-18:30',
          'from_week_day' => '42/12, We',
          'mins_per_unit' => 30,
          #'patternId' => 189383984,
          'until_week_day' => '44/12, Mo',
       },
       'until_date' => '2012-10-29',
     },{
       'description' => '1 Nachtschicht für die nette Kollegin',
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
        "Gesamtzustand nach allen respects";

    TODO: {
        local $TODO = '$tprof->timestamp_after_net_seconds($from_ts, $net_seconds)'
                     .'noch nicht implementiert.';
        my $ts0 = Time::Point->parse_ts('25.10.12 12:00');
        is $tp->seek_timestamp_after_net_seconds($ts0, 90_000), '30.10.12 2:59:59',
            'End-Zeitstempel landet in Slice';
        is $tp->seek_timestamp_after_net_seconds($ts0, 130_000), '1.11.12 11:06:39',
            '... bzw. im Fill-in';
    }

    TODO: {
        local $TODO = 'Time::Profile->lock(), unlock(), demand_protect() und release_protection() noch zu entwickeln';
    }

    TODO: {
        local $TODO = 'Time::Slice::VerticalScanner noch nicht implementiert';
        require_ok 'Time::Slice::VerticalScanner';
    }

    my @spans; my $next = $tp->start;
    $tp->detect_circular;
    do { push @spans, weaken($next) } while $next = $next->next; 
    $tp->reset;
    my $num =()= grep !defined, @spans;
    ok $num <= 1, 'timeline reset';
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

