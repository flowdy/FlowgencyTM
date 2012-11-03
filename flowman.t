#!perl
use strict;

my $db;
use FlowDB \$db => 'test.db';

print ref($db), " connected successfully\n";

my $s1 = $db->resultset('Step')->find({task => "t1", ID => "s1"});
my $s2 = $db->resultset('Step')->find({task => "t2", ID => ""});

printf "s2 hängt ab von: %s.\n",
     join ",", map { $_->title } $s2->prior_steps;

printf "s1 ist erforderlich für einen Schritt mit folgender Beschreibung: %s\n",
     join ",", map { $_->description } $s1->required_for_steps;
