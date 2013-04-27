#!/usr/bin/perl
use strict;

use 5.014;

package Util::GraphChecker;
use Moose;
use Carp qw(croak);
use List::Util qw(first);

has axes => (
    is => 'ro',
    isa => 'HashRef[CodeRef]',
    required => 1,
);

has nodes => (
    is => 'ro',
    isa => 'HashRef[HashRef[ArrayRef]]',
    default => sub {{}},
    init_arg => undef,
);

sub declare {
    my ($self, $node, $relaxis, $relnode) = @_;
    
    my $axes = $self->axes;

    croak "Node can't be linked to itself" if $node eq $relnode;

    for ( $node, $relnode ) { 
        $_ = $self->nodes->{$_} ||= {
            name => $_,
            map { $_ => [] } keys $axes
        };
    }

    for ( keys $axes ) {
        my $axis = $_;
        next if $axis eq $relaxis;
        croak "Graph circularized at $_->{name}:$axis"
            if $_ = $self->find($node => $axis, $relnode);
    }

    if ( !first { $_ eq $relnode->{name} } @{$node->{$relaxis}} ) {
        push @{$node->{$relaxis}}, $relnode->{name};
        return $axes->{$relaxis}->($relnode, $node->{name});
    }
    else { return; }
}

sub find {
    my ($self, $orig_node, $axis, $node) = @_;
    
    my $nodes = $self->{nodes};
    my $name = $orig_node->{name};
    my ($n, $x, @examine) = ($node, "!$name");

    while ( 1 ) {
        return $n if $x eq $name;
        push @examine, @{$n->{$axis}};
        $x = shift(@examine) // last;
        $n = $nodes->{$x};
    }

    return;
} 

return 1 if caller;

package main;

my $grch = Util::GraphChecker->new(
  axes => {
    parents => sub {
        my ($parent, $child) = @_;
        push @{$parent->{children}}, $child;
    },
    children => sub {
        my ($child, $parent) = @_;
        $child->{parent} = [$parent];
    }
});

$grch->declare(foo => parents => "bar") and print "success! 1 \n";
$grch->declare(bar => children => "foo") and print "success! 2\n";
$grch->declare(bar => parents => "foo") and print "success! 3\n";
