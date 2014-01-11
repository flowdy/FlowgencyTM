#!/usr/bin/perl
use strict;

use FindBin '$Bin';
use Test::More tests => 3;

my $db;
use FlowDB \$db;

use Time::Model;
use User::Tasks;

my $default_model = Time::Model->from_json(...);
 
ok $default_model->isa('Time::Model'), 'wrap default model in a moose class with tree/node functionality';

my $tasks = User::Tasks->new(
    task_rs => $db->resultset('FlowDB::Task'),
    model => $default_model,
);

my $t = $tasks->new_task({
    name => 'test1',
    from_date => '25.10.',
    until_date => '10.11.',
});

is $t && $t->name, 'test1', 'create a task';
