
use strict;

use FindBin qw($Bin);
use Test::More;
use Time::Model;
use Time::Cursor;

my $model = Time::Model->from_json(<<'JSON');
{
   "work": {
       "label": "UB Informationstechnik",
       "pattern": "Mo-Fr@9-17:30",
       "variations": [
           { "ref":"urlaub", "apply":true, "from":"10.5.", "until":"7.6.13" },
           { "week_pattern": "Mi@13-17", "from": "21.5.13", "until": "31.",
             "description": "Ehrenamtliche Arbeit"
           }
       ],
   },

   "urlaub": { "pattern": "Mo-So@!0-23" }

}
JSON

ok($model->isa("Time::Model"), 'Zeitschema eingerichtet.');

my $work = $model->time_profile("work");
my $cursor = Time::Cursor->new(
    timeprofile => $work,
    run_from => '1.5.13',
    run_until => '30.6.13',
);
my $span = $work->start;
my $number_spans = 1;
$number_spans++ while $span = $span->next;
is $number_spans, 5 => "Zeitprofil work besteht aus fünf Abschnitten";
is $work->start->pattern, $work->end->pattern => "Erster und letzter Abschnitt besitzen selben Rhythmus";
is $model->time_profile('urlaub')->fillIn->pattern, $work->start->next->pattern => "Zweiter Abschnitt ist Urlaub";
is $work->start->next->next->description, "Ehrenamtliche Arbeit", "Ehrenamtstage im Urlaub";

done_testing();
