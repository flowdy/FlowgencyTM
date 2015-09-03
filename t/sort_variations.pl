#!/usr/bin/perl
use strict;

use Test::More tests => 208;
use Test::Exception;
use Carp qw(croak);

use constant X => undef;

sub test_cmp_variations {
    my ($first, $second, $num, $description, $exp) = @_;

    $_ = [ @$_ ] for $first, $second;

    unless ( $num & 8 ) { my $n = $first->[0]; $first->[0] = \$n }
    unless ( $num & 4 ) { my $n = $first->[1]; $first->[1] = \$n }
    unless ( $num & 2 ) { my $n = $second->[0]; $second->[0] = \$n }
    unless ( $num & 1 ) { my $n = $second->[1]; $second->[1] = \$n }

    $description = sprintf "(%d) %s >> %s", $num, $description,
       $exp // '(X: explicit interlace forb.)';

    ($a, $b) = ($first, $second);
    if ( defined $exp ) {
        is eval { cmp_variations() } // (
            $@ ? ($@ =~ /^Conflict!/ ? 'X' : die $@) : undef
           ), $exp, $description;
    }
    else {
        my $res;
        dies_ok { $res = cmp_variations() } $description
            or diag "Failed recognizing interlace (returned $res)";
    }
}

my @BORDERS = ([1, 2], [3, 4], [1, 3], [2, 4], [1, 4], [2, 3]);

              # 0-6    # 7     # 8-10   # 11    # 12 # 13    # 14    # 15
my @FLAGS = ( ([1])x7, [0, 1], ([1])x3, [1, 1], [1], [1, 0], [0, 0], [0] );

