#!/usr/bin/perl
use strict;

package FTM::Time::Variation::Section;
use Moose;

extends 'FTM::Time::Variation';

has source => (
    is => 'rw',
    isa => 'FTM::Time::Track',
    required => 1,
);

sub span {
    my ($self) = @_;
    my $span = $self->source->get_section(
        $self->from_date,
        $self->until_date
    );
    return $span;
}

1;

__END__

=head1 NAME

FTM::Time::Variation::Section – A variation using a rendered span section of another track

