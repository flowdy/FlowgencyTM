#!/usr/bin/perl
use strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use FTM::Util::LinearNum2ColourMapper;
use List::Util qw(min);

my @basecolor = (0,0xC0,0xff);

my $blender = FTM::Util::LinearNum2ColourMapper->new({
    '1' => [255,38,76],
    '0' => \@basecolor,
    '-1' => [51,255,64],
});

sub relation {
    my ($n1, $op, $n2)
       = $_[0] =~ m{ \A (\d+(?:[.,]\d+)?) ([:\/]) (\d+(?:[.,]\d+)?) \z }xms
       or die 'format rules disrespected: '.$_[0];
    s{,}{.} for $n1,$n2;
    return $op eq ':' ? ($n2, $n1 / ( $n1 + $n2 ))
         : $op eq '/' ? ($n2-$n1, $n1 / $n2)
         : die 'invalid op';
}

my ($elapsed, $done) = map { scalar relation($_) } @ARGV;

my $rel_state = $elapsed - $done;
$rel_state /= 1 - min($elapsed, $done);

my $orient = $rel_state > 0 ? "right" : "left";
my $other_opacity = 1 - abs($rel_state);

my $primary_color = $blender->blend($rel_state);
my $primary_width = sprintf("%1.0f", ($rel_state > 0 ? 1-$done : $done) * 100);
my $secondary_color = sprintf 'rgba(%d,%d,%d,%f)', @basecolor, $other_opacity;

print qq{<!--
   elapsed:   $elapsed
   done:      $done
   rel_state: $rel_state
-->
<li><header><h2>Zeitfortschritt: $ARGV[0] / Erledigungsfortschritt: $ARGV[1]</h2>
<div class="progressbar" style="text-align:$orient; background-color:$secondary_color"><span class="erledigt" style="background-color:$primary_color;width:$primary_width%;">&nbsp;</span></div></header></li>\n};
