#!perl
use strict;
use utf8;

package FTM::Time::Span;
use Moose;
use FTM::Types;
use FTM::Time::Point;
use FTM::Time::Rhythm;
use FTM::Time::SlicedInSeconds;
use Date::Calc qw(Delta_Days Add_Delta_Days);
use Carp qw(carp croak);
use List::Util qw(min max);

with "FTM::Time::Structure::Link";

has description => ( is => 'rw', isa => 'Str' );

has track => ( is => 'rw', isa => 'FTM::Time::Track', weak_ref => 1 );

has rhythm => (
    is => 'ro',
    isa => 'FTM::Time::Rhythm',
    handles => ['pattern'],
    init_arg => undef,
);

has span => ( is => 'ro' );

has slice => (
    is => 'ro',
    lazy => 1,
    builder => '_calc_slice',
    isa => 'FTM::Time::SlicedInSeconds',
    init_arg => undef,
);

sub BUILD {
    my ($self,$args) = @_;

    my @from_dcomp = $self->from_date->date_components;

    my $w = delete $args->{week_pattern}
        or croak 'Missing week_pattern argument';

    my $rhythm = $self->{rhythm} = ref($w)
        ? FTM::Time::Rhythm->new(
            map({ $_ => $w->$_() } qw(pattern hourdiv description)),
            init_day => \@from_dcomp,
          )
        : FTM::Time::Rhythm->from_string(
            $w, { init_day => \@from_dcomp, }
          )
        ;

    $rhythm->move_end(Date::Calc::Delta_Days(
        @from_dcomp, $self->until_date->date_components
    ));
}

sub _onchange_until {
    my ($self, $date, $old) = @_;
    my $dd = Delta_Days($old->date_components, $date->date_components);
    $self->rhythm->move_end($dd) if $dd;
    delete $self->{_slice};
}

sub _onchange_from {
    my ($self, $date, $old) = @_;
    my $dd = Delta_Days($old->date_components, $date->date_components);
    $self->rhythm->move_start($dd) if $dd;
    delete $self->{_slice};
}

sub from_string {
    my ($class, $span) = @_;
    my $orig_span = $span;

    my $is_absence = $span =~ s{^!}{};
    my ($dates, $week_pattern) = split /:/, $span, 2;

    my ($from_date,$until_date);
    $from_date = FTM::Time::Point->parse_ts($span);
    $span = $from_date->remainder;
    my $rhythm;

    # 1. Handelt es sich bei $dates um ein Anfangs und Enddatum?
    if ( $span =~ s{^\s*--?\s*}{} || $span =~ m{^\s*\+} ) {
        $until_date = FTM::Time::Point->parse_ts($span,$from_date);
        croak "Bis-Datum liegt vor Von-Datum"
            if !$from_date->fix_order($until_date);
	($rhythm = $until_date->remainder) =~ s{^(:|=>)}{};
    }
    else {
        # Wir haben es mit einem einzigen Tag zu tun
        my $hours = $span =~ s{ (@ [\d:,-]+) \z }{}xms ? $1 : q{};
        $rhythm = "Mo-So$hours"; 
        $until_date = $from_date;
    }
    
    return $class->new({
        span         => $orig_span,
        from_date    => $from_date,
        until_date   => $until_date,
        week_pattern => $rhythm,
    });
}

sub new_alike {
    my ($self, $args) = @_;

    for my $arg (qw/from_date until_date description track/) {
        next if exists $args->{$arg};
        $args->{$arg} = $_ if defined($_ = $self->$arg());
    }

    $args->{week_pattern} = $self->rhythm;
    return ( ref $self )->new($args);

}

sub new_shared_rhythm {
    shift->new_alike({
        (map { my $arg = shift; defined($arg) ? ($_ => $arg) : () }
            qw/from_date until_date/
        ), $_[0] ? %{+shift} : ()
    });
}

sub _calc_slice {
    my ($self, $from, $until) = @_;

    if ( @_ > 1 ) {
        return $self->next if $from > $self->until_date;
        return             if $self->from_date > $until;
    }
    else {
        $from = $self->from_date;
        $until = $self->until_date;
    }

    my $span_start = $self->from_date->epoch_sec;
    my $cursor_start = $from->epoch_sec;
    my $span_end = $self->until_date->last_sec + 1;
    my $cursor_end = $until->last_sec + 1;
    my ($ts_null) = $self->from_date->split_seconds_since_midnight;
    $_ -= $ts_null for $span_start, $span_end, $cursor_start, $cursor_end;
    my $rhythm = $self->rhythm;

    my ($start, $slice);
    if ( $span_start >= $cursor_start && $span_end <= $cursor_end ) {
        $start = $span_start;
        if ( my $s = $self->{slice} ) { return scalar $self->next, $s }
        $slice = $rhythm->sliced($start, $span_end);
    }
    else {
        $start = max($span_start, $cursor_start);
        $slice = $rhythm->sliced($start, min($span_end, $cursor_end));
    }

    return $cursor_end > $span_end ? scalar $self->next : undef,
           FTM::Time::SlicedInSeconds->new(
               span => $self,
               position => $ts_null + $start,
               slicing => $slice,
           )
        ;
}

sub calc_slices {
    my ($self, $from, $until) = @_;
    my ($next, @slices) = ($self);
    while ( $next ) {
        ($next, my $slice) = $next->_calc_slice( $from, $until );
        push @slices, $slice // ();
    } 
    return @slices;
}

sub like {
    my ($self, $fillIn) = @_;
    $self->pattern == $fillIn->pattern;
}

after alter_coverage => sub {
    delete $_[0]->{slice}
};

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Time::Span - connect a coverage between from and until time point to a time rhythm

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

