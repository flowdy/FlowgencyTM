#!/usr/bin/perl
use strict;

use lib '../lib';
use Test::More tests => 3;

my $db;
use FlowDB \$db;

my $default_scheme = $db->resultset('FlowDB::TimeScheme')->create({
    name => 'DEFAULT',
    title => 'Default Time-scheme',
    pattern => 'Mo-Fr@9-17',
    propagate => 0,
});

ok $default_scheme->isa('FlowDB::TimeScheme'), 'FlowDB::TimeScheme row object created';

use Time::Scheme;
use Tasks;

$default_scheme = Time::Scheme->new( dbirow => $default_scheme );

ok $default_scheme->isa('Time::Scheme'), 'wrap default scheme in a moose class with tree/node functionality';

my $tasks = Tasks->new(
    task_rs => $db->resultset('FlowDB::Task'),
    scheme => $default_scheme,
);

my $t = $tasks->new_task({
    name => 'test1',
    from_date => '25.10.',
    until_date => '10.11.',
});

is $t && $t->name, 'test1', 'create a task';
