#!/usr/bin/perl
use strict;

use FindBin '$Bin';
use Test::More tests => 3;

my $db;
use FlowDB \$db;

use Time::Scheme;
use User::Tasks;

my $default_scheme = Time::Scheme->from_json(...);
 
ok $default_scheme->isa('Time::Scheme'), 'wrap default scheme in a moose class with tree/node functionality';

my $tasks = User::Tasks->new(
    task_rs => $db->resultset('FlowDB::Task'),
    scheme => $default_scheme,
);

my $t = $tasks->new_task({
    name => 'test1',
    from_date => '25.10.',
    until_date => '10.11.',
});

is $t && $t->name, 'test1', 'create a task';
