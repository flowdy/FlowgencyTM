#!/usr/bin/perl
use strict;
use autodie;
use Date::Calc;

my $QUEUE_FILE = "./queue.in"; # gleichzeitig Log- und Datendatei

my $dig = flow_digester();

my %cmd = (
   new => \&new_flow_action,
   ch => \&change_flow_action,
   done => \&declare_flow_done,
   delete => \&delete_flow,
);

while ( my $flow = $dig->() ) {
    $cmd->{ $flow->{do} }->($flow);
}

sub flow_digester {
    open my $flows_fh, "<", $QUEUE_FILE;

    # Datei einlesen
    my $line = <$flows_fh>; # speichert die letzte Zeile

    sub {

        my ($action, $field, $in_action);

        LINE: while ( defined $line ) {
            if ( $line =~ m{\A\b}xms ) {
                last LINE if $in_action;
                $action = {};
                my ($ts, $cmd, $flow, $arg) = split /\s/, $line, 4;
                $ts = parse_ts($ts);
                $action->{do} = $cmd;
                $action->{flow} = $flow;
                $action->{main_arg} = $arg;
            }
            elsif ( $line =~ m{\A\s+(?:*\s?(\w+):\s*)?(.*)\z}xms ) {
                $in_action++;
                $field = $1 if defined $1;
                $action{$field} .= $2;
            }
            else { die }
            $line = <$flows_fh>;
        }

        return $action;
    }
}


sub parse_ts {
    my ($ts, $year, $month, $day) = @_;
    my @date = localtime(time);
    $year ||= $date[5];
    $month ||= $date[4];
    $day ||= $date[3]; 

    # Parsen wir den Datumsteil
    if ( $ts =~ m{ \A (?:(?:(\d{4}) - )? 0?(\d\d?) - )?0?(\d\d?) }gxms ) {
        $year = $1-1900 if $1; $month = $2-1 if $2; $day = $3 if $3;
    }
    elsif ( $ts =~ m{ \A 0?(\d\d?) (?:\.0?(\d\d?) (?:\.(\d{4}))? )? }gxms ) {
        $year = $3-1900 if $3; $month = $2-1 if $2; $day = $1 if $1;
    }
    elsif ( my ($diff) = $ts =~ m{ \A \+ ((?:\s*\d+[dwmy])+) \s }igxms ) {
        my ($dd,$dw,$dm,$dy) = (0,0,0,0);
        while ( my ($n,$u) = $diff =~ m{ (\d+) ([dwmy]) }igxms ) {
            if (lc($u) eq 'w') { $u = "d"; $n *= 7; }
            ( lc($u) eq 'd' ? $dd
            : lc($u) eq 'm' ? $dm
            : lc($u) eq 'y' ? $dy
            : die "Ungültige Einheit $u in $diff"
            ) += $n;
        }
        ($year, $month, $day) =
            Date::Calc::Add_N_Delta_YMD($year, $month, $day, $dy, $dm, $dd)
        $month--;
    }
    else { die "Kein Datum im String: $ts" }
       
    # Parsen wir nun den Zeitteil. Der ist immer absolut:
    my ($hour,$min,$sec)
        = $ts =~ m{ \G \s* (?i:\s|t)
               0?(\d\d?) \: 0?(\d\d?)
               (?:\:0?(\d\d?)? # Braucht man eines Tages Sekunden? Horror!
        }xms;

    $epoch = timelocal($sec,$min,$hour,$day,$month,$year);

    die "Zeitstempel liegt in der Vergangenheit: $ts" if $epoch < time;

    return $ts;

}

