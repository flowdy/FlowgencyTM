package FTM::Time::Cursor::Stage;

use Moose;
use FTM::Types;
use List::MoreUtils qw(zip);
with 'FTM::Time::Structure::Link';

has track => ( is => 'ro', isa => 'FTM::Time::Track', required => 1 );

has prior_slice => ( # used for estimating completion time
    isa => 'FTM::Time::SlicedInSeconds',
    reader => 'pass_after_slice',
    writer => '_set_prior_slice',
);

has _partitions => (
    is => 'rw',
    isa => 'Maybe[' . __PACKAGE__ . ']',
    predicate => 'block_partitioning',
    clearer => '_clear_partitions',
    init_arg => 'partitions',
);

*BUILD = \&ensure_track_coverage;
            
sub ensure_track_coverage {
    my $self = shift;
    my ($from, $to) = ($self->from_date, $self->until_date);
    my $track = $self->track;
    my $ultim_from = $track->start->from_date;
    my $ultim_to   = $track->end->until_date;
    if ( $to < $ultim_from ) {
        $self->_onchange_from($from);
        $self->_onchange_until($to);
    }
    else {
        $self->_onchange_until($to);
        $self->_onchange_from($from);
    } 
    return 1;

}

sub like {
    my ($self, $other) = @_;
    return $self->track eq $other->track;
}

sub new_alike {
    my ($self, $args) = @_;

    $args->{track} = $self->track;

    return __PACKAGE__->new($args);

}

sub version {
    my ( $track, $from, $until ) = map { $_[0]->$_() } 
        qw/ track from_date until_date /
    ;
    my @from  = reverse split //, $from->epoch_sec =~ s/0*$//r;
    my @until = reverse split //, $until->last_sec =~ s/0*$//r;
    my $version = $track->version;
    my $tail    = join "", map { $_ // 0 } zip @from, @until; 
    return "$version.$tail"+0; 
}

sub _onchange_from {
    my ($self, $date) = @_;
    $self->track->mustnt_start_later($date);
    if ( my $part = $self->_partitions ) {
        $part->from_date($date);
    }
    return;
}

sub _onchange_until {
    my ($self, $date) = @_;
    my ($last_piece, $track) = (undef, $self->track);

    # Redoing our partitions to reflect the until_latest/successor
    # settings of our track (if any).
    #
    $self->_clear_partitions if $self->_partitions;

    my $extender = !$self->block_partitioning && sub {
       my ($until_date, $next_track) = @_;

       my $from_date = $last_piece
           ? $last_piece->until_date->successor
           : $self->from_date
           ;

       my $span = __PACKAGE__->new({
           from_date  => $from_date // $until_date,
           until_date => $until_date, track => $track,
           partitions => undef, # to block recursion
       });

       if ( $last_piece ) {
           $last_piece->next($span);
       }
       else {
           $self->_partitions($span);
       }

       $track = $next_track;
       $last_piece = $span;

    };

    $self->track->mustnt_end_sooner($date, $extender);

    if ( $last_piece ) {
        $last_piece->next(__PACKAGE__->new(
            from_date  => $last_piece->until_date->successor,
            until_date => $date, track => $track,
            partitions => undef,
        ));
    }

    return;
}

sub add_slices_to_aref {
    my ($self, $slices) = @_;
    my ($track, $from, $until, $part)
       = map { $self->$_() } qw/track from_date until_date _partitions/;

    my $i = 1;
    if ( !$part ) {
        if ( my $s = $slices->[-1] ) { $self->_set_prior_slice( $s ); }
        push @$slices, $track->calc_slices( $from, $until );
    }

    while ( $part ) {
        ($track, $from, $until) =
             map { $part->$_() } qw/track from_date until_date/;
        if ( my $s = $slices->[-1] ) { $part->_set_prior_slice( $s ); }
        push @$slices, $track->calc_slices( $from, $until );
        $part = $part->next and $i++;
    }

    return $i;

}

sub partition_sensitive_iterator {
    my $self = shift;
    my $part = $self->_partitions;

    return (
        $part // $self,
        sub {
            return if !$self;
            my $next;

            # Find next partition or stage
            1 until $next
                = $part ? ($part = $part->next) : do {
                    $self = $self->next        or return;
                    $part = $self->_partitions or $self;
                }
            ;

            return $next;

        }
    );
}
__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Time::Cursor::Stage - a cursor's association with a time track

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

