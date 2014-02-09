#!perl
use strict;
use utf8;

package Time::Structure::Chain;
use Moose::Role;
use Carp qw(croak);

has start => (
    is => 'ro',
    does => 'Time::Structure::Link',
    required => 1,
    writer => '_set_start',
);

has end => (
    is => 'ro',
    does => 'Time::Structure::Link',
    lazy => 1,
    default => sub {
        return last_link_of_chain_from( shift->start );
    },
    writer => '_set_end',
);


sub _find_span_covering {
    my ($self) = shift;
    my ($span,$ts) = @_ > 1 ? @_ : ($self->start,shift);
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

sub couple {
    my ($self,$span) = @_;

    $span->does("Time::Structure::Link")
        or croak "$span: Does not role Time::Structure::Link";

    my ($start,$last) = ($self->start, $self->end);

    my $lspan = last_link_of_chain_from($span);

    my $span_from_date = $span->from_date;
    if ( $span_from_date < $start->from_date->epoch_sec ) {
        my ($start_fd, $lspan_ud) = ($start->from_date, $lspan->until_date);
        my $lspan_ud_succ = $lspan_ud->successor;
        if ( $start_fd > $lspan_ud ) {
            # we need a gap or bridge, at any rate a defaultRhythm span
            my ($start) = $lspan_ud_succ == $start_fd
                ? $start : $start->alter_coverage(
                      $lspan_ud_succ, undef, $self->fillIn
                  )
                ;
            $lspan->next($start);
        }
        else {
            my ($prior, $span2)
                = _find_span_covering(undef, $start, $lspan_ud_succ);
            if ( $span2 ) {
                $span2->from_date($lspan_ud_succ);
                $lspan->next($span2);
            }
            elsif ( $lspan_ud_succ >= $last->until_date ) {
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
        my $span_fd_pred = $span_from_date->predecessor;
        my $last = $span_fd_pred == $last->until_date
            ? $last : $last->alter_coverage(
                  undef, $span_fd_pred => $self->fillIn
            )
        ;
        $last->next($span);
        $self->_set_end($span);
    }
    elsif (
        my ($prior,$trunc_right_span)
            = _find_span_covering(undef, $start, $span_from_date)
      ) {

        my $successor = $lspan->until_date->successor;
        my $trunc_left_span = _find_span_covering(
            undef, $trunc_right_span, $successor
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
       
}

sub all {
    my ($self) = @_; my @links;
    my $span = $self->start; while ( $span ) {
        push @links, $span; $span = $span->next;
    }
    return @links;
}

sub fillIn {
    confess "Time::Structure::Chain'ing class does not fill in gaps"
          . " - no fillIn method defined"
          ;
}

sub detect_circular {
    my $self = shift;
    my $span = $self->start;
    my (%priors, $next);
    while ( $span ) {
        $next = $span->next || return;
        if ( my $p = $priors{$next} ) {
            croak "Circular reference detected for $span "
                . "(prior: $p, rival: $next)"
        }
        $priors{$next} = $span;
    }
    continue { $span = $next }
}

sub last_link_of_chain_from {
    my $span = shift;
    my $next;
    while ( $next = $span->next ) { $span = $next }
    return $span;
}


1;
