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
    my $ordered_list = $ado->schedule_all // _fail_with_reason($dependencies);
    return wantarray ? @$ordered_list : $ordered_list;
            
}

sub _fail_with_reason {
    my $dependencies = shift;
    my (@stack, @path, $following) = ($dependencies);
    my %following = map { $_ => {} } keys %$dependencies;

    FROM_STACK:
    while ( my $subdep = $stack[-1] ) {

        DEPENDENCY:
        while ( my ($name, $deps) = each %$subdep ) {
            $following = $following{$name};
            push @path, $name;

            FOLLOWER:
            for my $dep_name ( @$deps ) {
                if ( $following->{$dep_name} ) {
                    my $path = join ">", @path, $dep_name;
                    $path =~ s{ \A (.+?) > (?=\Q$dep_name\E>) }{}xms;
                    FTM::Error::IrresolubleDependency->throw(
                        "Detected circular dependency: $path"
                    );
                }
                else {
                    my $fd = $following{$dep_name};
                    $_++ for @{$fd}{$name, keys %$following};
                        # Increment to make debugging easier, maybe
                }
            }
            if ( @$deps ) { 
                my %deps;
                for my $dep ( @$deps ) {
                    my $subdeps = $dependencies->{$dep} //
                        FTM::Error::IrresolubleDependency->throw(
                            "$dep, required by $name, is not found "
                              . "in dependency graph"
                        );
                    ;
                    $deps{$dep} = $subdeps;
                }
                push @stack, \%deps;
                next FROM_STACK;
            }
            pop @path;
        }
        pop @stack;
    }
    
    die "Dunno why ADO could not resolve the dependencies";

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

