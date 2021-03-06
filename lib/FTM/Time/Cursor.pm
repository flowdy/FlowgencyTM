package FTM::Time::Cursor;
use strict;
use Carp qw(croak carp);
# use Scalar::Util qw(weaken); # apparently no more needed
use List::Util qw(sum);
use POSIX qw(strftime);
use FTM::Types;
use Moose;
use FTM::Time::Cursor::Way;
use FTM::Time::Spec;

my @POSITION_SLOTS
   = qw(elapsed_pres remaining_pres elapsed_abs remaining_abs);
has _runner => (
    is => 'rw',
    isa => 'CodeRef',
    lazy_build => 1,
    init_arg => undef,
);

has version => (
    is => 'rw',
    isa => 'Str',
    default => '',
    init_arg => undef,
);

has _timeway => (
    is => 'rw',
    isa => 'FTM::Time::Cursor::Way',
    trigger => \&_must_have_working_time,
    required => 1,
);

around BUILDARGS => sub {
    my ($orig, $class, @args) = @_;

    my $args = $class->$orig(@args);

    if ( my $t = $args->{timestages} ) {
        croak "timestages attribute not an array-ref"
            if ref $t ne "ARRAY";
        $t->[0]->{from_date} = $args->{start_ts}
            // croak "missing start_ts attribute";
        $args->{_timeway} = FTM::Time::Cursor::Way->from_stage_hrefs(@$t);
    }
    else {
        croak "Missing mandatory attribute timestages used ".
              "to initialize internal _timeway";
    }

    return $args;

};

sub start_ts {  shift->_timeway->start->from_date(@_)  }
sub due_ts { shift->_timeway->end->until_date(@_)   }

sub change_way {
    return shift->_timeway( FTM::Time::Cursor::Way->from_stage_hrefs(@_) );
}

sub _must_have_working_time {
    my ($self, $newtw, $oldtw) = @_;
    my %pos = $self->update( $self->start_ts );
    if ( !$pos{ remaining_pres } ) {
        $self->{_timeway} = $oldtw;
        FTM::Error::Task::InvalidDataToStore->throw(
            'No working time available in chosen period and track'
        );
    }
}

sub apply_stages {
    my $way = shift->_timeway;
    for my $stage_href ( @_ ) {
        my $stage = FTM::Time::Cursor::Stage->new($stage_href); 
        $way->couple($stage);
    }
}

sub _get_unixtime {
    my $time = shift;
    $time //= FTM::Time::Spec->now;
    if ( ref $time && $time->isa('FTM::Time::Spec') ) {
        $time = $time->epoch_sec;
    }
    return $time;
}

sub update {
    my ($self, $time) = @_;

    $time = _get_unixtime($time);

    my @timeway = $self->_timeway->all;
    my @ids;
    my $version_hash = sum map {
        push @ids, $_->track->name;
        $_->version
    } @timeway;
    $version_hash .= "::".join(",", @ids);

    my $old;
    if ( $self->version ne $version_hash ) {
        if ( $self->_has_runner ) {
            for ( @timeway ) { $_->ensure_track_coverage; }
            $old = $self->_runner->($time);
            $self->_clear_runner;
        }
        $self->version($version_hash);
    }

    my $data = $self->_runner->($time);
    $data->{old} = $old if $old;

    $data->{remaining_pres} ||= do {
        my $overdue = $self->start_ts->epoch_sec
            + $data->{elapsed_pres} + $data->{elapsed_abs}
            - $time;
        $data->{elapsed_pres} -= $overdue;
        $data->{state} = 1;
        $overdue; 
    };

    my $current_pos = $data->{elapsed_pres}
        / ( $data->{elapsed_pres} + $data->{remaining_pres} || 1 )
        ;

    return %$data, current_pos => $current_pos;

}

