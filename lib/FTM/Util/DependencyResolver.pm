#!/usr/bin/perl
package FTM::Util::DependencyResolver;
use strict;
use Algorithm::Dependency::Ordered;
use Algorithm::Dependency::Source::HoA;
use Carp qw(croak);

use base qw(Exporter);
our @EXPORT_OK = qw(ordered);

sub ordered {
    my ($dependencies) = @_;
    my $source = Algorithm::Dependency::Source::HoA->new(shift);
    my $ado = Algorithm::Dependency::Ordered->new( source => $source );
    my $ordered_list = $ado->schedule_all;

    if ( !$ordered_list ) {
        # Algorithm::Dependency to weed out all items selected in schedule_all
        # in Algorithm::Dependency::Ordered.
        croak "There are irresoluble dependencies either because of ",
              "circularity or because the dependency graph is incomplete";
    }

    return wantarray ? @$ordered_list : $ordered_list;
            
}

__END__

=head1 NAME

FTM::Util::DependencyResolver - Replacement for FTM::Util::GraphChecker

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 COPYRIGHT

(C) 2012-2014 Florian Hess

=head1 LICENSE

This file is part of FlowgencyTM.

FlowgencyTM is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowgencyTM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowgencyTM. If not, see <http://www.gnu.org/licenses/>.

