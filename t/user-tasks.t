#!/usr/bin/perl
use strict;

use Test::More;
use Test::Exception;
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
    priorities => q[{"pile":1,"whentime":2,"soon":3,"urgent":5}],
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
    title => 'Migrate excel sheet to sql database to be accessed via webapp',
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

my $parser = $user->tasks->get_tfls_parser( -dry => 0 );

sub parser_test {
    my ($description, $lazystr, $hash_str4eval) = @_;
    my $cmp_to_href = eval "#line Hash_Data 0\n 1 && {".$hash_str4eval."}";
    die if $@;
    my ($parsed, $task) = $parser->($lazystr);
    is_deeply( $parsed, $cmp_to_href, $description );
    return $task;
}

my $task3 = parser_test('Simple task parsed with Util::TreeFromLazyStr', <<'TASK', <<'COMPARE');
This is an example task =task3 ;pr soon ;from 8-28 ;until 9-4@default ;1 a step =foo ;expoftime_share 3 ;1 =link2migr ;link kundenmigr ;checks 0
TASK
name => 'task3',
title => 'This is an example task',
from_date => '8-28',
priority => 'soon',
steps => {
    foo => {
        description => 'a step',
        expoftime_share => 3,
    },
    link2migr => {
        link => 'kundenmigr',
        checks => 0,
        description => undef,
    },
},
substeps => ';foo|link2migr',
timestages => [
    { track => 'default', until_date => '9-4' }
],
COMPARE

is $task3->dbicrow->priority, 3, "priority label resolved to number";
is $task3->priority, 'soon', "priority output as label";

my $step = $task3->step('foo');
is $step->done, 0, "default value of done is 0";
is $step->checks, 1, "default value of checks is 1";
for my $field ( qw(done checks expoftime_share) ) {
    throws_ok { $step->update({ $field => -1 }) } qr/cannot be/,
        "$field cannot be negative";
}
throws_ok { $step->update({ expoftime_share => 0 }) } qr/less than/,
    "Expoftime_share can neither be 0";
throws_ok { $step->update({ checks => 0 }) } qr/Checks must be >0/,
    "Checks must be >0 when step is not a parent of substeps";
throws_ok { $step->update({ done => 3 }) } qr/than available/,
    "You cannot make more checks than available";

$step = $task3->step('link2migr');
is $step->checks, 0, "checks can be 0 for a link";
is $step->link_row->checks, 1, "which is independent from linked row";

# TODO: Test for exceptions
#  * circular dependency in hash to store
#  * typo in substeps
#  * orphan steps
#  * invalid parent for single step to update
#    * not existing
#    * make a descendent a parent
#    * make an ancestor a descendent
done_testing();

