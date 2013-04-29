#!perl
use strict;

package Time::Profile;
use Moose;
use Time::Span;
use Carp qw(carp croak);
#use Moose::Util qw(apply_all_roles);

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
    my ($orig, $class) = @_;

    if ( @_ == 1 ? !ref $_[0] : @_ == 2 ? ref($_[1]) eq 'HASH' : !1 ) {
        my $day_of_month = (localtime)[3];
        my $fillIn = Time::Span->new(
            week_pattern => shift,
            from_date => $day_of_month,   # do really no matter; both time points
            until_date => $day_of_month,  # are adjusted dynamically
        );
        return $class->$orig( ssn => $_[0] );
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
        if ( my $base = $tspan->{reuse} ) {
            $span = $base->new_shared_rhythm(
                @{$tspan}{'from_date', 'until_date'}
            );
        }
        $self->_add_variation($tspan);
    }
    my ($start,$last) = ($self->start, $self->end);

    my $lspan = $span; $lspan = $_ while $_ = $lspan->next;

    my $span_from_date = $span->from_date;
    if ( $span_from_date < $start->from_date->epoch_sec ) {
        if ( $start->from_date > $lspan->until_date ) {
            # we need a gap or bridge, at any rate a defaultRhythm span
            my $gap = $self->fillIn->new_shared_rhythm(
                Time::Point->from_epoch($lspan->until_date->last_sec+1),
                Time::Point->from_epoch($start->from_date->epoch_sec-1),
            );
            $gap->next($start);
            $lspan->next($gap);
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
    elsif ( $span_from_date > $last->until_date->last_sec ) {
        my $gap = $self->fillIn->new_shared_rhythm(
            Time::Point->from_epoch($last->until_date->last_sec+1),
            Time::Point->from_epoch($span_from_date->epoch_sec-1),
        );
        $gap->next($span);
        $last->next($gap);
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

    if ( $start->pattern == $self->fillIn->pattern ) {
        $start->from_date($tp);
    }
    else {
        my $gap = $self->fillIn->new_shared_rhythm(
           $tp, $start->epoch_sec-1
        );
        $gap->next($start);
        $self->set_start($gap);
    }

}

sub mustnt_end_sooner {
    my ($self, $tp) = @_;

    my $end = $self->end;

    return if $tp <= $end->until_date;

    if ( $end->pattern == $self->fillIn->pattern ) {
        $end->until_date($tp);
    }
    else {
        my $gap = $self->fillIn->new_shared_rhythm(
           $end->last_sec+1, $tp
        );
        $end->next($gap);
        $self->set_end($gap);
    }
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

__PACKAGE__->meta->make_immutable;

1;
