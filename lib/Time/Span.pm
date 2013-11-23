#!perl
use strict;
use utf8;

package Time::Span;
use Moose;
use FlowTime::Types;
use Time::Point;
use Time::Rhythm;
use Date::Calc qw(Delta_Days Add_Delta_Days);
use Carp qw(carp croak);
use List::Util qw(min max);

has description => ( is => 'rw', isa => 'Str' );

has profile => ( is => 'rw', isa => 'Time::Profile', weak_ref => 1 );

has rhythm => (
    is => 'ro',
    isa => 'Time::Rhythm',
    handles => ['pattern'],
    init_arg => undef,
);

has from_date => (
     is => 'rw',
     isa => 'Time::Point',
     required => 1,
     trigger => sub {
        my ($self, $date, $old) = @_;
        return if !$old; # do nothing on construction
        croak "from_date must be earlier than or equal to until_date"
            if !$date->fix_order($self->until_date);
        my $dd = Delta_Days( $old->date_components, $date->date_components );
        $self->rhythm->move_start($dd) if $dd;
        delete($self->{_slice});
     },
     coerce => 1,
);

has until_date => (
     is => 'rw',
     isa => 'Time::Point',
     required => 1,
     trigger => sub {
        my ($self, $date, $old) = @_;
        return if !$old; # do nothing on construction
        croak "until_date must be later than or equal to from_date"
            if !$self->from_date->fix_order($date);
        my $dd = Delta_Days($old->date_components, $date->date_components);
        $self->rhythm->move_end($dd) if $dd;
        delete($self->{_slice});
     },
     coerce => 1,
);

has span => ( is => 'ro' );

has slice => (
    is => 'ro',
    lazy => 1,
    builder => '_calc_slice',
    isa => 'Time::Slice',
    init_arg => undef,
);

has next => (
    is => 'rw',
    isa => 'Time::Span',
    clearer => 'nonext'
);

sub BUILD {
    my ($self, $args) = @_;
    my $from_date = $self->from_date;
    my $until_date = $self->until_date;

    croak "Dates in wrong temporal order"
        if !$from_date->fix_order($until_date);

    my @from_dcomp = $from_date->date_components;

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
        @from_dcomp, $until_date->date_components
    ));
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

sub new_shared_rhythm {
    my ($self, $from, $until) = @_;

    $_ = ref $_ ? $_ : Time::Point->parse_ts($_)
        for grep defined, $from, $until;
    $from //= $self->from_date;
    $until //= $self->until_date;

    croak 'from date is later than until date'
        if !$from->fix_order($until);

    my $desc = $self->description;
    my $profile = $self->profile;
    my $new = __PACKAGE__->new(
        week_pattern => $self->rhythm,
        from_date    => $self->from_date, # initial only, reset in an instant
        until_date   => $self->until_date, # initial only, reset in an instant
        defined($desc) ? (description  => $desc) : (),
        defined($profile) ? (profile => $profile) : (),
        #is_absence   => $self->is_absence,
    );

    if ( $from > $self->until_date ) {
        $new->until_date($until);
        $new->from_date($from);
    }
    else {
        $new->from_date($from);
        $new->until_date($until);
    }

    return $new;
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
        $slice = $self->{slice} //= $rhythm->sliced($start, $span_end);
    }
    else {
        $start = max($span_start, $cursor_start);
        $slice = $rhythm->sliced($start, min($span_end, $cursor_end));
    }

    return $cursor_end > $span_end ? $self->next : undef,
           Time::Slice->new(
               span => $self,
               position => $self->from_date->epoch_sec,
               slicing => $slice,
           )
        ;
}

sub calc_slices {
    my ($self,$cursor) = @_;
    my ($next, @slices) = $self;
    while ( $next ) {
        ($next, my $slice) = $next->_calc_slice(
             $cursor->run_from,
             $cursor->run_until,
        );
        push @slices, $slice;
    } 
    return @slices;
}

sub covers_ts {
    my ($self, $ts) = @_;
    $self->from_date <= $ts && $ts <= $self->until_date;
}

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
        if ( $self->pattern == $fillIn->pattern
          || $from_date     >  $self->from_date
        ) {
            $self->from_date($from_date);
            $from_span = $self;
        }
        else {
            my $gap = $fillIn->new_shared_rhythm(
               $from_date, $self->from_date->predecessor
            );
            $gap->next($self);
            $from_span = $gap;
        }
        return $from_span if !defined $until_date;
    }

    if ( $until_date ) {
        if ( $self->pattern == $fillIn->pattern
          || $until_date    <  $self->until_date
        ) {
            $self->until_date($until_date);
            $until_span = $self;
        }
        else {
            my $gap = $fillIn->new_shared_rhythm(
               $self->until_date->successor, $until_date
            );
            $self->next($gap);
            $until_span = $gap;
        }
        return $until_span if !defined $from_date;
    }
    
    return $from_span, $until_span;

}
__PACKAGE__->meta->make_immutable;

1;
