#!perl
use strict;

package Time::Profile;
use Moose;
use Time::Span;
use Carp qw(carp croak);
use Scalar::Util qw(refaddr);

has version => (
    is => 'rw',
    isa => 'Int',
    default => 0,
);

has start => (
    is => 'ro',
    isa => 'Time::Span',
    required => 1,
    writer => '_set_start',
    init_arg => 'fillIn',
);

has end => (
    is => 'ro',
    isa => 'Time::Span',
    required => 1,
    writer => '_set_end',
    init_arg => 'fillIn',
);

has fillIn => (
    is => 'ro',
    isa => 'Time::Span',
    required => 1,
);

has _parent => (
    is => 'ro',
    isa => 'Time::Profile',
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
    my ($self, $cursor) = @_;
    my $ts0 = $cursor->run_from;
    my $span = _find_span_covering($self->start, $ts0);
    return $span->calc_slices($cursor);
}

sub _find_span_covering {
    my ($span,$ts) = @_;
    my $prior;

    until ( $span->covers_ts($ts) ) {
        $prior = $span;
        $span = $span->next || return;
        if ( $span->from_date > $ts ) {
            $span = undef;
            last;
        }
    }
    return $prior, $span;
}

sub respect {
    my ($self,$span) = @_;

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

    my ($start,$last) = ($self->start, $self->end);

    my $lspan = $span; $lspan = $_ while $_ = $lspan->next;

    my $span_from_date = $span->from_date;
    if ( $span_from_date < $start->from_date->epoch_sec ) {
        if ( $start->from_date > $lspan->until_date ) {
            # we need a gap or bridge, at any rate a defaultRhythm span
            my $start = $start->alter_coverage(
                $lspan->until_date->successor, undef, $self->fillIn
            );
            $lspan->next($start);
        }
        else {
            my $ts = $lspan->until_date->successor;
            my ($prior, $span2) = _find_span_covering($start, $ts);
            if ( $span2 ) {
                $span2->from_date($ts);
                $lspan->next($span2);
            }
            elsif ( $ts >= $last->until_date ) {
                $last->next($span);
                $self->_set_end($lspan);
            }
            elsif ( $prior ) {
                my $next = $prior->next();
                $prior->next($lspan);
                $lspan->next($next);
            }
            else { die }
        }
        $self->_set_start($span);
    }
    elsif ( $span_from_date > $last->until_date ) {
        my $last = $last->alter_coverage(
            undef, $span_from_date->predecessor => $self->fillIn
        );
        $last->next($span);
        $self->_set_end($span);
    }
    elsif (
        my ($prior,$trunc_right_span)
            = _find_span_covering($start, $span_from_date)
      ) {

        my $successor = $lspan->until_date->successor;
        my $trunc_left_span = _find_span_covering(
            $trunc_right_span, $successor
        );

        my $former_ud = $trunc_right_span->until_date;
        my $former_next = $trunc_right_span->next;
        if ( $trunc_right_span->from_date < $span_from_date ) {
            $trunc_right_span->until_date($span->from_date->predecessor);
            $trunc_right_span->next($span);
        }
        elsif ( $prior ) {
            $prior->next($span);
        }
        else { $self->_set_start($span); }

        if ( $trunc_left_span ) {
            if ( $trunc_left_span == $trunc_right_span ) {
                $trunc_left_span =
                    $trunc_right_span->new_shared_rhythm(
                        $successor, $former_ud
                    );
                if ( $former_next ) { $trunc_left_span->next($former_next); }
                else { $self->_set_end($trunc_left_span); }
            }
            else { $trunc_left_span->from_date($successor); }
            $lspan->next($trunc_left_span);
        }
        else { $self->_set_end($span); } 

    }
    else { die }
       
    #apply_all_roles($span, 'Time::Span::SubHiatus') unless $span->is_absence;
    $self->version($self->version+1);
    return;
}

sub get_section {
    my ($self, $from, $until) = @_;

    ref $_ or $_ = Time::Point->parse_ts($_) for $from, $until;
    $from->fix_order($until) or croak 'from and until arguments in wrong order';

    $self->mustnt_start_later($from);
    $self->mustnt_end_sooner($until);

    my $from_span = _find_span_covering($self->start, $from);
    my $until_span = _find_span_covering($from_span, $until);

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

    $start = $start->alter_coverage($tp, undef, $self->fillIn);

    #if ( $start->pattern == $self->fillIn->pattern ) {
        #$start->from_date($tp);
    #}
    #else {
        #my $gap = $self->fillIn->new_shared_rhythm(
           #$tp, $start->epoch_sec-1
        #);
        #$gap->next($start);
        #$self->set_start($gap);
    #}

    $self->_set_start($start);

}

sub mustnt_end_sooner {
    my ($self, $tp) = @_;

    my $end = $self->end;

    return if $tp <= $end->until_date;

    $end = $end->alter_coverage( undef, $tp, $self->fillIn );

    #if ( $end->pattern == $self->fillIn->pattern ) {
        #$end->until_date($tp);
    #}
    #else {
        #my $gap = $self->fillIn->new_shared_rhythm(
           #$end->last_sec+1, $tp
        #);
        #$end->next($gap);
        #$self->set_end($gap);
    #}

    $self->_set_end($end);

    return;
}


sub detect_circular {
    use Data::Dumper;
    local $Data::Dumper::Maxdepth=3;
    my $self = shift;
    my $span = $self->start;
    my %priors = (); my $next;
    while ( $span ) {
        $next = $span->next || return;
        if ( my $p = $priors{$next} ) {
            die 'Zirkularer Bezug: '.Dumper({
                former => [ $p, $p->description ],
                rival => [ $span, $span->description ],
                span => [ $next, $next->description ]
            });
        }
        $priors{$next} = $span;
    }
    continue { $span = $next }
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
        $rem_abs += $self->fillIn->rhythm->count_absence_between_net_seconds(
            $lspan->until_date->successor, abs $rem_pres
        );
    }
    else {
        croak "timestamp not found";
    }

    return Time::Point->from_epoch(
        $ts->epoch_sec + $net_seconds + $rem_abs - 1,
        ($ts->get_precision) x 2,
    );
}

__PACKAGE__->meta->make_immutable;

1;
