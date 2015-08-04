use strict;

package FTM::Time::Track::Variation;
use FTM::Types;
use Moose;

with FTM::Time::Structure::Link;

has [ '+from_date', '+until_date' ] => ( required => 0 );

has name => ( is => 'rw' );

has position => ( is => 'rw' );

has description => ( is => 'rw' );

has ref => (
    is => 'rw',
    isa => 'Maybe[Str]',
    trigger => sub {
       my ($self) = @_;
       $_ = undef for @{$self}{'week_pattern','section_from_track'};
    },
    lazy => 1,
    default => sub {
       my ($self) = @_;
       return $self->name if !$self->week_pattern
                          && !$self->section_from_track
                          ;
       return;
    }
);

has week_pattern => (
    is => 'rw',
    isa => 'Maybe[FTM::Time::Rhythm]',
    trigger => sub {
       my ($self) = @_;
       delete @{$self}{'ref','section_from_track'};
    },
    coerce => 1,
);

has section_from_track => (
    is => 'rw',
    isa => 'Maybe[FTM::Time::Track]',
    trigger => sub {
       my ($self) = @_;
       delete @{$self}{'week_pattern','ref'};
    },
);

has inherit_mode => ( is => 'rw', isa => 'Str' );

has apply => ( is => 'rw', isa => 'Str|Bool' );

has base => ( is => 'rw', isa => 'FTM::Time::Track::Variation' );

has track => ( is => 'rw', isa => 'FTM::Time::Track', weaken => 1 );

for my $prop (qw(from_date until_date description week_pattern section_from_track inherit_mode)) {
    around $prop => sub {
        my ($orig, $self, @val) = @_;
        return $self->$orig(@val) if @val || exists $self->{$prop};
        return $self->base->$prop();
    }
}

1;
