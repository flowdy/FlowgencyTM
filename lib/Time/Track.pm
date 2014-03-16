#!perl
use strict;

package Time::Track;
use Moose;
use Time::Span;
use Carp qw(carp croak);
use Scalar::Util qw(blessed refaddr);

has name => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has fillIn => (
    is => 'ro',
    isa => 'Time::Span',
    required => 1,
);

with 'Time::Structure::Chain';

has version => (
    is => 'rw',
    isa => 'Int',
    default => do { my $i; sub { ++$i } },
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
        my $span = $self->find_span_covering(shift);
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
        my ($self, $succ) = @_;
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
        my %opts = @_ ? %{+shift} : ();
        return $class->$orig({ %opts, fillIn => $fillIn });
    }
 
    else {
        return $class->$orig(@_);
    }

};

sub calc_slices {
    my ($self, $from, $until) = @_;
    $from = $from->run_from if $from->isa("Time::Cursor");

    return $self->find_span_covering($self->start, $from)
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

    my $from_span = $self->find_span_covering($from);
    my $until_span = $self->find_span_covering($from_span, $until);

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
    my $successor = $self->successor;

    my $until_latest = $self->until_latest // do {
        if ( $successor ) {
            my $from_earliest = $successor->from_earliest
                // croak "Cannot succeed at unknown point in time";
            $from_earliest->predecessor;
        }
        else { undef }
    };
    
    return if ( !$until_latest || $end->until_date == $until_latest )
           && $tp <= $end->until_date;
        ;

    my $tp1 = $tp;
    if ( $until_latest && $tp > $until_latest ) {
        croak "Can't end after maximal until_date" . ( $successor
            ? " (could with a passed extender sub-ref)"
            : q{}
          ) if !($successor && $extender);
        $extender->($until_latest, $successor);
        $tp1 = $until_latest;
    }
    
    my $end_span = $end->alter_coverage( undef, $tp1, $self->fillIn );
    $self->_set_end($end_span);

    if ( $successor ) {
        $successor->mustnt_end_sooner($tp, $extender);
    }

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

sub timestamp_of_nth_net_second_since {
    my ($self, $net_seconds, $ts, $early_pass) = @_;
    
    # Argument validation
    croak 'The number of net seconds (argument #1) is undefined'
        if !defined $net_seconds;
    croak 'Missing timestamp from when to count (argument #2)'
        if !( ref($ts) ? blessed($ts) && $ts->isa('Time::Point') : $ts );

    # If correspondent Time::Cursor method has called us: Get extended data
    my ($next_stage, $signal_slice, $last_sec) = do {
        if ( $early_pass and my $p = $early_pass->() ) {
            my $slice = $p->pass_after_slice;
            $p, $slice, $slice->position + $slice->length;
        }
        else { undef, undef, undef; }
    };

    # Pass through to all slices up to a) where next stage says so
    # or b) all net seconds are found or c) our spans are exhausted.
    my $span = $self->start; 
    my $pos = { remaining_pres => -($net_seconds||1) };
    my $lspan;
    my $epts = ref $ts ? $ts->epoch_sec : $ts;
    while ( $pos->{remaining_pres} < 0 && $span ) {         # b), c)
        if ( $last_sec && $span->covers_ts($last_sec) ) {   # a)
            $signal_slice->calc_pos_data( $epts, $pos );
            return $next_stage->track->timestamp_of_nth_net_second_since(
                abs $pos->{remaining_pres}, $next_stage->from_date, $early_pass
            );
        }
        else {
            $span->slice->calc_pos_data( $epts, $pos );
        }
    }
    continue {
        $lspan = $span;
        $span  = $span->next;
    }

    my ($rem_abs, $rem_pres) = @{ $pos }{qw{ remaining_abs remaining_pres }};
    if ( $rem_pres < 0 ) {
        # There still are net seconds remaining so we must gather them
        # in our base rhythm, respecting however any until_latest setting ...

        my $find_pres_sec = abs $rem_pres;
        my $seek_from_ts = $lspan->until_date->successor;
        my $successor = $self->successor;
        my $rhythm = $self->fillIn->rhythm;
        my $coverage = $successor && (
            $self->until_latest->last_sec - $seek_from_ts->epoch_sec
        );

        my ($found_pres_seconds, $plus_rem_abs)
          = $rhythm->net_seconds_per_week
            ? $rhythm->count_absence_between_net_seconds(
                $seek_from_ts, $find_pres_sec,
                $coverage && ($coverage - $find_pres_sec)
              )
            : 0
            ;

        $rem_abs += $plus_rem_abs;

        if ( my $remaining = $find_pres_sec - $found_pres_seconds ) {
            die "no successor to gather $remaining seconds" if !$successor;
            die "remaining seconds negative" if $remaining < 0;
            my $start_ts = $self->until_latest->successor;
            return $successor->timestamp_of_nth_net_second_since(
                $remaining, $start_ts
            );
        }

    }

    elsif ( $rem_pres ) {
       # If we have gone to far, we will have to go back
       $rem_abs -= $lspan->slice->absence_in_presence_tail($rem_pres);
    }

    else {}

    return Time::Point->from_epoch(
        $ts->epoch_sec + $net_seconds + $rem_abs, 
    );
}

__PACKAGE__->meta->make_immutable;

1;
