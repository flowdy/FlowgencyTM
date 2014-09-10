#!/usr/bin/perl
use strict;

use Test::More;
use Test::Exception;
use User;
use utf8;

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
is $task->description, 'Would appreciate it greatly if it works', "accessing description";

my $task2 = $user->tasks->add({
    name => 'kundenmigr',
    priority => 3,
    from_date => '21.7.2014 9:00',
    timestages => [{ track => 'default', until_date => '15.10. 17:00' }],
    title => 'Migrate excel sheet to sql database to be accessed via webapp',
    description => 'My first task with steps',
    checks => 2,
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

my $task3 = parser_test('Simple task parsed with Util::TreeFromLazyStr', <<'TASK', <<'COMPARE');
This is an example task =task3 ;pr soon ;from 8-28 ;until 9-4@default
  ;1 a step =foo ;expoftime_share: 3
  ;1 =link2migr ;link kundenmigr.dbsetup ;checks 0
     ;2 =copyadapt enhancement of a linked step ;o nx
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
        link => 'kundenmigr.dbsetup',
        checks => 0,
        substeps => 'copyadapt',
        description => undef,
    },
    copyadapt => {
        description => 'enhancement of a linked step'
    }
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

is +($task3->current_focus)[0][2], -1, "blocked link to a row to do after other steps";

check_done($task2, export2csv => 1);

my @focus_arefs;

@focus_arefs = $task3->current_focus;
ok !$focus_arefs[0][2] && @focus_arefs == 7, "unblocked by checking these other step";

check_done($task2, export2csv => 0);
$task3->store(link2migr => { link => 'kundenmigr' });
$step = $task3->step('link2migr');
is $step->checks, 0, "checks can be 0 for a link";
is $step->link_row->checks, 2, "which is independent from linked row";

# TODO: Test for exceptions
#  * circular dependency in hash to store
#  * typo in substeps
#  * orphan steps
#  * invalid parent for single step to update
#    * not existing
#    * make a descendent a parent
#    * make an ancestor a descendent

@focus_arefs = map { $_->[1] = $_->[1]->name; $_ } $task3->current_focus;

is_deeply \@focus_arefs, [
    [2, 'export2csv', !1],
    [1, '', 1],
    [2, 'copyadapt', !1],
    [1, 'link2migr', !1],
    [1, 'foo', !1],
    [0, '', !1]
], "current_focus test 1";

check_done( $task2,
    export2csv => 1,
    crtables   => 3,
    dblogic    => 3,
    dbsetup    => 1,
    audit      => 1,
);

@focus_arefs = map { $_->[1] = $_->[1]->name; $_ } $task3->current_focus;
is_deeply \@focus_arefs, [
    [2, 'csvinput', !1],
    [1, '', 1],
    [2, 'copyadapt', !1],
    [1, 'link2migr', !1],
    [1, 'foo', !1],
    [0, '', !1]
], "current_focus test 2";

is sprintf("%.5f", $task3->progress), sprintf("%.5f", (
  0/1*1          # task3/
  + 0/1*3        # foo
  + ( 0*1        # link2migr ->
    + 0/1*1      # kundenmigr/
    + 1/1*1      # export2csv
    + ( 1/1*3    # dbsetup
      + 3/3*3    # crtables
      + 3/3*2    # dblogic
      ) / 8 * 3  # end dbsetup = 8/8*3
    + 0/1*1      # csvinput
    + ( 0/1*6    # webapp
      + 1/2*2    # audit
      ) / 8 * 6  # end webapp = 1/8*6
    + 0/1*1      # copyadapt
    ) / 14 * 1   # end link2migr = 4/14*1 = 0.2857... 
) / 5 ), "calculate progress";

check_done( $task2,
    csvinput => 1,
    audit => 2,
    webapp => 2,
    '' => 2
);
check_done( $task3,
    foo => 1,
    copyadapt => 1,
    '' => 1
);

@focus_arefs = $task3->current_focus;
is scalar @focus_arefs, 0, "No more steps to do, task completed";
is $task3->progress, 1, "... progress is at 100% accordingly";
#diag("Current focus:");
#$task3->current_focus;

done_testing();

sub check_done {
    my ( $task_obj, %done_checks ) = @_;
    my $task = $task_obj->name;
    while ( my ($step, $done) = each %done_checks ) {
        #diag("Checking $task:$step => $done");
        $task_obj->store( $step => { done => $done });
    }
} 

sub parser_test {
    my ($description, $lazystr, $hash_str4eval) = @_;
    my $cmp_to_href = eval "#line Hash_Data 0\n 1 && {".$hash_str4eval."}";
                         # ^ force hash context
    die if $@;
    my ($parsed, $task) = $parser->($lazystr);
    is_deeply( $parsed, $cmp_to_href, $description );
    return $task;
}

