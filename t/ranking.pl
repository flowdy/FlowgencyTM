#!/usr/bin/perl
use strict;

use locale;

my $tasks =
<<TASKS;# prio	elapsed	done:todo
foo       2	190/371	9:7
bar	  1     20431/39549 8:15
baz3	  3     25524/32093 14:3
baz	  3     27524/32093 4:15
baz2	  1     27524/32093 1:15
alpha     2	3/4	2:2
beta	  2	9/10	8:2
gamma     2     29/30     2:1
TASKS

sub relation {
    my ($n1, $op, $n2)
       = $_[0] =~ m{ \A (\d+(?:[.,]\d+)?) ([:\/]) (\d+(?:[.,]\d+)?) \z }xms
       or die 'format rules disrespected';
    s{,}{.} for $n1,$n2;
    return $op eq ':' ? ($n2, $n1 / ( $n1 + $n2 ))
         : $op eq '/' ? ($n2-$n1, $n1 / $n2)
         : die 'invalid op';
}

my %tasks;

for ( split /\n/, $tasks ) {
    use List::Util qw(min);
    my ($name, $prio, $elapsed, $done) = split /\s+/;
    my ($avatime, $elapsed) = relation($elapsed);
    $done = relation($done);
    my $rel_state = $elapsed - $done;
    $rel_state /= 1 - min($elapsed, $done);
    #my $res = $prio * 10**$rel_state / (1-$elapsed);
    my $res = 10**($prio+$rel_state*$prio) / (1-$elapsed);
    my ($left_yellow2green,$right_yellow2red) = (255,255);
    if ( $done < $elapsed ) {
        $right_yellow2red -= int($rel_state * 255);
    }
    elsif ( $done > $elapsed ) {
        $left_yellow2green -= int(-$rel_state * 255);
    }
    my $left_color  = sprintf '#%xff00', $left_yellow2green;
    my $right_color = sprintf '#ff%x00', $right_yellow2red;

    my $hours = int($avatime / 3600);
    my $seconds = $avatime % 3600;
    my $minutes = int( $seconds / 60 );
    $seconds %= 60;

    $tasks{ $name } = [
        $prio,
        sprintf('%d:%02d:%02d', $hours, $minutes, $seconds),
        $left_color,
        sprintf('%.2f%%', $done * 100),
        $right_color,
        sprintf('(%+.2f%%)', -$rel_state * 100),
        $res,
    ];
}

my @ranking = sort { $tasks{$b}->[-1] <=> $tasks{$a}->[-1] } keys %tasks;

while ( my $task = shift @ranking ) {
    for ( $tasks{$task}[-1] ) {
        if ( @ranking ) {
            $_ /= $tasks{ $ranking[0] }[-1];
        }
        $_ = sprintf('%.3f', $_);
    }
    print join "\t", $task.': ', @{$tasks{$task}};
    print "\n";
}
