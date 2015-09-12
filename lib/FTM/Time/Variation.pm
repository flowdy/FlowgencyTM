use strict;

package FTM::Time::Variation;
use Moose;

with FTM::Time::Structure::Link;

has name => ( is => 'rw' );

has description => ( is => 'rw' );

has inherit_mode => ( is => 'rw', isa => 'Str' );

has apply => ( is => 'rw', isa => 'Str|Bool' );

has track => (
    is => 'rw',
    isa => 'FTM::Time::Track',
    weak_ref => 1,
);

sub from_date_is_explicit { 1 }
sub until_date_is_explicit { 1 }
sub week_pattern { shift->track->week_pattern }

sub span {
    my ($self) = @_;
    return FTM::Time::Span->new({
        map { $_ => $self->$_ } qw(
            week_pattern description from_date until_date
        )
    });
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
    #       FTM::Error::TimeVariation::Interlaced is thrown.
    #
    # Thus, the user can change start/end dates of variations without worrying
    # about position conflicts between variations in other tracks.
    # 

    my $mode = 0;
    if ( $left ->from_date_is_explicit  ) { $mode |= 8 }
    if ( $left ->until_date_is_explicit ) { $mode |= 4 }
    if ( $right->from_date_is_explicit  ) { $mode |= 2 }
    if ( $right->until_date_is_explicit ) { $mode |= 1 }

    my ($a_fd, $a_ud, $b_fd, $b_ud) = (
        $left->from_date, $left->until_date,
        $right->from_date, $right->until_date,
    );

    return -1 if $b_fd > $a_ud && $a_fd < $b_ud;
    return  1 if $b_fd < $a_ud && $a_fd > $b_ud;

    FTM::Error::TimeVariation::Interlaced->throw(
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

    FTM::Error::TimeVariation::Interlaced->throw(
        left => $left, right => $right
    );

}

sub subtype_instance {
    use FTM::Time::Variation::BorrowedRhythm;
    use FTM::Time::Variation::Derived;
    use FTM::Time::Variation::DifferentRhythm;
    use FTM::Time::Variation::Section;

    my (undef, $args) = @_;
    my $package = __PACKAGE__;

    if ( $args->{ref} ) {
        if ( $args->{ref} =~ s/^@// ) {
            croak "Contradiction: Can't depend on another object as week_pattern is passed"
                if $args->{week_pattern};
            if ( $args->{ref} =~ s/\+$// ) {
                $package .= '::Section';
            }
            elsif ( length $args->{ref} ) {
                $package .= '::BorrowedRhythm';
            }
        }
        else {
            $package .= '::Derived';
        }
    }
    
    elsif ( $args->{week_pattern} ) {
        croak "Contradiction: Can't depend on another object as week_pattern is passed"
            if $args->{ref};
        $package .= '::DifferentRhythm';
    }

    return $package->new($args);

}

package FTM::Error::TimeVariation::Interlaced;
extends FTM::Error;

has left => ( isa => 'FTM::Time::Variation' );
has right => ( isa => 'FTM::Time::Variation' );

has '+message' => ( required => 0 );

around 'message' => sub {
    my $orig = shift;

    if ( @_ > 1 ) { return $orig->(@_); }

    return $orig->(shift) //
        sprintf "Variations in %s may not be interlaced due to explicit dates: %s <-> %s",
            $left->track->name,
            $left->name // "$left", $right->name // "$right"
        ;
};

1;
