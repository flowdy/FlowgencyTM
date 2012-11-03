#!/usr/bin/perl
use strict;
use utf8;
use Date::Calc;
#use ANSI::Colors;
use autodie;

open my $tasks, "<", "tasks.list";

my $overdue;
while ( my $line = <$tasks> ) {
    my ($title, $since, $deadline, $prio, $description) = split /\t/, $line;
    my $since_ts = parse_ts($since);
    my $deadline_ts = parse_ts($deadline);
    my $remaining = $deadline_ts - time;

    my %task;

    # Wenn wir mehr als einen Tag haben
    if ( my $days = $remaining / 84600 and $days >= 1 ) {
        $remaining = sprintf "%.1f Tage", $days;
        $remaining =~ s/\./,/;
    }
    # Wenn wir noch mehr als eine Stunde haben
    elsif ( my $hours = $remaining / 3600 and $hours >= 1 ) {
        $remaining = sprintf "%dh:%dm%s", $hours,
           60 * ($hours - int $hours),
           $hours > 120 ? "" : "n"; 
    }
    # Wenn wir nur noch Minuten haben
    elsif ( my $min = $remaining / 60 and $min >= 1 ) {
        $remaining = sprintf "%d Min.", $min; 
    }
    else {
        my $sec = -$remaining;
        warn "Zeile $.: $title - Deadline seit ${sec}s überschritten\n";
        $overdue++;
        next;
    }

    $task{remaining} = $remaining;


    my $desc = $description =~ s{\A ([^\{]+) }{}xms ? $1
             : "(Keine Beschreibung)";

     
}