my $i = 0;
test_cmp_variations(@$_) for
   map({ unshift @$_, @BORDERS[0, 0], $i++ % 16; $_ }
       [ '[\1=[\1 \2]=\2] : [a=[b a]=b]' => 0 ],
       [ '[\1=[\1 \2]= 2] : [a=[b a]=B]' => 0 ],
       [ '[\1=[ 1 \2]=\2] : [a=[B a]=b]' => 0 ],
       [ '[\1=[ 1 \2]= 2] : [a=[B a]=B]' => 0 ],
       [ '[\1=[\1  2]=\2] : [a=[b A]=b]' => 0 ],
       [ '[\1=[\1  2]= 2] : [a=[b A]=B]' => X ],
       [ '[\1=[ 1  2]=\2] : [a=[B A]=b]' => 0 ],
       [ '[\1=[ 1  2]= 2] : [a=[B A]=B]' => X ],
       [ '[ 1=[\1 \2]=\2] : [A=[b a]=b]' => 0 ],
       [ '[ 1=[\1 \2]= 2] : [A=[b a]=B]' => 0 ],
       [ '[ 1=[ 1 \2]=\2] : [A=[B a]=b]' => X ],
       [ '[ 1=[ 1 \2]= 2] : [A=[B a]=B]' => X ],
       [ '[ 1=[\1  2]=\2] : [A=[b A]=b]' => 0 ],
       [ '[ 1=[\1  2]= 2] : [A=[b A]=B]' => X ],
       [ '[ 1=[ 1  2]=\2] : [A=[B A]=b]' => X ],
       [ '[ 1=[ 1  2]= 2] : [A=[B A]=B]' => X ]),
   map({ unshift @$_, @BORDERS[0, 1], $i++ % 16; $_ }
       [ '[\1 \2] [\3 \4] : [a a] [b b]' => -1 ],
       [ '[\1 \2] [\3  4] : [a a] [b B]' => -1 ],
       [ '[\1 \2] [ 3 \4] : [a a] [B b]' => -1 ],
       [ '[\1 \2] [ 3  4] : [a a] [B B]' => -1 ],
       [ '[\1  2] [\3 \4] : [a A] [b b]' => -1 ],
       [ '[\1  2] [\3  4] : [a A] [b B]' => -1 ],
       [ '[\1  2] [ 3 \4] : [a A] [B b]' => -1 ],
       [ '[\1  2] [ 3  4] : [a A] [B B]' => -1 ],
       [ '[ 1 \2] [\3 \4] : [A a] [b b]' => -1 ],
       [ '[ 1 \2] [\3  4] : [A a] [b B]' => -1 ],
       [ '[ 1 \2] [ 3 \4] : [A a] [B b]' => -1 ],
       [ '[ 1 \2] [ 3  4] : [A a] [B B]' => -1 ],
       [ '[ 1  2] [\3 \4] : [A A] [b b]' => -1 ],
       [ '[ 1  2] [\3  4] : [A A] [b B]' => -1 ],
       [ '[ 1  2] [ 3 \4] : [A A] [B b]' => -1 ],
       [ '[ 1  2] [ 3  4] : [A A] [B B]' => -1 ]),
   map({ unshift @$_, @BORDERS[0, 2], $i++ % 16; $_ }
       [ '[\1=[\1 \2] \3] : [a=[b a] b]' => 0 ],
       [ '[\1=[\1 \2]  3] : [a=[b a] B]' => 0 ],
       [ '[\1=[ 1 \2] \3] : [a=[B a] b]' => 0 ],
       [ '[\1=[ 1 \2]  3] : [a=[B a] B]' => 0 ],
       [ '[\1=[\1  2] \3] : [a=[b A] b]' => 0 ],
       [ '[\1=[\1  2]  3] : [a=[b A] B]' => 0 ],
       [ '[\1=[ 1  2] \3] : [a=[B A] b]' => 0 ],
       [ '[\1=[ 1  2]  3] : [a=[B A] B]' => X ],
       [ '[ 1=[\1 \2] \3] : [A=[b a] b]' => 0 ],
       [ '[ 1=[\1 \2]  3] : [A=[b a] B]' => 0 ],
       [ '[ 1=[ 1 \2] \3] : [A=[B a] b]' => X ],
       [ '[ 1=[ 1 \2]  3] : [A=[B a] B]' => X ],
       [ '[ 1=[\1  2] \3] : [A=[b A] b]' => 0 ],
       [ '[ 1=[\1  2]  3] : [A=[b A] B]' => 0 ],
       [ '[ 1=[ 1  2] \3] : [A=[B A] b]' => X ],
       [ '[ 1=[ 1  2]  3] : [A=[B A] B]' => X ]),
   map({ unshift @$_, @BORDERS[0, 3], $i++ % 16; $_ }
       [ '[\1 \2]=[\2 \4] : [a a]=[b b]' => 0 ],
       [ '[\1 \2]=[\2  4] : [a a]=[b B]' => 0 ],
       [ '[\1 \2]=[ 2 \4] : [a a]=[B b]' => 0 ],
       [ '[\1 \2]=[ 2  4] : [a a]=[B B]' => 0 ],
       [ '[\1  2]=[\2 \4] : [a A]=[b b]' => 0 ],
       [ '[\1  2]=[\2  4] : [a A]=[b B]' => 0 ],
       [ '[\1  2]=[ 2 \4] : [a A]=[B b]' => X ],
       [ '[\1  2]=[ 2  4] : [a A]=[B B]' => X ],
       [ '[ 1 \2]=[\2 \4] : [A a]=[b b]' => 0 ],
       [ '[ 1 \2]=[\2  4] : [A a]=[b B]' => 0 ],
       [ '[ 1 \2]=[ 2 \4] : [A a]=[B b]' => 0 ],
       [ '[ 1 \2]=[ 2  4] : [A a]=[B B]' => 0 ],
       [ '[ 1  2]=[\2 \4] : [A A]=[b b]' => 0 ],
       [ '[ 1  2]=[\2  4] : [A A]=[b B]' => 0 ],
       [ '[ 1  2]=[ 2 \4] : [A A]=[B b]' => X ],
       [ '[ 1  2]=[ 2  4] : [A A]=[B B]' => X ]),
   map({ unshift @$_, @BORDERS[1, 0], $i++ % 16; $_ }
       [ '[\3 \4] [\1 \2] : [b b] [a a]' => 1 ],
       [ '[\3 \4] [\1  2] : [b B] [a a]' => 1 ],
       [ '[\3 \4] [ 1 \2] : [B b] [a a]' => 1 ],
       [ '[\3 \4] [ 1  2] : [B B] [a a]' => 1 ],
       [ '[\3  4] [\1 \2] : [b b] [a A]' => 1 ],
       [ '[\3  4] [\1  2] : [b B] [a A]' => 1 ],
       [ '[\3  4] [ 1 \2] : [B b] [a A]' => 1 ],
       [ '[\3  4] [ 1  2] : [B B] [a A]' => 1 ],
       [ '[ 3 \4] [\1 \2] : [b b] [A a]' => 1 ],
       [ '[ 3 \4] [\1  2] : [b B] [A a]' => 1 ],
       [ '[ 3 \4] [ 1 \2] : [B b] [A a]' => 1 ],
       [ '[ 3 \4] [ 1  2] : [B B] [A a]' => 1 ],
       [ '[ 3  4] [\1 \2] : [b b] [A A]' => 1 ],
       [ '[ 3  4] [\1  2] : [b B] [A A]' => 1 ],
       [ '[ 3  4] [ 1 \2] : [B b] [A A]' => 1 ],
       [ '[ 3  4] [ 1  2] : [B B] [A A]' => 1 ]),
   map({ unshift @$_, @BORDERS[1, 2], $i++ % 16; $_ }
       [ '[\3 \4] [\1 \3] : [b b]=[a a]' => 0 ],
       [ '[\3 \4] [\1  3] : [b B]=[a a]' => 0 ],
       [ '[\3 \4] [ 1 \3] : [B b]=[a a]' => 0 ],
       [ '[\3 \4] [ 1  3] : [B B]=[a a]' => 0 ],
       [ '[\3  4] [\1 \3] : [b b]=[a A]' => 0 ],
       [ '[\3  4] [\1  3] : [b B]=[a A]' => 0 ],
       [ '[\3  4] [ 1 \3] : [B b]=[a A]' => 0 ],
       [ '[\3  4] [ 1  3] : [B B]=[a A]' => 0 ],
       [ '[ 3 \4] [\1 \3] : [b b]=[A a]' => 0 ],
       [ '[ 3 \4] [\1  3] : [b B]=[A a]' => X ],
       [ '[ 3 \4] [ 1 \3] : [B b]=[A a]' => 0 ],
       [ '[ 3 \4] [ 1  3] : [B B]=[A a]' => X ],
       [ '[ 3  4] [\1 \3] : [b b]=[A A]' => 0 ],
       [ '[ 3  4] [\1  3] : [b B]=[A A]' => X ],
       [ '[ 3  4] [ 1 \3] : [B b]=[A A]' => 0 ],
       [ '[ 3  4] [ 1  3] : [B B]=[A A]' => X ]),
   map({ unshift @$_, @BORDERS[1, 3], $i++ % 16; $_ }
       [ '[\3 [\2 \4]=\4] : [b [a a]=b]' => 0 ],
       [ '[\3 [\2 \4]= 4] : [b [a a]=B]' => 0 ],
       [ '[\3 [ 2 \4]=\4] : [B [a a]=b]' => 0 ],
       [ '[\3 [ 2 \4]= 4] : [B [a a]=B]' => 0 ],
       [ '[\3 [\2  4]=\4] : [b [a A]=b]' => 0 ],
       [ '[\3 [\2  4]= 4] : [b [a A]=B]' => X ],
       [ '[\3 [ 2  4]=\4] : [B [a A]=b]' => 0 ],
       [ '[\3 [ 2  4]= 4] : [B [a A]=B]' => X ],
       [ '[ 3 [\2 \4]=\4] : [b [A a]=b]' => 0 ],
       [ '[ 3 [\2 \4]= 4] : [b [A a]=B]' => 0 ],
       [ '[ 3 [ 2 \4]=\4] : [B [A a]=b]' => 0 ],
       [ '[ 3 [ 2 \4]= 4] : [B [A a]=B]' => X ],
       [ '[ 3 [\2  4]=\4] : [b [A A]=b]' => 0 ],
       [ '[ 3 [\2  4]= 4] : [b [A A]=B]' => X ],
       [ '[ 3 [ 2  4]=\4] : [B [A A]=b]' => 0 ],
       [ '[ 3 [ 2  4]= 4] : [B [A A]=B]' => X ]),

   map({ unshift @$_, @BORDERS[2, 0], $i++ % 16; $_ }
       [ '[\1=[\1 \3] \2] : [a=[b b] a]' => 0 ],
       [ '[\1=[\1 \3]  2] : [a=[b B] a]' => 0 ],
       [ '[\1=[ 1 \3] \2] : [a=[B b] a]' => 0 ],
       [ '[\1=[ 1 \3]  2] : [a=[B B] a]' => 0 ],
       [ '[\1=[\1  3] \2] : [a=[b b] A]' => 0 ],
       [ '[\1=[\1  3]  2] : [a=[b B] A]' => 0 ],
       [ '[\1=[ 1  3] \2] : [a=[B b] A]' => 0 ],
       [ '[\1=[ 1  3]  2] : [a=[B B] A]' => 0 ],
       [ '[ 1=[\1 \3] \2] : [A=[b b] a]' => 0 ],
       [ '[ 1=[\1 \3]  2] : [A=[b B] a]' => 0 ],
       [ '[ 1=[ 1 \3] \2] : [A=[B b] a]' => X ],
       [ '[ 1=[ 1 \3]  2] : [A=[B B] a]' => X ],
       [ '[ 1=[\1  3] \2] : [A=[b b] A]' => 0 ],
       [ '[ 1=[\1  3]  2] : [A=[b B] A]' => X ],
       [ '[ 1=[ 1  3] \2] : [A=[B b] A]' => X ],
       [ '[ 1=[ 1  3]  2] : [A=[B B] A]' => X ]),
   map({ unshift @$_, @BORDERS[2, 3], $i++ % 16; $_ }
       [ '[\1 [\2 \3] \4] : [a [b a] b]' => 0 ],
       [ '[\1 [\2 \3]  4] : [a [b a] B]' => 0 ],
       [ '[\1 [ 2 \3] \4] : [a [B a] b]' => 0 ],
       [ '[\1 [ 2 \3]  4] : [a [B a] B]' => 0 ],
       [ '[\1 [\2  3] \4] : [a [b A] b]' => 0 ],
       [ '[\1 [\2  3]  4] : [a [b A] B]' => 0 ],
       [ '[\1 [ 2  3] \4] : [a [B A] b]' => 0 ],
       [ '[\1 [ 2  3]  4] : [a [B A] B]' => X ],
       [ '[ 1 [\2 \3] \4] : [A [b a] b]' => 0 ],
       [ '[ 1 [\2 \3]  4] : [A [b a] B]' => 0 ],
       [ '[ 1 [ 2 \3] \4] : [A [B a] b]' => 0 ],
       [ '[ 1 [ 2 \3]  4] : [A [B a] B]' => 0 ],
       [ '[ 1 [\2  3] \4] : [A [b A] b]' => 0 ],
       [ '[ 1 [\2  3]  4] : [A [b A] B]' => 0 ],
       [ '[ 1 [ 2  3] \4] : [A [B A] b]' => X ],
       [ '[ 1 [ 2  3]  4] : [A [B A] B]' => X ]),
   map({ unshift @$_, @BORDERS[2, 5], $i++ % 16; $_ }
       [ '[\1 [\2 \3]=\3] : [a [b b]=a]' => 0 ],
       [ '[\1 [\2 \3]= 3] : [a [b B]=a]' => 0 ],
       [ '[\1 [ 2 \3]=\3] : [a [B b]=a]' => 0 ],
       [ '[\1 [ 2 \3]= 3] : [a [B B]=a]' => 0 ],
       [ '[\1 [\2  3]=\3] : [a [b b]=A]' => 0 ],
       [ '[\1 [\2  3]= 3] : [a [b B]=A]' => X ],
       [ '[\1 [ 2  3]=\3] : [a [B b]=A]' => 0 ],
       [ '[\1 [ 2  3]= 3] : [a [B B]=A]' => X ],
       [ '[ 1 [\2 \3]=\3] : [A [b b]=a]' => 0 ],
       [ '[ 1 [\2 \3]= 3] : [A [b B]=a]' => 0 ],
       [ '[ 1 [ 2 \3]=\3] : [A [B b]=a]' => 0 ],
       [ '[ 1 [ 2 \3]= 3] : [A [B B]=a]' => 0 ],
       [ '[ 1 [\2  3]=\3] : [A [b b]=A]' => 0 ],
       [ '[ 1 [\2  3]= 3] : [A [b B]=A]' => X ],
       [ '[ 1 [ 2  3]=\3] : [A [B b]=A]' => X ],
       [ '[ 1 [ 2  3]= 3] : [A [B B]=A]' => X ]),

   map({ unshift @$_, @BORDERS[3, 2], $i++ % 16; $_ }
       [ '[\2 \4] [\1 \3] : [b [a b] a]' => 0 ],
       [ '[\2 \4] [\1  3] : [b [a B] a]' => 0 ],
       [ '[\2 \4] [ 1 \3] : [B [a b] a]' => 0 ],
       [ '[\2 \4] [ 1  3] : [B [a B] a]' => 0 ],
       [ '[\2  4] [\1 \3] : [b [a b] A]' => 0 ],
       [ '[\2  4] [\1  3] : [b [a B] A]' => 0 ],
       [ '[\2  4] [ 1 \3] : [B [a b] A]' => 0 ],
       [ '[\2  4] [ 1  3] : [B [a B] A]' => 0 ],
       [ '[ 2 \4] [\1 \3] : [b [A b] a]' => 0 ],
       [ '[ 2 \4] [\1  3] : [b [A B] a]' => 0 ],
       [ '[ 2 \4] [ 1 \3] : [B [A b] a]' => 0 ],
       [ '[ 2 \4] [ 1  3] : [B [A B] a]' => X ],
       [ '[ 2  4] [\1 \3] : [b [A b] A]' => 0 ],
       [ '[ 2  4] [\1  3] : [b [A B] A]' => X ],
       [ '[ 2  4] [ 1 \3] : [B [A b] A]' => 0 ],
       [ '[ 2  4] [ 1  3] : [B [A B] A]' => X ]),

   map({ unshift @$_, @BORDERS[4, 5], $i++ % 16; $_ }
       [ '[\1 \4] [\2 \3] : [a [b b] a]' => 0 ],
       [ '[\1 \4] [\2  3] : [a [b B] a]' => 0 ],
       [ '[\1 \4] [ 2 \3] : [a [B b] a]' => 0 ],
       [ '[\1 \4] [ 2  3] : [a [B B] a]' => 0 ],
       [ '[\1  4] [\2 \3] : [a [b b] A]' => 0 ],
       [ '[\1  4] [\2  3] : [a [b B] A]' => 0 ],
       [ '[\1  4] [ 2 \3] : [a [B b] A]' => 0 ],
       [ '[\1  4] [ 2  3] : [a [B B] A]' => 0 ],
       [ '[ 1 \4] [\2 \3] : [A [b b] a]' => 0 ],
       [ '[ 1 \4] [\2  3] : [A [b B] a]' => 0 ],
       [ '[ 1 \4] [ 2 \3] : [A [B b] a]' => 0 ],
       [ '[ 1 \4] [ 2  3] : [A [B B] a]' => 0 ],
       [ '[ 1  4] [\2 \3] : [A [b b] A]' => 0 ],
       [ '[ 1  4] [\2  3] : [A [b B] A]' => X ],
       [ '[ 1  4] [ 2 \3] : [A [B b] A]' => X ],
       [ '[ 1  4] [ 2  3] : [A [B B] A]' => X ]),

   map({ unshift @$_, @BORDERS[5, 4], $i++ % 16; $_ }
       [ '[\2 \3] [\1 \4] : [b [a a] b]' => 0 ],
       [ '[\2 \3] [\1  4] : [b [a a] B]' => 0 ],
       [ '[\2 \3] [ 1 \4] : [B [a a] b]' => 0 ],
       [ '[\2 \3] [ 1  4] : [B [a a] B]' => 0 ],
       [ '[\2  3] [\1 \4] : [b [a A] b]' => 0 ],
       [ '[\2  3] [\1  4] : [b [a A] B]' => 0 ],
       [ '[\2  3] [ 1 \4] : [B [a A] b]' => 0 ],
       [ '[\2  3] [ 1  4] : [B [a A] B]' => X ],
       [ '[ 2 \3] [\1 \4] : [b [A a] b]' => 0 ],
       [ '[ 2 \3] [\1  4] : [b [A a] B]' => 0 ],
       [ '[ 2 \3] [ 1 \4] : [B [A a] b]' => 0 ],
       [ '[ 2 \3] [ 1  4] : [B [A a] B]' => X ],
       [ '[ 2  3] [\1 \4] : [b [A A] b]' => 0 ],
       [ '[ 2  3] [\1  4] : [b [A A] B]' => 0 ],
       [ '[ 2  3] [ 1 \4] : [B [A A] b]' => 0 ],
       [ '[ 2  3] [ 1  4] : [B [A A] B]' => X ])
