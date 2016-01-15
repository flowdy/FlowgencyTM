#!perl
use strict;
use utf8;

package FTM::Time::Structure::Link;
use Moose::Role;

requires 'like', 'new_alike';

has from_date => (
     is => 'rw',
     isa => 'FTM::Time::Spec',
     required => 1,
     trigger => sub {
        my ($self, $date, $old) = @_;
        my $ud = $self->until_date // return;
        FTM::Error::Time::InvalidSpec->throw(
            "from_date ($date) succeeds until_date ($ud)"
        ) if !$date->fix_order($ud);
        my $trigger = $self->can("_onchange_from");
        $self->$trigger($date, $old) if $old && $trigger;
     },
     coerce => 1,
);

has until_date => (
     is => 'rw',
     isa => 'FTM::Time::Spec',
     required => 1,
     trigger => sub {
        my ($self, $date, $old) = @_;
        my $fd = $self->from_date // return;
        FTM::Error::Time::InvalidSpec->throw(
            "until_date ($date) preceeds from_date ($fd)"
        ) if !$fd->fix_order($date);
        my $trigger = $self->can("_onchange_until");
        $self->$trigger($date, $old) if $old && $trigger;
     },
     coerce => 1,
);

has next => (
    is => 'rw',
    does => 'FTM::Time::Structure::Link',
    clearer => 'nonext'
);

sub covers_ts {
    my ($self, $ts) = @_;
    $self->from_date <= $ts && $ts <= $self->until_date;
}

sub get_last_in_chain {
    my ($self) = @_;
    my $last = $self;
    $last = $self while $self = $self->next;
    return $last;
}

around BUILDARGS => sub {
    my ($orig, $class, @args) = @_;

    my $args = $class->$orig(@args);

    my ($from, $to) = @{$args}{'from_date','until_date'};
    $from = $args->{from_date} = FTM::Time::Spec->parse_ts($from)      if !ref $from;
    $args->{until_date}        = FTM::Time::Spec->parse_ts($to, $from) if !ref $to;

    return $args;
};

around 'new_alike' => sub {
    my ($wrapped, $self) = (shift, shift);

    my $args = @_ > 1 ? { @_ } : @_ ? shift : {};
    $_ = ref $_ ? $_ : FTM::Time::Spec->parse_ts($_)
        for grep defined, @{$args}{qw/from_date until_date/};
    $args->{from_date  } //= $self->from_date;
    $args->{until_date} //= $self->until_date;

    return $self->$wrapped($args);

};

sub alter_coverage {
    my ($self, $from_date, $until_date, $fillIn) = @_;

    $fillIn //= $self;
    $_ = FTM::Time::Spec->parse_ts($_)
        for grep { defined && !ref } $from_date, $until_date;
    if ( $from_date && $until_date ) {
        $from_date->fix_order($until_date)
            or FTM::Error::Time::InvalidSpec->throw(
                'FTM::Time::Span::alter_coverage(): dates in wrong order'
            );
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

__END__

=head1 NAME

FTM::Time::Structure::Link - something with an start date, an end date, and a next instance

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


