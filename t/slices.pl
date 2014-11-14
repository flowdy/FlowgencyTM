#!/usr/bin/perl
use strict;

sub analyze_sec_spans {

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
    my @atoms;
    while (1) { 
        use List::Util qw(min);
        my @col = map { $_->{remainder} ||= shift @{$_->{stack}} } @lists;
        my $min = min( map { defined($_) ? abs($_) : () } @col );
        last if !defined $min;
        my $i = 0;
        my $list;
        my $atom = $atoms[@atoms] = [$min, 0, 0];
        for ( @col ) {
            next if !defined;
            $list = $lists[$i++];
            my $diff = $_>0 ? $min : -$min;
            $list->{remainder} -= $diff;
            $atom->[ $diff > 0 || 2 ]++;
        }
    }

    return @atoms;
   
}

1;

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