;
 
my ($a_fd, $a_ud, $b_fd, $b_ud, $mode, $flag_overlap, $flag_covered, $left_polarity, $right_polarity);
sub cmp_variations {

    # For variations situated properly apart in regard to their start/end
    # dates, returns -1 or 1 like <=> does. If two variations interlace, it
    # either returns 0 or throws an exception:
    #    a) It returns 0 = "equal" if at least one of the start/end dates
    #       causing the interlace is not defined explicitly in the same track
    #       but is implied by fallback to what is defined for a variation with
    #       the indicated name higher in the track ancestry.
    #       So stable sort leaves their order untouched and we can guarantee
    #       that the variation mentioned right-hand in the track's list of own
    #       or adapted variations trims or covers the left-hand one.
    #    b) If both end/start dates are explicit, an exception of class
    #       FTM::X::VariationsInterlace is thrown.
    #       
    # Thus, the user can change start/end dates of variations without worrying
    # about position conflicts between variations in other tracks.
    # 

    $mode = 0;
    ($a_fd, $a_ud, $b_fd, $b_ud) = (@$a, @$b);
    if ( ref $a_fd ) { $a_fd = $$a_fd } else { $mode |= 8 }
    if ( ref $a_ud ) { $a_ud = $$a_ud } else { $mode |= 4 }
    if ( ref $b_fd ) { $b_fd = $$b_fd } else { $mode |= 2 }
    if ( ref $b_ud ) { $b_ud = $$b_ud } else { $mode |= 1 }

    return -1 if $b_fd > $a_ud && $a_fd < $b_ud;
    return  1 if $b_fd < $a_ud && $a_fd > $b_ud;

    croak "Conflict!" if $mode == 15 
                      || ( ( $mode & 10 ) == 10 && $a_fd == $b_fd )
                      || ( ( $mode &  9 ) ==  9 && $a_fd == $b_ud )
                      || ( ( $mode &  6 ) ==  6 && $a_ud == $b_fd )
                      || ( ( $mode &  5 ) ==  5 && $a_ud == $b_ud )
                      ;

    return 0 if $mode ==  7 ? $a_ud > $b_ud || $a_ud < $b_fd
              : $mode == 11 ? $a_fd < $b_fd || $a_fd > $b_ud
              : $mode == 13 ? $b_ud < $a_fd || $b_ud > $a_ud
              : $mode == 14 ? $b_fd > $a_ud || $b_fd < $a_fd
              :               1
              ;

    croak "Conflict!";

}