sub _build__runner {
    my ($self) = @_;

    my $slices = $self->_timeway->get_slices;

    return sub {
        my ($time, $until) = @_;

        my %ret = map { $_ => 0 } @POSITION_SLOTS;

        my @dump;

        if ( ref $until ) {
            return _splicing_between($slices, $time, $until);
        }
        else {
            my $i = 0;
            for ( @$slices ) {
                $_->calc_pos_data($time,\%ret);
                $i++ if !$ret{reach_for_next};
                if ( $until && $until eq 'dump' ) {
                    push @dump, {
                        %ret,
                        span => $_->span,
                        until_date => strftime(
                            "%Y-%m-%d %H:%M:%S",
                            localtime( $_->position + $_->length - 1 )
                        ),
                    }
                }
            }
            if ( delete $ret{reach_for_next}
              && $ret{remaining_pres} > $ret{seconds_until_switch}
            ) {
                my @rfn = ($ret{span});
                my $sus = \$ret{seconds_until_switch};
                while ( my $next = $slices->[++$i] ) {
                    my $nsl = $next->slicing;
                    last if ($$sus < 0) xor ($nsl->[0] < 0);
                    $$sus += $nsl->[0];
                    push @rfn, $next->span;
                    last if @$nsl > 1;
                }
                $ret{span} = \@rfn;
            }
            $_ = abs for $ret{seconds_until_switch} // ();
            return @dump ? @dump : \%ret;
        }
    }
}

sub alter_coverage {
    my ($self, $from, $until) = @_;
    $_ = FTM::Time::Spec->parse_ts($_) for $from, $until;
    if ( $from->fix_order($until) ) {
        $self->run_from($from);
        $self->run_until($until);
    }
    else {
        $self->run_until($until);
        $self->run_from($from);
    }
}

sub timestamp_of_nth_net_second_since {
    my ($self, $net_seconds, $from_ts) = @_;

    my $stage = defined($from_ts)
        ? $self->_timeway->find_span_covering($from_ts)
             // FTM::Error::Time::InvalidSpec->throw(
                    "Time $from_ts not covered by cursor timeway"
                )
        : $self->_timeway->start;

    my ($stage_part, $iter) = $stage->partition_sensitive_iterator;

    if ( $from_ts ) {
        $stage_part = $iter->() until $stage_part->covers_ts($from_ts);
    }
    
    return $stage_part->track->timestamp_of_nth_net_second_since(
        $net_seconds, $from_ts // $stage->from_date, $iter
    );
}

sub slicing_between {
    my ($self, $time, $until) = @_;

    $time->fix_order($until) if ref $time && ref $until;
    if ( ref $time ) { $time = $time->epoch_sec }
    if ( ref $until ) { $until = $until->last_sec }

    return $self->_runner->( $time, $until );
}

sub _splicing_between {
    my ($slices, $time, $until) = @_;
    my $until_diff = $until - $time;
    my $start = $slices->[0]->position;
    my ($end) = map { $_->position + $_->length } $slices->[-1];

    return if $until < $start || $time > $end;

    my $diff = $time - $start;
    my @sec;
    if ( $diff < 0 ) {
        push @sec, $diff;
        $until_diff += $diff;
        $diff = 0;
    }
    for my $sl ( @$slices ) {
        my $add = $sl->splice( \$diff, \$until_diff );
        push @sec, @$add;
        last if !$until_diff;
    }
    if ( $until_diff ) {
        push @sec, -$until_diff;
    }

    return \@sec;
}

sub dump_timestages {
    my ($self, $ts) = @_;
    $ts = _get_unixtime($ts);
    my @stages = $self->_runner->($ts, "dump");
    my @new_stages;
    my $cumulate = { map { $_ => 0 } @POSITION_SLOTS };
    my ($s, $v);
    my $ltrack = 0;
    while ( $s = shift @stages ) {
        for my $slot ( @POSITION_SLOTS ) {
            $s->{ $slot } -= $cumulate->{ $slot };
            $cumulate->{ $slot } += $s->{ $slot };
            my $seconds = $s->{ $slot };
            my $minutes = int( $seconds / 60 );
            $seconds -= $minutes * 60;
            my $hours   = int( $minutes / 60 );
            $minutes -= $hours * 60;
            $s->{ $slot } = sprintf "%d:%02d:%02d", $hours, $minutes, $seconds;
        }
        my $span = $s->{span};
        $s->{span} = {
             pattern => $span->rhythm->description,
             description => $span->description,
             vname => do { if ( $v = $span->variation ) { $v->name } },
             $span->track == $ltrack ? () : do {
                 $ltrack = $span->track;
                 track => sprintf "%s [%s]", $ltrack->label, $ltrack->name;
             },
        };
        for my $vname ( $s->{span}{vname} // () ) {
            $vname .= ", originally defined in track ".$v->track->name
                if $v->track != $ltrack;
        }
        push @new_stages, $s;
    }    
    return $self->start_ts, @new_stages;
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Time::Cursor - Get us working-time progress data at a point after starting date

=head1 SYNOPSIS

 my %pos = $cursor->update($timepoint_or_seconds_since_epoch);

 # Created in FTM::Task::_build_cursor

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

