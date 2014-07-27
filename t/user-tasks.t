#!/usr/bin/perl
use strict;

use Test::More;
use User;

my $db;
use FlowDB \$db => (@ARGV ? shift :());

ok $db->isa("DBIx::Class::Schema"), "database initialized";

sub time_model_json { return <<'END_JSON'; }
{"default":{"label":"UB/IT","week_pattern":"Mo-Fr@9-17:30"}}
END_JSON

my $user = $db->resultset("User")->find_or_create({
    id => 'fh',
    username => 'Florian Heß',
    password => '',
    time_model => time_model_json(),
    weights => q[{"pri":1,"tpd":1,"due":1,"open":1,"eptn":1}],
    priorities => q[{1:"Auf Halde",2:"Gelegentlich",3:"Bald erledigen",5:"Dringend"}],
});

ok $user->isa("FlowDB::User"), 'User fh created';

$user = User->new( dbicrow => $user );

ok $user->isa("User"), 'Wrapped user in a FlowTime User object';

my $task = $user->tasks->add({
    name => 'task1',
    priority => 2,
    from_date => '2014-01-20 12:30',
    timestages => [{ track => 'default', until_date => '2014-02-03 9:30' }],
    title => "My first task for testing purposes",
    description => 'Would appreciate it greatly if it works',
    checks => 5,
});

is $task->name, "task1", "Created test1";

done_testing();

