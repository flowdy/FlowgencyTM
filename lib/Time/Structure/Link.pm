#!perl
use strict;
use utf8;

package Time::Structure::Link;
use Moose::Role;
use Carp qw(croak);

requires 'like', 'new_alike';

has from_date => (
     is => 'rw',
     isa => 'Time::Point',
     required => 1,
     trigger => sub {
        my ($self, $date, $old) = @_;
        my $ud = $self->until_date // return;
        croak "from_date ($date) > until_date ($ud)"
            if !$date->fix_order($ud);
        my $trigger = $self->can("_onchange_from");
        $self->$trigger($date, $old) if $old && $trigger;
     },
     coerce => 1,
);

has until_date => (
     is => 'rw',
     isa => 'Time::Point',
     required => 1,
     trigger => sub {
        my ($self, $date, $old) = @_;
        my $fd = $self->from_date // return;
        croak "until_date ($date) < from_date ($fd)"
            if !$fd->fix_order($date);
        my $trigger = $self->can("_onchange_until");
        $self->$trigger($date, $old) if $old && $trigger;
     },
     coerce => 1,
);

has next => (
    is => 'rw',
    does => 'Time::Structure::Link',
    clearer => 'nonext'
);

sub covers_ts {
    my ($self, $ts) = @_;
    $self->from_date <= $ts && $ts <= $self->until_date;
}


around 'new_alike' => sub {
    my ($wrapped, $self) = (shift, shift);

    my $args = @_ > 1 ? { @_ } : @_ ? shift : {};
    $_ = ref $_ ? $_ : Time::Point->parse_ts($_)
        for grep defined, @{$args}{qw/from_date until_date/};
    $args->{from_date  } //= $self->from_date;
    $args->{until_date} //= $self->until_date;

    return $self->$wrapped($args);

};

sub alter_coverage {
    my ($self, $from_date, $until_date, $fillIn) = @_;

    $fillIn //= $self;
    $_ = Time::Point->parse_ts($_)
        for grep { defined && !ref } $from_date, $until_date;
    if ( $from_date && $until_date ) {
        $from_date->fix_order($until_date)
            or croak 'Time::Span::alter_coverage(): dates in wrong order';
    }

    my ( $from_span, $until_span );

    if ( $from_date ) {
        if ( $self->like($fillIn) || $from_date > $self->from_date ) {
            $self->from_date($from_date);
            $from_span = $self;
        }
        else {
            my $gap = $fillIn->new_alike({
               from_date => $from_date,
               until_date => $self->from_date->predecessor,
            });
            $gap->next($self);
            $from_span = $gap;
        }
        return $from_span if !defined $until_date;
    }

    if ( $until_date ) {
        if ( $self->like($fillIn) || $until_date < $self->until_date ) {
            $self->until_date($until_date);
            $until_span = $self;
        }
        else {
            my $gap = $fillIn->new_alike({
               from_date => $self->until_date->successor,
               until_date => $until_date,
            });
            $self->next($gap);
            $until_span = $gap;
        }
        return $until_span if !defined $from_date;
    }
    
    return $from_span, $until_span;

}

#__PACKAGE__->meta->make_immutable;
1;


