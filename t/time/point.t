#!/usr/bin/perl
use strict;

use FindBin;
use Test::More tests => 72;

use Time::Point;
use Date::Calc;

my $cur_ts_string_ref;
my ($DAY,$MONTH,$YEAR) = (localtime time)[3,4,5];
$MONTH++; $YEAR += 1900;

$cur_ts_string_ref = \(my $ts_test_string1 = '2012-07-04 19:15');
my $ts1 = Time::Point->parse_ts($$cur_ts_string_ref);
isa_ok($ts1, 'Time::Point', "created object for timestamp $$cur_ts_string_ref");

is("$ts1", $$cur_ts_string_ref, 'stringification 1');
is($ts1->epoch_sec, 1341422100, 'seconds since epoch available from the start');
$ts1->sec(1);
is($ts1->epoch_sec, 1341422101, 'automatic update seconds since epoch');
is($ts1->last_sec, 1341422101, 'epoch sec = last sec if second part defined');
my ($midnight,$ssm) = $ts1->split_seconds_since_midnight;
is($midnight, 1341352800, 'seconds of midnight');
is($ssm, 69301, 'seconds since midnight');

$cur_ts_string_ref = \(my $ts_test_string2 = '12-07-04 19:15');
my $ts2 = Time::Point->parse_ts($$cur_ts_string_ref);
is($ts2.q{}, "20$$cur_ts_string_ref", 'stringification 2, 20 of the year added');
is($ts2->last_sec, 1341422159, 'last sec implies +59 seconds if they are undefined');

$cur_ts_string_ref = \(my $ts_test_string3 = '07-04 19:15');
my $ts3 = Time::Point->parse_ts($$cur_ts_string_ref);
is($ts3->year, undef, 'Year ommitted in international date format');
is($ts3->month, 7, 'Month provided in international date format');
is($ts3->day, 4, 'Day provided in international date format');
is($ts3->hour, 19, 'Hour provided in international date format');
is($ts3->min, 15, 'Minute provided in international date format');
is($ts3->sec, undef, 'Undefined seconds in international date format');
is($ts3->fill_in_assumptions->year, $YEAR, 'this year assumed');

$cur_ts_string_ref = \(my $ts_test_string4 = '7-4 19:15');
my $ts4 = Time::Point->parse_ts($$cur_ts_string_ref)->fill_in_assumptions;
is("$ts4", "$ts3", 'leading zero omitted');
$cur_ts_string_ref = \(my $ts_test_string5 = '4 19:15');
my $ts5 = Time::Point->parse_ts($$cur_ts_string_ref)->fill_in_assumptions;
$ts5->fill_in_assumptions;
is($ts5->year, $YEAR, 'only day given, this year assumed (2)');
is($ts5->month, $MONTH, 'only day given, this month assumed');

$cur_ts_string_ref = \(my $ts_test_string6 = '04.07.2012 19:15');
my $ts6 = Time::Point->parse_ts($$cur_ts_string_ref);
is("$ts6","$ts_test_string1", "german notation supported");

$cur_ts_string_ref = \(my $ts_test_string7 = '04.07.12 19:15');
my $ts7 = Time::Point->parse_ts($$cur_ts_string_ref);
is("$ts7","$ts_test_string1", "german, 20 ommitted");

$cur_ts_string_ref = \(my $ts_test_string8 = '04.07. 19:15');
my $ts8 = Time::Point->parse_ts($$cur_ts_string_ref);
is($ts8->year, undef, 'german, Year ommitted');
is($ts8->month, 7, 'german, Month provided');
is($ts8->day, 4, 'german, Day provided');
is($ts8->hour, 19, 'german, Hour provided');
is($ts8->min, 15, 'german, Minute provided');
is($ts8->sec, undef, 'german, seconds omitted');
is($ts8->fill_in_assumptions->year, $YEAR, 'german, this year assumed');

$cur_ts_string_ref = \(my $ts_test_string9 = '4.7. 19:15');
my $ts9 = Time::Point->parse_ts($$cur_ts_string_ref)->fill_in_assumptions;
is("$ts9", "$ts8", 'german, leading zero omitted');
$cur_ts_string_ref = \(my $ts_test_string10 = '4. 19:15');
my $ts10 = Time::Point->parse_ts($$cur_ts_string_ref)->fill_in_assumptions;
$ts10->fill_in_assumptions;
is($ts10->year, $YEAR, 'german, only day given, this year assumed (2)');
is($ts10->month, $MONTH, 'german, only day given, this month assumed');

my $tsf = eval { Time::Point->parse_ts("18.3") };
like($@, qr/Could not parse date/, 'german, point required after month');
$tsf = eval { Time::Point->parse_ts("18.3.8") };
like($@, qr/Could not parse date/, 'german, one-digit year not allowed');


my $ts = Time::Point->parse_ts('22:06')->fill_in_assumptions;
is("$ts", sprintf("%4d-%02d-%02d 22:06", $YEAR, $MONTH, $DAY),
   'all date components impliable');
