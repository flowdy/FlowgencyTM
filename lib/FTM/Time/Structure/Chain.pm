#!perl
use strict;
use utf8;

package FTM::Time::Structure::Chain;
use Moose::Role;
use Carp qw(croak);

has start => (
    is => 'ro',
    does => 'FTM::Time::Structure::Link',
    required => 1,
    writer => '_set_start',
);

has end => (
    is => 'ro',
    does => 'FTM::Time::Structure::Link',
    lazy => 1,
    default => sub {
        return shift->start->get_last_in_chain;
    },
    writer => '_set_end',
);


sub find_span_covering {
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

    $span->does("FTM::Time::Structure::Link")
        or croak "$span: Does not role FTM::Time::Structure::Link";

    my ($start,$last) = ($self->start, $self->end);

    my $lspan = $span->get_last_in_chain;

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
                = find_span_covering(undef, $start, $lspan_ud_succ);
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
            = find_span_covering(undef, $start, $span_from_date)
      ) {

        my $successor = $lspan->until_date->successor;
        my $trunc_left_span = find_span_covering(
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
    confess "FTM::Time::Structure::Chain'ing class does not fill in gaps"
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

1;

__END__

=head1 NAME

FTM::Time::Structure::Chain - A list of linked FTM::Time::Structure::Link role-players

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

