#!perl
use strict;

package Time::Span::SubHiatus;
use Moose::Role;
use Carp qw(carp croak);

has subspans => (
    is => 'rw',
    isa => 'CodeRef',
    default => sub { sub{return;} },
);

has hiatus => (
    is => 'rw',
    isa => 'Time::Span::Hiatus',
    predicate => 'has_hiatus',
);

around calc_slices => sub {
    my ($orig, $self, $cursor) = @_;

    $_->calc_slices($cursor) for $self->subspans->($cursor);

    my ($next, $slices) = $self->$orig($cursor);

    $self->apply_hiatus($cursor, grep { !$_->finished } @slices);

    return $next, @slices;

};

sub apply_hiatus {
    my ($self,$cursor) = (shift, shift);
    @_ && $self->has_hiatus or return;

    my $slices = $cursor->in_subspan_context(
        $_[0]->begin, $_[-1]->end => sub {
            $self->hiatus->calc_all_slices(shift);
        }
    );
    
    my $h; while ( my $p = shift ) {
        $h ||= shift @$slices or $p->finish(1), last;
        $p->swallow_hiatus_slice($h);
        $h = undef if $h->finished;
        redo if !$p->finished;
    }

}

__PACKAGE__->meta->make_immutable;


