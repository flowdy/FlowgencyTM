#!perl
use strict;

package Time::Track;
use Moose;
use Time::Span;
use Carp qw(carp croak);
use Scalar::Util qw(refaddr);

has fillIn => (
    is => 'ro',
    isa => 'Time::Span',
    required => 1,
);

with 'Time::Structure::Chain';

has version => (
    is => 'rw',
    isa => 'Int',
    default => sub { time - $^T },
    lazy => 1,
    clearer => '_update_version',
);

has ['+start', '+end'] => (
    init_arg => 'fillIn'
);

has ['from_earliest', 'until_latest'] => (
    is => 'rw',
    isa => 'Time::Point',
    coerce => 1,
    trigger => sub {
        my $self = shift;
        my $span = $self->_find_span_covering(shift);
        if ( $span ) {
            croak "Time track borders can be extended, not narrowed";
        }
        $self->_update_version;
    }
);

has successor => (
    is => 'ro',
    isa => 'Time::Track',
    trigger => sub {
        my ($self, $succ) = shift;
        $succ->mustnt_start_later($self->end->until_date->successor);
        $self->_update_version;
    }
);

has _parent => (
    is => 'ro',
    isa => 'Time::Track',
    init_arg => 'parent',
);

has _variations => (
    is => 'ro',
    isa => 'ArrayRef[HashRef]',
    init_arg => undef,
    default => sub { [] },
    traits => [ 'Array' ],
    handles => { _add_variation => 'push' },
);

around BUILDARGS => sub {
    my ($orig, $class) = (shift, shift);

    if ( @_ == 1 ? !ref $_[0] : @_ == 2 ? ref($_[1]) eq 'HASH' : !1 ) {
        my $day_of_month = (localtime)[3];
        my $fillIn = Time::Span->new(
            week_pattern => shift,
            from_date => $day_of_month,  # do really no matter; both time points
            until_date => $day_of_month, # are adjusted dynamically
        );
        return $class->$orig({ fillIn => $fillIn });
    }
 
    else {
        return $class->$orig(@_);
    }

};

sub calc_slices {
    my ($self, $from, $until) = @_;
    $from = $from->run_from if $from->isa("Time::Cursor");

    return $self->_find_span_covering($self->start, $from)
               ->calc_slices($from, $until);
}

around couple => sub {
    my ($wrapped, $self, $span) = @_;
    
    if ( ref $span eq 'HASH' ) {
        my $tspan = $span;
        if ( my $base = $tspan->{obj} ) {
            $span = $base->new_shared_rhythm(
                @{$tspan}{'from_date', 'until_date'}
            );
        }
        else {
            $span = Time::Span->new($tspan);
            $tspan->{obj} = $span;
        }
        $self->_add_variation($tspan);
    }

    $self->$wrapped($span);

    #apply_all_roles($span, 'Time::Span::SubHiatus') unless $span->is_absence;
    $self->_update_version;
    return;

};

sub get_section {
    my ($self, $from, $until) = @_;

    ref $_ or $_ = Time::Point->parse_ts($_) for $from, $until;
    $from->fix_order($until) or croak 'from and until arguments in wrong order';

    $self->mustnt_start_later($from);
    $self->mustnt_end_sooner($until);

    my $from_span = $self->_find_span_covering($from);
    my $until_span = $self->_find_span_covering($from_span, $until);

    if ( $from_span == $until_span ) {
        return $from_span->new_shared_rhythm($from, $until);
    }

    my $start_span = $from_span->new_shared_rhythm($from, undef);

    my ($last_span, $cur_span) = ($start_span, $from_span->next);
    until ( $cur_span && $cur_span == $until_span ) {
        my $next_span = $cur_span->new_shared_rhythm();
        $last_span->next( $next_span );
        $cur_span = $cur_span->next;
    }
    
    if ( $cur_span ) {
        $last_span->next( $cur_span->new_shared_rhythm(undef, $until) );
    }

    return $start_span;

}

