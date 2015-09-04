use strict;

package FTM::Time::Track::Variation;
use FTM::Types;
use Moose;

with FTM::Time::Structure::Link;

for my $date ( 'from_date', 'until_date' ) {
    has "+$date" => ( required => 0, predicate => "${date}_is_explicit" );
}

has name => ( is => 'rw' );

has position => ( is => 'rw' );

has description => ( is => 'rw' );

has ref => (
    is => 'rw',
    isa => 'Maybe[Str]',
    trigger => sub {
       my ($self) = @_;
       $_ = undef for @{$self}{'week_pattern','section_from_track'};
    },
    lazy => 1,
    default => sub {
       my ($self) = @_;
       return $self->name if !$self->week_pattern
                          && !$self->section_from_track
                          ;
       return;
    }
);

has week_pattern => (
    is => 'rw',
    isa => 'Maybe[FTM::Time::Rhythm]',
    trigger => sub {
       my ($self) = @_;
       delete @{$self}{'ref','section_from_track'};
    },
    coerce => 1,
);

has section_from_track => (
    is => 'rw',
    isa => 'Maybe[FTM::Time::Track]',
    trigger => sub {
       my ($self) = @_;
       delete @{$self}{'week_pattern','ref'};
    },
);

has inherit_mode => ( is => 'rw', isa => 'Str' );

has apply => ( is => 'rw', isa => 'Str|Bool' );

has base => ( is => 'rw', isa => 'FTM::Time::Track::Variation', weaken => 1 );

has track => ( is => 'rw', isa => 'FTM::Time::Track', weaken => 1 );

for my $prop (qw(from_date until_date description week_pattern section_from_track inherit_mode)) {
    around $prop => sub {
        my ($orig, $self, @val) = @_;
        return $self->$orig(@val) if @val || exists $self->{$prop};
        return $self->base->$prop();
    }
}

sub cmp_position_to {
    my ($left, right) = @_;

    # For variations situated properly apart in regard to their start/end
    # dates, returns -1 or 1 like <=> does. If two variations interlace, it
    # either returns 0 or throws an exception:
    #    a) It returns 0 = "equal" if at least one of the start/end dates
    #       causing the interlace is not defined explicitly in the same track
    #       but is implied by fallback to what is defined for a variation with
    #       the indicated name higher in the track ancestry.
    #       So stable sort leaves their order untouched and we can guarantee
    #       that the variation mentioned right-hand in the track's list of own
    #       or adapted variations trims or covers the left-hand one.
    #    b) If both end/start dates are explicit, an exception of class
    #       FTM::X::VariationsInterlace is thrown.
    #       
    # Thus, the user can change start/end dates of variations without worrying
    # about position conflicts between variations in other tracks.
    # 

    my $mode = 0;
    my ($a_fd, $a_ud, $b_fd, $b_ud) = (
        $left->from_date, $left->until_date,
        $right->from_date, $right->until_date,
    );
    if ( $left ->from_date_is_explicit  ) { $mode |= 8 }
    if ( $left ->until_date_is_explicit ) { $mode |= 4 }
    if ( $right->from_date_is_explicit  ) { $mode |= 2 }
    if ( $right->until_date_is_explicit ) { $mode |= 1 }

    return -1 if $b_fd > $a_ud && $a_fd < $b_ud;
    return  1 if $b_fd < $a_ud && $a_fd > $b_ud;

    FTM::Error::TimeTrackVariation::Interlaced->throw(
        left => $left, right => $right
    ) if $mode == 15 
      || ( ( $mode & 10 ) == 10 && $a_fd == $b_fd )
      || ( ( $mode &  9 ) ==  9 && $a_fd == $b_ud )
      || ( ( $mode &  6 ) ==  6 && $a_ud == $b_fd )
      || ( ( $mode &  5 ) ==  5 && $a_ud == $b_ud )
    ;

    return 0 if $mode ==  7 ? $b_fd > $a_ud || $a_ud > $b_ud
              : $mode == 11 ? $b_fd > $a_fd || $a_fd > $b_ud
              : $mode == 13 ? $a_fd > $b_ud || $b_ud > $a_ud
              : $mode == 14 ? $a_fd > $b_fd || $b_fd > $a_ud
              :               1
              ;

    FTM::Error::TimeTrackVariation::Interlaced->throw(
        left => $left, right => $right
    );

}

package FTM::Error::TimeTrackVariation::Interlaced;
extends FTM::Error;

has left => ( isa => 'FTM::Time::Track::Variation' );
has right => ( isa => 'FTM::Time::Track::Variation' );

has '+message' => ( required => 0 );

around 'message' => sub {
    my $orig = shift;

    if ( @_ > 1 ) { return $orig->(@_); }

    return $orig->(shift) //
        sprintf "Variations in %s interlaced due to explicit dates: %s <-> %s",
            $left->track->name,
            $left->name // "$left", $right->name // "$right"
        ;
};

1;
