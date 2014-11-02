#!/usr/bin/perl
use strict;

use Test::More;

my $db;
use FTM::FlowDB \$db => (@ARGV ? shift :());

ok $db->isa("DBIx::Class::Schema"), "database initialized";

my $user = $db->resultset("User")->find_or_create({
    user_id => 'fh',
    username => 'Florian Heß',
    password => '',
    time_model => '{"default":{"label":"UB/IT","week_pattern":"Mo-Fr@9-17:30"}}',
    weights => '{"pri":1,"tpd":1,"due":1,"open":1,"eptn":1}',
    priorities => '{1:"Auf Halde",2:"Gelegentlich",3:"Bald erledigen",5:"Dringend"}',
});

ok $user->isa("FTM::FlowDB::User"), "User fh gefunden oder erstellt";

my $task = $user->tasks->new({
    name => 'test',
    priority => 2,
    from_date => '2014-01-20 12:30',
    timestages => [{ track => 'default', until_date => '2014-02-03 9:30' }],
    title => 'Meine erste Testaufgabe',
    description => 'Wäre toll, wenn es funktioniert',
});

ok $task->isa("FTM::FlowDB::Task"), "FTM::FlowDB::Task-Objekt erstellt";
ok $task->insert, "Task in die Datenbank geschrieben";
is $task->description, $task->main_step_row->description, 'Beschreibung via Proxy';
is $task->description, 'Wäre toll, wenn es funktioniert', ' ... gesetzt';

my $substep = $task->main_step_row->add_to_substeps({ name => 'substep1', description => 'ein Unterschritt' });
is $substep->task_id, 1, "Unterschritt erbt Task-Id vom übergeordneten Schritt";

done_testing();

