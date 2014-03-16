#!perl
use strict;
use utf8;

package Time::Span;
use Moose;
use FlowTime::Types;
use Time::Point;
use Time::Rhythm;
use Time::SlicedInSeconds;
use Date::Calc qw(Delta_Days Add_Delta_Days);
use Carp qw(carp croak);
use List::Util qw(min max);

with "Time::Structure::Link";

has description => ( is => 'rw', isa => 'Str' );

has track => ( is => 'rw', isa => 'Time::Track', weak_ref => 1 );

has rhythm => (
    is => 'ro',
    isa => 'Time::Rhythm',
    handles => ['pattern'],
    init_arg => undef,
);

has span => ( is => 'ro' );

has slice => (
    is => 'ro',
    lazy => 1,
    builder => '_calc_slice',
    isa => 'Time::SlicedInSeconds',
    init_arg => undef,
);

sub BUILD {
    my ($self,$args) = @_;

    my @from_dcomp = $self->from_date->date_components;

    my $w = delete $args->{week_pattern}
        or croak 'Missing week_pattern argument';

    my $rhythm = $self->{rhythm} = ref($w)
        ? Time::Rhythm->new(
            map({ $_ => $w->$_() } qw(pattern hourdiv description)),
            init_day => \@from_dcomp,
          )
        : Time::Rhythm->from_string(
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
    $from_date = Time::Point->parse_ts($span);
    $span = $from_date->remainder;
    my $rhythm;

    # 1. Handelt es sich bei $dates um ein Anfangs und Enddatum?
    if ( $span =~ s{^\s*--?\s*}{} || $span =~ m{^\s*\+} ) {
        $until_date = Time::Point->parse_ts($span,$from_date);
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

    for my $arg (qw/description track/) {
        next if exists $args->{$arg};
        $args->{$arg} = $_ if defined($_ = $self->$arg());
    }

    $args->{week_pattern} = $self->rhythm;
    return __PACKAGE__->new($args);

}

sub new_shared_rhythm {
    shift->new_alike({
        map { my $arg = shift; defined($arg) ? ($_ => $arg) : () }
            qw/from_date until_date/
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
        if ( my $s = $self->{slice} ) { return $s }
        $slice = $rhythm->sliced($start, $span_end);
    }
    else {
        $start = max($span_start, $cursor_start);
        $slice = $rhythm->sliced($start, min($span_end, $cursor_end));
    }

    return $cursor_end > $span_end ? $self->next : undef,
           Time::SlicedInSeconds->new(
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
        push @slices, $slice;
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

1;
