#!/usr/bin/perl
use strict;

use Test::More tests => 25;

=head1 NAME

FlowMan::Time::Slice - Begrenzter Bereich aus einem Zeitschema

=head2 INTERNE HILFSFUNKTIONEN

=item harmonize_sec_spans() - interne Hilfsfunktion

Bei der Berechnung der aktuellen Dringlichkeit einer Aufgabe spielt die Position in ihren Nettoarbeitszeitfragmenten eine wichtige Rolle. Die Positionsermittlung erfordert es, dass jede konkrete Sekunde der Bruttozeitspanne der vom Anwender konfigurierten Arbeits- bzw. Freizeit zugeordnet werden kann. Damit bei Überlagerungen zweier Zeitschemata jeweils gegenüberliegende Sekundenspannen verglichen werden können, müssen die Beträge der Sekundenzahlen spaltenweise übereinstimmen. Diese Funktion erwartet zwei Referenzen auf Ganzzahlenarrays (theoretisch auch mehr möglich) und gibt in gleicher Reihenfolge Referenzen auf deren jeweils harmonisierte Versionen zurück.

=cut

sub harmonize_sec_spans {

    return shift if @_ == 1;

    # Listenteile, deren Zahlen alle entweder positiv oder negativ sind,
    # sollen erst einmal durch Addition zu einem Element reduziert werden.
    # Da die CodeRef an List::Util::reduce nur Skalare zurückgeben darf ...
    my $same_sign_reduce = sub {
        my @out = shift;
        while ( defined(my $num = shift) ) {
            if ( $out[-1] && $num && $out[-1]<0 ^ $num<0 ) {
                push @out, $num;
            }
            else { $out[-1] += $num }
        }
        return \@out;
    };

    # Validiere und bereite Ausgangsdaten zur Weiterverarbeitung auf
    my ($i, %sums, @lists);
    for ( @_ ) {
        $i++;
        my $s; $s += abs($_) for @$_;
        push @{$sums{$s}}, $i;
        push @lists, { stack => $same_sign_reduce->(@$_) };
    }
    if ( scalar keys %sums > 1 ) {
        my @sums;
        while ( my ($sum, $lists) = each %sums ) {
            push @sums, $sum.'('.join(',', map { "\$$_" } @$lists).')';
        }
        die "Sums of magnitudes differ between the lists: ",
            join(' != ', @sums);
    }

    # Nun steppt der Bär: Wir reichen einzeln von {stack} über {remainder}
    # zu {new} durch. Jedes durchgereichte Element ist das kleinste in der
    # jeweiligen Spalte. Die {remainder} der anderen Zeilen werden um diesen
    # Betrag gegen 0 reduziert, an ihre {new}-Liste wird dieser Betrag mit dem
    # Vorzeichen des Rests angehängt.
    while (1) { 
        use List::Util qw(min);
        my @col = map { $_->{remainder} ||= shift @{$_->{stack}} } @lists;
        my $min = min( map { defined($_) ? abs($_) : () } @col );
        last if !defined $min;
        my $i = 0;
        my $list;
        for ( @col ) {
            $list = $lists[$i++];
            next if !defined;
            $_ = $_>0 ? $min : -$min;
            $list->{remainder} -= $_;
            push @{ $list->{new} }, $_;
        }
    }

    return map { $_->{new} } @lists;
   
}

local $/ = "\n\n";

my $i;

while ( chomp(my $test = <DATA>) ) {
    $i++;
    my (@lists, @expected);

    for (split "\n", $test) {
        my ($list, $expected) = split /\t+/, $_;
        push @lists, [split / /, $list ];
        $expected =~ s/ +/ /g;
        $expected =~ s/^ //;
        push @expected, $expected;
    }
         
    my @alpha = 'a'..'z';
    for my $got ( harmonize_sec_spans(@lists) ) {
        my $g = join ' ', @{shift @lists};
        my $x = shift @expected;
        is((join ' ', @$got), $x, "[$i".shift(@alpha)."] $g => $x");
    }

}

eval { harmonize_sec_spans([qw[10 3 10 2]], [qw[-1 -22 -2]], [qw[15 7 -5]]) };
ok($@, 'lists are rejected if sums differ');

__END__
-9 2 7 1 1	-1 -8  6  5
-1 14 -5	-1  8  6 -5

-1 14 -5 	-1  3  11 -2 -3
4 -13 3		 1  3 -11 -2  3

4 -13 3		 4 -11 -2  3
-15 5		-4 -11  2  3

-15 5		-5 -10  4  1
-5 14 -1	-5  10  4 -1

-5 14 -1	-5  4  10 -1
-9 2 7 1 1	-5 -4  10  1

-9 2 7 1 1	-4 -5  8  3
4 -13 3		 4 -5 -8  3

-24 -1		-25
-25		-25

-25		-24 -1
16 3 5 -1	 24 -1

16 3 5 -1	 15  5  3  1 -1
15 -5 3 -2	 15 -5  3 -1 -1

15 -5 3 -2	 15 -5  3 -2
10 3 10 2	 15  5  3  2
-1 -22 -2	-15 -5 -3 -2

10 3 10 2	 22  3
-1 -22 -2 	-22 -3
15 7 -3		 22 -3