$ts = Time::Point->parse_ts('+1d',2008,3,17);
is("$ts", "2008-03-18", 'plus notation, day i.e. +1d');
$ts = Time::Point->parse_ts('+1w',2008,3,17);
is("$ts", "2008-03-24", 'plus notation, week i.e. +1w');
$ts = Time::Point->parse_ts('+1m',2008,3,17);
is("$ts", "2008-04-17", 'plus notation, month i.e. +1m');
$ts = Time::Point->parse_ts('+1y',2008,3,17);
is("$ts", "2009-03-17", 'plus notation, year i.e. +1y');
$ts = Time::Point->parse_ts('+1d2w3m4y 18:00',2008,3,17);
is("$ts", "2012-07-02 18:00", 'plus notation, +1d2w3m4y');

my $tsa = Time::Point->parse_ts("18.3.");
my $tsb = Time::Point->parse_ts("3.4.");
is($tsa->fix_order($tsb), 1, "timestamps in right order");
is($tsa->year, $YEAR, "timestamp a: year set to $YEAR"); 
is($tsb->year, $YEAR, "timestamp b: year set to $YEAR"); 
$tsa = Time::Point->parse_ts("3.4.2012");
is($tsa->last_sec, 1333490399, 'datestamp, get last second of the day');
$tsb = Time::Point->parse_ts("18.3.2012");
is($tsa->fix_order($tsb), !1, "timestamps in wrong order");
$tsb = Time::Point->parse_ts("18.3.");
is($tsa->fix_order($tsb), 1, "timestamps in right order (fixed year)");
is($tsb->year, 2013, " ... i.e timestamp b has been set to one year later");
$tsb = Time::Point->parse_ts("1.");
is($tsa->fix_order($tsb), 1, "timestamps in right order (fixed month)");
is($tsb->month, 5, " ... i.e timestamp b has been set to one month later");
is($tsb->year, 2012, " ... i.e timestamp b has been set to same year");
$tsa = Time::Point->parse_ts("20.12.2012");
$tsb = Time::Point->parse_ts("18.");
is($tsa->fix_order($tsb), 1, "timestamps in right order");
is($tsb->month, 1, " ... leaping Dec to Jan");
is($tsb->year, 2013, " ... leaping 2012 to 2013");

$tsa = Time::Point->parse_ts("3.4.");
$tsb = Time::Point->parse_ts("18.3.2012");
is($tsa->fix_order($tsb), 1, "timestamps in right order (fixed year)");
is($tsa->year, 2011, " ... i.e timestamp a has been set to one year earlier");
$tsa = Time::Point->parse_ts("20.");
is($tsa->fix_order($tsb), 1, "timestamps in right order (fixed month)");
is($tsa->month, 2, " ... i.e timestamp a has been set to one month earlier");
is($tsa->year, 2012, " ... i.e timestamp a has been set to same year");
$tsa = Time::Point->parse_ts("20.");
$tsb = Time::Point->parse_ts("6.1.2012");
is($tsa->fix_order($tsb), 1, "timestamps in right order");
is($tsa->month, 12, " ... leaping Jan to Dec");
is($tsa->year, 2011, " ... leaping 2012 to 2011");

$tsa = Time::Point->parse_ts('2012-07-15');
cmp_ok( $tsa, '==', $tsa->epoch_sec, "left-hand comparison operand denotes first second covered");
cmp_ok( $tsa, '!=', $tsa->last_sec, "left-hand comparison operand does not denote last second covered");
cmp_ok( $tsa->last_sec, '==', $tsa, "right-hand comparison operand denotes last second covered");
cmp_ok( $tsa->epoch_sec, '!=', $tsa, "right-hand comparison operand does not denote first second covered");
$tsb = Time::Point->parse_ts('2012-07-15 17:00:00');
ok( $tsa < $tsb && $tsb < $tsa, 'compare whole day and particular time of it');
$tsb = Time::Point->parse_ts('2012-07-14 23:59:59');
ok( $tsa > $tsb && $tsb < $tsa, ' ... different days');
$tsb = Time::Point->parse_ts('2012-07-16 00:00:01');
ok( $tsb > $tsa && $tsa < $tsb, ' ... different days (2)');
$tsb = Time::Point->parse_ts('2012-07-14 23:59:59');
ok( $tsa > $tsb->epoch_sec && $tsb->epoch_sec < $tsa, ' ... different days, one side plain seconds since epoch number');
$tsb = Time::Point->parse_ts('2012-07-16 00:00:01');
ok( $tsb->epoch_sec > $tsa && $tsa < $tsb->epoch_sec, ' ... different days (2), one side plain seconds since epoch number');
$tsb = Time::Point->parse_ts('2012-07-15');
ok( $tsa == $tsb, 'same day');
$tsb = Time::Point->parse_ts('2012-07-15 0');
ok( !$tsb->remainder && $tsa < $tsb && $tsb < $tsa,
    'whole day less and more than that day restricted to zero\'th hour');
is( $tsb->last_sec, 1342306799, 'last second of an hour' );

