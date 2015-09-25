#!/usr/bin/perl
use strict;

package FTM::Time::Variation::Section;
use Moose;

extends 'FTM::Time::Variation';

has section_from_track => (
    is => 'rw',
    isa => 'FTM::Time::Track',
    required => 1,
    trigger => \&FTM::Time::Variation::_change_ref_track,
    weak_ref => 1,
);

sub span {
    my ($self) = @_;
    my $span = $self->section_from_track->get_section({
        from_date => $self->from_date,
        until_date => $self->until_date,
        variation => $self,
    });
    return $span;
}

sub _specific_fields { return 'section_from_track' }

augment like => sub {
    my ($self, $other) = @_;
    
    return $self->section_from_track
        == $other->section_from_track
        && ( ref($self) eq __PACKAGE__ || inner() );
        ;
};

sub DEMOLISH {
    my $self = shift;
    $self->section_of_track->_drop_ref_child(
        $self->track, $self->name
    );
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 NAME

FTM::Time::Variation::Section – A variation using a rendered span section of another track