sub dump {
    my ($self,$index,$length) = @_;
    my $span = $self->start;
    if ( defined $index ) {
        croak 'negative indices not supported' if $index < 0;
        $length //= 1;
    }
    else {
        $length //= -1;
    }
    1 while $index-- and $span = $span->next;
    my @dumps;
    while ( $length-- && $span ) {
        my $rhythm = $span->rhythm;
        push @dumps, {
            description => $span->description,
            from_date   => $span->from_date.q{},
            until_date  => $span->until_date.q{},
            rhythm      => {
                 patternId => refaddr($rhythm->pattern),
                 description => $rhythm->description,
                 from_week_day => $rhythm->from_week_day,
                 until_week_day => $rhythm->until_week_day,
                 mins_per_unit => 60 / $rhythm->hourdiv,
                 atomic_enum => $rhythm->atoms->to_Enum,
            },
        };
    }
    continue {
        $span = $span->next;
    }
    return @dumps;
}

sub reset {
    my ($self) = @_;
    my $fillIn = $self->fillIn;
    $fillIn->nonext;
    $self->_set_start($fillIn);
    $self->_set_end($fillIn);
}

sub mustnt_start_later {
    my ($self, $tp) = @_;

    my $start = $self->start;

    return if $start->from_date <= $tp;

    croak "Can't start before minimal from_date"
        if $self->from_earliest && $tp < $self->from_earliest;

    $start = $start->alter_coverage($tp, undef, $self->fillIn);

    $self->_set_start($start);

}

sub mustnt_end_sooner { # recursive on successor if any
    my ($self, $tp, $extender) = @_;

    my $end = $self->end;

    return if $tp <= $end->until_date;

    my $successor = $self->successor;
    my $until_latest = $self->until_latest // do {
        if ( $successor ) {
            my $from_earliest = $successor->from_earliest
                // croak "Cannot succeed at unknown point in time";
            $from_earliest->predecessor;
        }
        else { undef }
    };

    my $tp1 = $tp;
    if ( $until_latest && $tp > $until_latest ) {
        croak "Can't end after maximal until_date"
            if !$extender;
        $extender->($until_latest, $successor);
        $tp1 = $until_latest;
    }
    
    if ( $successor ) {
        $successor->mustnt_end_sooner($tp, $extender);
    }

    $end = $end->alter_coverage( undef, $tp1, $self->fillIn );

    $self->_set_end($end);

    return;
}


sub inherit_variations {
    my ($self, $expl_var) = @_;

    my ( @to_suggest, @to_impose );
    if ( my $p = $self->parent ) {
        my ($inner_suggest, $inner_impose) = $p->inherit_variations($expl_var);
        @to_suggest = @$inner_suggest;
        @to_impose = @$inner_impose;    
    }

    for my $v ( @{$self->_variations} ) {
        
    }

}

sub seek_last_net_second_timestamp {
    my ($self, $ts, $net_seconds) = @_;
    
    my $span = $self->start;
    my $pos = { remaining_pres => -$net_seconds };
    my $lspan;
    while ( $span && $pos->{remaining_pres} < 0 ) {
        $span->slice->calc_pos_data($ts->epoch_sec,$pos);
        ($lspan, $span) = ($span,$span->next);
    }

    my $rem_abs = $pos->{remaining_abs};
    my $rem_pres = $pos->{remaining_pres};
    if ( $rem_pres >= 0 ) {
        my $sl = $lspan->slice->slicing;
        my ($val, $pres, $abs) = (undef, 0, 0);
        for ( my $i = -1; $pres < $rem_pres; $i-- ) {
            $val = $sl->[$i];
            ($val > 0 ? $pres : $abs) += abs $val;
        }
        $rem_abs -= $abs;
    }
    elsif ( $rem_pres < 0 ) {

        my $find_pres_sec = abs $rem_pres;
        my $seek_from_ts = $lspan->until_date->successor;
        my $successor = $self->successor;
        my $rhythm = $self->fillIn->rhythm;
        my $coverage = $successor && (
            $self->until_latest->last_sec - $seek_from_ts->epoch_sec
        );

        my $found_pres_seconds = $rhythm->net_seconds_per_week
            ? $rhythm->count_absence_between_net_seconds(
                $seek_from_ts, $find_pres_sec,
                $coverage && ($coverage - $find_pres_sec)
              )
            : 0
            ;

        if ( my $remaining = $find_pres_sec - $found_pres_seconds ) {
            return $successor->seek_last_net_second_timestamp(
                $seek_from_ts, $remaining
            );
        }

    }
    else {
        croak "Timestamp not found - not enough time on this track";
    }

    return Time::Point->from_epoch(
        $ts->epoch_sec + $net_seconds + $rem_abs - 1,
        ($ts->get_precision) x 2,
    );
}

__PACKAGE__->meta->make_immutable;

1;