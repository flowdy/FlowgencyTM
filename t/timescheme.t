
use strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;
use Time::Scheme;

my $scheme = Time::Scheme->from_json(<<JSON);
{
   work: {
       label: 'UB Informationstechnik',
       pattern: "Mo-Fr@9-17:30",
       variations: [
           { ref: 'urlaub', apply: true, from: '10.5.', until: '7.6.' }
       ],
   },

   urlaub: { pattern: 'Mo-So@!0-23' }

}
JSON

ok($scheme->isa("Time::Scheme"), 'Zeitschema eingerichtet.');

my $work = $scheme->time_profile("work");
my $span = $work->start;
my $number_spans = 1;
$number_spans++ while $span = $span->next;
is $number_spans, 3 => "Zeitprofil work besteht aus drei Abschnitten";


done_testing();
