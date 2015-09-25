
use strict;

use FindBin qw($Bin);
use Test::More;
use FTM::Time::Model;
use FTM::Time::Cursor;

my $model = FTM::Time::Model->from_json(<<'JSON');
{
   "work": {
       "label": "UB Informationstechnik",
       "week_pattern": "Mo-Fr@9-17:30",
       "variations": [
           { "name":"u1", "week_pattern_of_track":"urlaub", "apply":true,
             "from_date":"10.5.", "until_date":"17.5.2013"
           },
           { "week_pattern": "We@13-17", "from_date": "21.5.13", "until_date": "7.6.13",
             "description": "Honorary work", "name":"hw"
           }
       ]
   },

   "urlaub": { "week_pattern": "Mo-So@!0-23" }

}
JSON

ok($model->isa("FTM::Time::Model"), 'time model setup');

my $work = $model->get_track("work");
my $cursor = FTM::Time::Cursor->new(
    timestages => [{ track => $work, until_date => '30.6.13' }],
    start_ts => '1.5.13',
);
my $span = $work->start;
my $number_spans = 1;
$number_spans++ while $span = $span->next;
is $number_spans, 5 => "Time track consists of five linked spans";
is $work->start->pattern, $work->end->pattern => "The first and the last one have the same rhythm pattern";
my $next = $work->start->next;
is $model->get_track("urlaub")->fillIn->pattern, $next->pattern => "Second span is holidays";
$next = $next->next;
is $work->fillIn->pattern, $next->pattern => "Third span is business as usual";
$next = $next->next;
is $next->description, "Honorary work", "Forth span is honorary work";

done_testing();
