#!/usr/bin/perl
use strict;
use warnings;

use Test::More tests => 50;

use lib qw(../lib/);
use Time::Slice;
use Time::Cursor;
use Time::Profile;
use Scalar::Util qw(weaken);


my $tspan;

$tspan = Time::Span->from_string('21.5.--5.8.:Mo-Fr@9-16');
is($tspan->_rhythm->atoms->to_Enum, '9-16,33-40,57-64,81-88,105-112,177-184,201-208,225-232,249-256,273-280,345-352,369-376,393-400,417-424,441-448,513-520,537-544,561-568,585-592,609-616,681-688,705-712,729-736,753-760,777-784,849-856,873-880,897-904,921-928,945-952,1017-1024,1041-1048,1065-1072,1089-1096,1113-1120,1185-1192,1209-1216,1233-1240,1257-1264,1281-1288,1353-1360,1377-1384,1401-1408,1425-1432,1449-1456,1521-1528,1545-1552,1569-1576,1593-1600,1617-1624,1689-1696,1713-1720,1737-1744,1761-1768,1785-1792', 'Time span 21.5.--5.8.:Mo-Fr@9-16: rhythm');
my $tspan_bin = $tspan->_rhythm->atoms->to_Bin;
$tspan->until_date('10.8. 11');
like( $tspan->_rhythm->atoms->to_Bin, qr{ \A ( 0{7}1{8}0{9} ){5} 0{24} }xms, 'tspan expanded by 5 days at the end' );
$tspan->until_date('5.8.');
is($tspan->_rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible');
$tspan->until_date('3.8.');
like( $tspan->_rhythm->atoms->to_Bin, qr{ \A 0{7} 1 }xms, 'tspan truncated by 2 days at the end' );
$tspan->until_date('5.8.');
is($tspan->_rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible');
$tspan->from_date('19.5.');
like( $tspan->_rhythm->atoms->to_Bin, qr{ 1 0{57} \z }xms, 'tspan expand by -2 days at the beginning' );
$tspan->from_date('21.5.');
is($tspan->_rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible');
$tspan->from_date('26.5.');
like( $tspan->_rhythm->atoms->to_Bin, qr{ 1 0{57} \z }xms, 'tspan expand by +5 days at the beginning' );
$tspan->from_date('21.5.');
is($tspan->_rhythm->atoms->to_Bin, $tspan_bin, ' ... which is reversible');
my $tspan2 = Time::Span->from_string('21.5.--5.8.:Mo-Fr@9-17:30');
is($tspan2->_rhythm->hourdiv, 2, 'another tspan with end of business day 17:30');
is(length($tspan2->_rhythm->atoms->to_Bin), length($tspan_bin)*2, 'double-sized rhythm');
like($tspan2->_rhythm->atoms->to_Bin, qr{ 0 1{17} 0{18} \z }xms, 'additional half an hour respected at atom level');

my $curprof = Time::Profile->new(
    fillIn => Time::Span->new(
        description => 'reguläre Bürozeiten',
        from_date => '3.10.',
        until_date => '3.10.',
        week_pattern => 'Mo-Fr@9-17',
    ),
);
my $cursor = Time::Cursor->new(
    timeprofile => $curprof,
    run_from => Time::Point->parse_ts('27.6.'),
    run_until => Time::Point->parse_ts('15.7.'),
);

$cursor->slices($tspan->calc_slices($cursor));
my $ts = Time::Point->parse_ts('7.7.')->fill_in_assumptions;
my $pos = $cursor->update($ts->epoch_sec);
$ts = Time::Point->from_epoch($ts->epoch_sec+43200);
my $pos2 = $cursor->update($ts->epoch_sec);
is( $pos, $pos2, 'elapsed presence time should not until '.$ts);
$ts = Time::Point->from_epoch($ts->epoch_sec+162000);
my %pos2 = $cursor->update($ts->epoch_sec);
is( $pos, $pos2{current_pos}, 'it does neither at '.$ts);
$pos2 = $cursor->update($ts->epoch_sec+1);
cmp_ok( $pos, '<', $pos2, 'but just a second later, at 9:00:01am, it grows');
1;
$tspan2 = $tspan->new_shared_rhythm( '8.' => '21.8.' );
is($tspan2->_rhythm->atoms->bit_test(83), 0, 'copied and moved tspan, test 1');
is($tspan2->_rhythm->atoms->bit_test(63), 1, 'copied and moved tspan, test 2');

my $ts2 = Time::Point->parse_ts('2012-05-21 17:00:00');
$cursor->run_from(Time::Point->parse_ts('12.5.'));
$cursor->update($ts);
my %pos = $cursor->update($ts2);
$curprof->respect($tspan);
%pos2 = $cursor->update($ts2->epoch_sec+3601);

is $pos{elapsed_pres}, $pos2{elapsed_pres}, 'Unterschied nach Integration einer variierten Zeitspanne';
is $pos2{old}{elapsed_pres} - $pos2{elapsed_pres}, 3600, "Subhash 'old' beim ersten Time::Curso->update()-Aufruf nach einem Respect.";

my $defaultRhythm = Time::Span->new(week_pattern => 'Mo-Fr@9-17:30', from_date => '30.9.12', until_date => '30.9.12', description => 'Lückenfüller' );

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

my $span4 = Time::Span->new(description => 'Urlaubsteilzeit', from_date => '20.8.12', until_date => '31.8.', week_pattern => 'Mo-Fr@7:30-11;Mo-Do@7-10:30');

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

my $span7 = Time::Span->new(description => '1 Nachtschicht für die nette Kollegin', from_date => '30.10.', until_date => '31.10.', week_pattern => 'Mo-Fr@21:30-22,0-4:30');

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

my @spans; my $next = $tp->start;
$tp->detect_circular;
do { push @spans, weaken($next) } while $next = $next->next; 
$tp->reset;
my $num =()= grep !defined, @spans;
ok $num <= 1, 'timeline reset';
