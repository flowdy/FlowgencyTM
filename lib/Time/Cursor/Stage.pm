package Time::Cursor::Stage;

use Moose;
use FlowTime::Types;
use List::MoreUtils qw(zip);
with 'Time::Structure::Link';

has track => ( is => 'ro', isa => 'Time::Track', required => 1 );

has _partitions => (
    is => 'rw',
    isa => 'Maybe[' . __PACKAGE__ . ']',
    predicate => 'block_partitioning',
    clearer => '_clear_partitions',
    init_arg => 'partitions',
);

sub BUILD {
    my $self = shift;
    my ($from, $to) = ($self->from_date, $self->until_date);
    $self->_onchange_until($to);
    $self->_onchange_from($from);
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
        push @$slices, $track->calc_slices( $from, $until );
    }

    while ( $part ) {
        ($track, $from, $until) =
             map { $self->$_() } qw/track from_date until_date/;
        push @$slices, $track->calc_slices( $from, $until );
        $part = $part->next and $i++;
    }

    return $i;

}

__PACKAGE__->meta->make_immutable;

