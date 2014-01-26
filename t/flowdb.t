#!/usr/bin/perl
use strict;

use Test::More;

my $db;
use FlowDB \$db => (@ARGV ? shift :());

ok $db->isa("DBIx::Class::Schema"), "database initialized";

my $task = $db->resultset("Task")->new({
    user => 'fh',
    name => 'test',
    priority => 2,
    from_date => '2014-01-20 12:30',
    title => 'Meine erste Testaufgabe',
    timesegments => [{ profile => 'default', until_date => '2014-02-03 9:30' }],
    description => 'Wäre toll, wenn es funktioniert',
});

ok $task->isa("FlowDB::Task"), "FlowDB::Task-Objekt erstellt";
ok $task->insert, "Task in die Datenbank geschrieben";
is $task->description, $task->main_step_row->description, 'Beschreibung via Proxy';
is $task->description, 'Wäre toll, wenn es funktioniert', ' ... gesetzt';

my $substep = $task->main_step_row->add_to_substeps({ name => 'substep1', description => 'ein Unterschritt' });
is $substep->task, 1, "Unterschritt erbt Task-Id vom übergeordneten Schritt";

done_testing();

