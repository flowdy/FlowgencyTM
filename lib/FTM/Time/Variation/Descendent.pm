#!/usr/bin/perl
use strict;

package FTM::Time::Variation::Descendent;
use Moose;

extends 'FTM::Time::Variation';

has ref => (
    is => 'rw',
    isa => 'FTM::Time::Variation',
    handles => ['span'],
    trigger => sub {
        my ($self, $new, $old) = @_;
        $new->incr_reference_count;
        $old->decr_reference_count;
    }
);

for my $prop (qw(from_date until_date description inherit_mode)) {
    has "+$prop" => ( required => 0, predicate => "${prop}_is_explicit" );
    around $prop => sub {
        my ($orig, $self, @val) = @_;
        return @val || exists $self->{$prop} ? $self->$orig(@val) : $self->base->$prop;
    }
}

sub _specific_fields { return 'ref' }

augment like => sub {
    my ($self, $other) = @_;
    
    return $self->ref == $other->ref
        && ( ref($self) eq __PACKAGE__ || inner() );
        ;
};

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

__PACKAGE__->meta->make_immutable;

sub DEMOLISH {
    my $self = shift;
    $self->ref->decr_reference_count;
}

1;

__END__

=head1 NAME

FTM::Time::Variation::Derived – A track variation from a borrowing track
