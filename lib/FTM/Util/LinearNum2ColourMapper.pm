#!/usr/perl
use strict;

package FTM::Util::LinearNum2ColourMapper;
use Moose;
use FTM::Types;
use Scalar::Util qw(looks_like_number);
use Carp qw(croak);

has thresholds => (
    is => 'ro',
    isa => 'HashRef[RgbColour]',
    required => 1,
);

sub BUILDARGS {
    my $class = shift;
    my $args = @_ == 1 ? shift : { @_ };

    for my $t ( $args->{thresholds} //= {} ) {
        if ( %$t ) {
            for ( keys %$t ) {
               croak "Not a number: $_" if !looks_like_number($_);
            }
        }
        else { 
            $t->{$_} = delete $args->{$_}
                for grep { looks_like_number($_) }
                    keys %$args
                ;
        }
        next;
    }

    return $args;

}; 

sub blend {
    my ($self,$val) = @_;
    my $thresholds = $self->thresholds;
    
    my $wa = wantarray;
    my $output = sub {
        my @c = map { sprintf '%02X', $_ } @{+shift};
        return $wa ? @c : "#".join(q{}, @c);
    };

    if ( my $c = $thresholds->{$val} ) {
        return $output->($c);
    }

    my @sorted = sort keys %$thresholds;

    my $lower = $val - 1;
    my $upper;

    while ( defined($upper = shift @sorted) ) {
        last if $val > $lower && $val < $upper;
        $lower = $upper;
    }

    my ($red, $green, $blue) = ([],[],[]);

    if ( my $lower_c = $thresholds->{$lower} ) {
        $red->[0] = $lower_c->[0];
        $green->[0] = $lower_c->[1];
        $blue->[0] = $lower_c->[2];
    }
    else { return $output->($thresholds->{$upper}); }

    if ( my $upper_c = $thresholds->{$upper//''} ) {
        $red->[1] = $upper_c->[0];
        $green->[1] = $upper_c->[1];
        $blue->[1] = $upper_c->[2];
    }
    else { return $output->($thresholds->{$lower}) }

    my $rel = ($val - $lower) / ($upper - $lower);

    for my $c ( $red, $green, $blue ) {
        my $diff = $c->[1] - $c->[0];
        $c = $c->[0] + sprintf('%.0f', $rel * $diff);
    }
    
    return $output->([ $red, $green, $blue ]);
}

return 1 if caller;

package main;

my %colours = (
    '-1' => [255,38,76],
    '0' => [0,0xC0,0xff],
    '1' => [51,255,64],
);

my $blender = LinearNum2ColourMapper->new(\%colours);

print '-2: ', scalar($blender->blend(-2)), "\n";
print '-1: ', join(" ", $blender->blend(-1)), "\n";
print '-0.67: ', join(" ", $blender->blend(-2/3)), "\n";
print '-0.5: ', join(" ", $blender->blend(-0.5)), "\n";
print '-0.33: ', join(" ", $blender->blend(-1/3)), "\n";
print '0: ', join(" ", $blender->blend(0)), "\n";
print '+0.33: ', join(" ", $blender->blend(1/3)), "\n";
print '+0.5: ', join(" ", $blender->blend(0.5)), "\n";
print '+0.67: ', join(" ", $blender->blend(2/3)), "\n";
print '+1: ', join(" ", $blender->blend(+1)), "\n";
print '+2: ', scalar($blender->blend(+2)), "\n";

__END__

=head1 NAME

FTM::Util::LinearNum2ColourMapper - Used for the colour gradient

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 COPYRIGHT

(C) 2012-2014 Florian Hess

=head1 LICENSE

This file is part of FlowTiMeter.

FlowTiMeter is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowTiMeter is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowTiMeter. If not, see <http://www.gnu.org/licenses/>.

