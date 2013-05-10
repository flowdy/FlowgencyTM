#!perl
use strict;
use utf8;

package Time::Span;
use Moose;
use Moose::Util::TypeConstraints;
use Time::Point;
use Time::Rhythm;
use Date::Calc qw(Day_of_Week Delta_Days Add_Delta_Days);
use Carp qw(carp croak);

coerce 'Time::Point' => from 'Str' => via { Time::Point->parse_ts(shift) };

has description => ( is => 'rw', isa => 'Str' );

has line => ( is => 'rw', isa => 'Time::Profile', weak_ref => 1 );

has _rhythm => ( is => 'ro', isa => 'Time::Rhythm', required => 1, handles => ['pattern'] );

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
        $self->_rhythm->move_start($dd) if $dd;
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
        $self->_rhythm->move_end($dd) if $dd;
     },
     coerce => 1,
);

has span => ( is => 'ro' );

has next => (
    is => 'rw',
    isa => 'Time::Span',
    clearer => 'nonext'
);

#has is_absence => ( is => 'rw', isa => 'Bool', required => 1 );

around BUILDARGS => sub {
    my ($orig,$class) = (shift,shift);
    my $args = ref $_[0] && @_==1 ? shift : { @_ };

    if ( my $w = delete $args->{week_pattern} ) {
        if ( ref $w ) {
            $w = Time::Rhythm->new(
                pattern => $w->pattern,
                hourdiv => $w->hourdiv,
            );
        }
        else {
            $w = Time::Rhythm->from_string($w);
        }
        $args->{_rhythm} = $w;
    }

    $class->$orig($args);
};

sub BUILD {
    my $self = shift;

    my $from_date = $self->from_date;
    my $until_date = $self->until_date;

    croak "Dates in wrong temporal order"
        if !$from_date->fix_order($until_date);

    my $rhythm = $self->_rhythm;

    my @from_dcomp = $from_date->date_components;
    $rhythm->move_start(Day_of_Week(@from_dcomp)-1);

    my $dd = Date::Calc::Delta_Days(
        @from_dcomp, $until_date->date_components
    );
    $rhythm->move_end($dd+1);
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
    if ( $span =~ s{^\s*--?\s*}{} || $span =~ m{^\s*+} ) {
        $until_date = Time::Point->parse_ts($span,$from_date);
        croak "Bis-Datum liegt vor Von-Datum"
            if !$from_date->fix_order($until_date);
	($rhythm = $until_date->remainder) =~ s{^(:|=>)}{};
    }
    elsif ($span =~ s{^(:|=>)}{} ) {
        $rhythm = Time::Rhythm->from_string($span);
        my $length = $rhythm->loop_size;
        $until_date = Time::Point->parse_ts(sprintf(
            '%4d-%02d-%02d',
            Add_Delta_Days(
                $from_date->fill_in_assumptions->date_components,
                $length - 1
            )
        ));
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
        (ref $rhythm ? '_rhythm' : 'week_pattern' )
                     => $rhythm,
        is_absence   => $is_absence,
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
    my $line = $self->line;
    my $new = __PACKAGE__->new(
        week_pattern => $self->_rhythm,
        from_date    => $self->from_date, # initial only, reset in an instant
        until_date   => $self->until_date, # initial only, reset in an instant
        defined($desc) ? (description  => $desc) : (),
        defined($line) ? (line => $line) : (),
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

sub _calc_slices {
    my ($self, $cursor) = @_;
    # Lücken zwischen den Slices ausfüllen

    return $self->next if $cursor->run_from > $self->until_date;
    return             if $self->from_date  > $cursor->run_until;

    my $orig_slices = []; # $cursor->slices; # need that?

    my ($ts_null, $ssm_offset) = $self->from_date->split_seconds_since_midnight;
    my $stm_offset = $self->until_date->last_sec;
    my $rhythm = $self->_rhythm;
    my $hourdiv = 3600 / $rhythm->hourdiv;

    my $get_pos = sub {
        my ($ts) = @_;
        $ts = $ts->epoch_sec if ref $ts;
        $ts -= $ts_null;
        my $index = int( $ts / $hourdiv );
        my $rest = $ts % $hourdiv;
        return [ $index, $hourdiv - $rest, $rest ]; 
    };
    
    my $get_slice = sub {
        my ($ts1, $ts2) = @_;
        $_ = $get_pos->($_) for $ts1, $ts2;
        my @slice = $rhythm->slice( $ts1->[0], $ts2->[0] );
        for ($slice[0] ) { $_ -= $_/abs($_) * $ts1->[-1] }
        for ($slice[-1]) { $_ -= $_/abs($_) * $ts2->[ 1] }
        return Time::Slice->new(
           span => $self,
           position => ( ref $_[0] ? $_[0]->epoch_sec : $_[0] ),
           slicing => \@slice,
        );
    };

    use List::Util qw(min max);

    my $posit = max($self->from_date->epoch_sec, $cursor->run_from->epoch_sec);
    my $end = min($stm_offset, $cursor->run_until->last_sec);
    
    my @slices;

    SLICE: while ( my $orig_slice = $orig_slices->[0] ) {
        my $pos = $orig_slice->position;
        last if $pos > $end;
        if ( $pos <= $posit ) {
            push @slices, $orig_slice;
            $posit = $pos + $orig_slice->length + 1;
            next SLICE;
        }
        else {
            my $slice = $get_slice->($posit, $pos-1);
            $posit = $pos;
            push @slices, $slice;
            redo SLICE;
        }
    }
    continue { shift @$orig_slices; }

    if ( $posit < $end ) {
        push @slices, $get_slice->($posit, $end);
    }

    return $self->next, @slices;
}

sub calc_slices {
    my ($self,$cursor) = @_;
    my ($next, @slices) = $self;
    while ( $next ) {
        ($next, my @to_append) = $next->_calc_slices($cursor);
        push @slices, @to_append;
    } 
    return \@slices;
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
