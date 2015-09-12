#!/usr/bin/perl
use strict;

package FTM::Time::Variation::Derived;
use Moose;

extends 'FTM::Time::Variation';

has ref => (
    is => 'rw',
    isa => 'Str',
    lazy => 1,
    default => sub { shift->name },
);

has base => (
    is => 'rw',
    isa => 'FTM::Time::Variation',
    weak_ref => 1,
    handles => ['span']
);

for my $prop (qw(from_date until_date description inherit_mode)) {
    has "+$prop" => ( required => 0, predicate => "${prop}_is_explicit" );
    around $prop => sub {
        my ($orig, $self, @val) = @_;
        return @val || exists $self->{$prop} ? $self->$orig(@val) : $self->base->$prop;
    }
}

around span => sub {
    my ($orig, $self, @args) = @_;
    my $span = $self->$orig(@args);
    my $from_date = $self->from_date_is_explicit ? $self->from_date : undef;
    my $until_date = $self->until_date_is_explicit ? $self->until_date : undef;
    $span->alter_coverage($from_date, $until_date);
    $span->description($self->description) if $self->description_is_explicit;
    $span->variation($self);
    return $span;
};

1;

__END__

=head1 NAME

FTM::Time::Variation::Derived – A track variation from a borrowing track