__END__
0000  1 -1  1 [0 A 0] [0 B 0]
0000 -1  1 -1 [0 B 0] [0 A 0]
0000 -1 -1  0 [0 A [0 0] B 0]
0000 -1 -1  0 [0 A [0 B 0] 0]
0001  1 -1  1 [0 A 0] [0 B 1]
0001 -1  1 -1 [0 B 1] [0 A 0]
0001 -1 -1  0 [0 A [0 0] B 1]
0001 -1 -1  0 [0 A [0 B 0] 1]
0010  1 -1  1 [0 A 0] [1 B 0]
0010 -1  1 -1 [1 B 0] [0 A 0]
0010 -1 -1  0 [0 A [1 0] B 0]
0010 -1 -1  0 [0 A [1 B 0] 0]
0011  1 -1  1 [0 A 0] [1 B 1]
0011 -1  1 -1 [1 B 1] [0 A 0]
0011 -1 -1  0 [0 A [1 0] B 1]
0011 -1 -1  0 [0 A [1 B 0] 1]
0100  1 -1  1 [0 A 1] [0 B 0]
0100 -1  1 -1 [0 B 0] [0 A 1]
0100 -1 -1  0 [0 A [0 1] B 0]
0100 -1 -1  0 [0 A [0 B 1] 0]
0101  1 -1  1 [0 A 1] [0 B 1]
0101 -1  1 -1 [0 B 1] [0 A 1]
0101 -1 -1  0 [0 A [0 1] B 1]
0101 -1 -1  0 [0 A [0 B 1] 1]
0110  2 -1  1 [0 A 1] [1 B 0]
0110 -2  1 -1 [1 B 0] [0 A 1]
0110 -2 -1  0 [0 A [1 1] B 0]
0110 -2 -1  0 [0 A [1 B 0] 1]
0110 -2 -1  0 [1 B [0 A 1] 0]
0111  2 -1  1 [0 A 1] [1 B 1]
0111 -2  1 -1 [1 B 1] [0 A 1]
0111 -2 -1  X [0 A [1 1] B 1]
0111 -2 -1  0 [0 A [1 B 1] 1]
0111 -2 -1  X [1 B [0 A 1] 1]
1000  1 -1  1 [1 A 0] [0 B 0]
1000 -1  1 -1 [0 B 0] [1 A 0]
1000 -1 -1  0 [1 A [0 0] B 0]
1000 -1 -1  0 [1 A [0 B 0] 0]
1001  1 -2  1 [1 A 0] [0 B 1]
1001 -1  2 -1 [0 B 1] [1 A 0]
1001 -1 -2  0 [1 A [0 0] B 1]
1001 -1 -2  0 [1 A [0 B 1] 0]
1001 -1 -2  0 [0 B [1 A 0] 1]
1010  1 -1  1 [1 A 0] [1 B 0]
1010 -1  1 -1 [1 B 0] [1 A 0]
1010 -1 -1  0 [1 A [1 0] B 0]
1010 -1 -1  0 [1 A [1 B 0] 0]
1011  1 -2  1 [1 A 0] [1 B 1]
1011 -1  1 -1 [1 B 1] [1 A 0]
1011 -1 -2  0 [1 A [1 0] B 1]
1011 -1 -2  0 [1 A [1 B 1] 0]
1011 -1 -2  X [1 B [1 A 0] 1]
1100  1 -1  1 [1 A 1] [0 B 0]
1100 -1  1 -1 [0 B 0] [1 A 1]
1100 -1 -1  0 [1 A [0 1] B 0]
1100 -1 -1  0 [1 A [0 B 0] 1]
1101  1 -2  1 [1 A 1] [0 B 1]
1101 -1  1 -1 [0 B 1] [1 A 1]
1101 -1 -2  0 [1 A [0 1] B 1]
1101 -1 -2  X [1 A [0 B 1] 1]
1101 -1 -2  0 [0 B [1 A 1] 1]
1110  2 -1  1 [1 A 1] [1 B 0]
1110 -2  1 -1 [1 B 0] [1 A 1]
1110 -2 -1  X [1 A [1 1] B 0]
1110 -2 -1  X [1 A [1 B 0] 1]
1110 -2 -1  0 [1 B [1 A 1] 0]
1111  2 -2  1 [1 A 1] [1 B 1]
1111 -2 -2 -1 [1 B 1] [1 A 1]
1111 -2 -2  X [1 A [1 1] B 1]
1111 -2 -2  X [1 A [1 B 1] 1]
1111 -2 -2  X [1 B [1 A 1] 1]

