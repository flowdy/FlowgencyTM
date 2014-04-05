
use strict;

use FindBin qw($Bin);
use Test::More;
use Time::Model;
use Time::Cursor;

my $model = Time::Model->from_json(<<'JSON');
{
   "work": {
       "label": "UB Informationstechnik",
       "week_pattern": "Mo-Fr@9-17:30",
       "variations": [
           { "ref":"urlaub", "apply":true, "from_date":"10.5.", "until_date":"7.6.13" },
           { "week_pattern": "Mi@13-17", "from_date": "21.5.13", "until_date": "31.",
             "description": "Ehrenamtliche Arbeit"
           }
       ]
   },

   "urlaub": { "week_pattern": "Mo-So@!0-23" }

}
JSON

ok($model->isa("Time::Model"), 'Zeitschema eingerichtet.');

my $work = $model->get_track("work");
my $cursor = Time::Cursor->new(
    timestages => [{ track => $work, until_date => '30.6.13' }],
    start_ts => '1.5.13',
);
my $span = $work->start;
my $number_spans = 1;
$number_spans++ while $span = $span->next;
is $number_spans, 5 => "Zeitprofil work besteht aus fünf Abschnitten";
is $work->start->pattern, $work->end->pattern => "Erster und letzter Abschnitt besitzen selben Rhythmus";
is $model->get_track('urlaub')->fillIn->pattern, $work->start->next->pattern => "Zweiter Abschnitt ist Urlaub";
is $work->start->next->next->description, "Ehrenamtliche Arbeit", "Ehrenamtstage im Urlaub";

done_testing();
