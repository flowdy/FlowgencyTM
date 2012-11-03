#!perl
use strict;

package Time::Line;
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

sub calc_slices {
    my ($self, $cursor) = @_;
    my $span = $self->start;
    my $ts0 = $cursor->run_from;
    $span = $span->next until $span->covers_ts($ts0);
    return $span->calc_slices($cursor);
}

sub respect {
    my ($self,$span) = @_;

    my ($start,$last) = ($self->start, $self->end);

    my $find_span_covering = sub {
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
    };
    
    my $span_from_date = $span->from_date;
    if ( $span_from_date < $start->from_date->epoch_sec ) {
        if ( $start->from_date > $span->until_date ) {
            # we need a gap or bridge, at any rate a defaultRhythm span
            my $gap = $self->fillIn->new_shared_rhythm(
                Time::Point->from_epoch($span->until_date->last_sec+1),
                Time::Point->from_epoch($start->from_date->epoch_sec-1),
            );
            $gap->next($start);
            $span->next($gap);
        }
        else {
            my $ts = $span->until_date->successor;
            my ($prior, $span2) = $find_span_covering->($start, $ts);
            if ( $span2 ) {
                $span2->from_date($ts);
                $span->next($span2);
            }
            elsif ( $ts >= $last->until_date ) {
                $last->next($span);
                $self->_set_end($span);
            }
            elsif ( $prior ) {
                my $next = $prior->next();
                $prior->next($span);
                $span->next($next);
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
            = $find_span_covering->($start, $span_from_date)
      ) {

        my $successor = $span->until_date->successor;
        my $trunc_left_span = $find_span_covering->(
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
            $span->next($trunc_left_span);
        }
        else { $self->_set_end($span); } 

    }
    else { die }
       
    #apply_all_roles($span, 'Time::Span::SubHiatus') unless $span->is_absence;
    $self->version($self->version+1);
    return;
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
__PACKAGE__->meta->make_immutable;

__END__

package Time::Line::Presence;
use Moose;
extends 'Time::Line';

has absence => (
    is => 'ro',
    isa => 'Time::Line::Absence',
    required => 1,
);

sub BUILD {
    my ($self, $args) = @_;
    $self->absence->presence($self);
}

around respect => sub {
    my ($self, $orig, $span) = @_;

    $self->$orig($span);

    $self->absence->mustnt_start_later($span->from_date);
    $self->absence->mustnt_end_sooner($span->until_date);
};

__PACKAGE__->meta->make_immutable;

package Time::Line::Absence;
use Moose;
extends 'Time::Line';

has presence => (
    is => 'ro',
    isa => 'Time::Line::Presence',
    weak_ref => 1,
);

around respect => sub {
    my ($self, $orig, $span) = @_;

    $self->$orig($span);

    $self->presence->mustnt_start_later($span->start);
    $self->presence->mustnt_end_sooner($span->until_date);
};

1;