## 0000 #############################
[0 A 0] [0 B 0]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 1
                               ==> -1

[0 A [0 0] B 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

[0 A [0 B 0] 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

## 0001 #############################
[0 A 0] [0 B 1]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 1
                               ==> -1

[0 A [0 0] B 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

[0 A [0 B 0] 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

## 0010 #############################
[0 A 0] [1 B 0]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 1
                               ==> -1

[0 A [1 0] B 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

[0 A [1 B 0] 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

## 0011 #############################
[0 A 0] [1 B 1]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 1
                               ==> -1

[0 A [1 0] B 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

[0 A [1 B 0] 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

## 0100 #############################
[0 A 1] [0 B 0]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 1
                               ==> -1

[0 A [0 1] B 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

[0 A [0 B 1] 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

## 0101 #############################
[0 A 1] [0 B 1]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 1
                               ==> -1

[0 A [0 1] B 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

[0 A [0 B 1] 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

## 0110 #############################
[0 A 1] [1 B 0]
$b->from_date > $a->until_date == 2
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == 1
                               ==> -1

[0 A [1 1] B 0]
$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == -1
                               ==> X

[0 A [1 B 0] 1]
$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == -1
                               ==> 0

## 0111 #############################
[0 A 1] [1 B 1]
$b->from_date > $a->until_date == 2
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == 1
                               ==> -1

[0 A [1 1] B 1]
$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == -1
                               ==> X

[0 A [1 B 1] 1]
$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == -1
                               ==> 0

## 1000 #############################
[1 A 0] [0 B 0]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 1
                               ==> -1

[1 A [0 0] B 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

[1 A [0 B 0] 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

## 1001 #############################
[1 A 0] [0 B 1]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -2
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 2
                               ==> -1

[1 A [0 0] B 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -2
                               ==> 0

[1 A [0 B 1] 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -2
                               ==> 0

## 1010 #############################
[1 A 0] [1 B 0]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -1
                               ==> 1

[1 B 0] [1 A 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 1
                               ==> -1

[1 A [1 0] B 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

[1 A [1 B 0] 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

## 1011 #############################
[1 A 0] [1 B 1]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -2
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 2
                               ==> -1

[1 A [1 0] B 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -2
                               ==> 0

[1 A [1 B 1] 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -2
                               ==> 0

[1 B [1 A 0] 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -2
                               ==> X
## 1100 #############################
[1 A 1] [0 B 0]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 1
                               ==> -1

[1 A [0 1] B 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

[1 A [0 B 1] 0]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -1
                               ==> 0

## 1101 #############################
[1 A 1] [0 B 1]
$b->from_date > $a->until_date == 1
$a->from_date > $b->until_date == -2
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 2
                               ==> -1

[1 A [0 1] B 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -2
                               ==> 0

[1 A [0 B 1] 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -2
                               ==> X

[0 B [1 A 1] 1]
$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == -2
                               ==> 0

## 1110 #############################
[1 A 1] [1 B 0]
$b->from_date > $a->until_date == 2
$a->from_date > $b->until_date == -1
                               ==> 1

$b->from_date > $a->until_date == -1
$a->from_date > $b->until_date == 2
                               ==> -1

[1 A [1 1] B 0]
$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == -1
                               ==> X

[1 A [1 B 0] 1]
$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == -1
                               ==> X

## 1111 ###############################
[1 A 1][1 B 1]
$b->from_date > $a->until_date == 2
$a->from_date > $b->until_date == -2
                               ==> 1

$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == 2
                               ==> -1

[1 A [1 1] B 1]
$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == -2
                               ==> X

[1 A [1 B 1] 1]
$b->from_date > $a->until_date == -2
$a->from_date > $b->until_date == -2
                               ==> X
