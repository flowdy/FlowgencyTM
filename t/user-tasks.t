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

my $task2 = $user->tasks->add({
    name => 'kundenmigr',
    priority => 3,
    from_date => '21.7.2014 9:00',
    timestages => [{ track => 'default', until_date => '15.10. 17:00' }],
    title => 'Migration Excel-Kundentabelle nach SQL-Datenbank und Webapp',
    description => 'My first task with steps',
    checks => 1,
    substeps => 'export2csv,dbsetup,csvinput,webapp',
    steps => {
        audit => {
            description => "Datensicherheits-Audit v. extern",
            expoftime_share => 2,
            checks => 2,
            done => 0,
        },
        crtables => {
            description => "Erstellung des SQL-Codes",
            expoftime_share => 3,
            checks => 3,
            done => 2,
        },
        csvinput => {
            description => "CSV-Daten mittels Datenbank-API verarbeiten",
            expoftime_share => 2,
            checks => 1,
            done => 0,
        },
        dbsetup => {
            description => "Konzeption der Datenbank, Entitäten und Relationen",
            expoftime_share => 3,
            checks => 1,
            done => 0,
            substeps => 'crtables/dblogic',
        },
        dblogic => {
            description => "Logik auf niedriger Ebene mittels Datenbank-Wrapper implementieren",
            expoftime_share => 2,
            checks => 3,
            done => 1,
        },
        export2csv => {
            description => "Export nach CSV-Format",
            expoftime_share => 1,
            checks => 1,
            done => 0,
        },
        webapp => {
            description => "Webapp erstellen unter Rückgriff auf Datenbankschnittstelle",
            expoftime_share => 6,
            checks => 2,
            done => 0,
            substeps => 'audit',
        },
    }, 
});

is $task2->name, 'kundenmigr', "Created task with steps";

done_testing();

