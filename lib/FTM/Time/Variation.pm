use strict;

package FTM::Time::Variation;
use FTM::Types;
use Moose;

with 'FTM::Time::Structure::Link';

has name => ( is => 'rw' );

has description => ( is => 'rw' );

has seqno => ( is => 'rw', isa => 'Num' );

has inherit_mode => (
    is => 'rw', isa => 'Str',
    predicate => 'inherit_mode_is_explicit',
);
around inherit_mode => sub {
    my ($orig, $self) = (shift, shift);
    return @_                           ? $self->$orig(@_)
         : exists $self->{inherit_mode} ? $self->$orig()
         :                                $self->track->default_inherit_mode
         ;
};
    
has apply => (
    is => 'rw',
    isa => 'Maybe[Bool|BooleanObject|Str]',
);

has keep_for_referents => (
    is => 'rw',
    isa => 'Num',
    traits => ['Counter'],
    handles => {
        'incr_reference_count' => 'inc',
        'decr_reference_count' => 'dec',
    }
);

has track => (
    is => 'rw',
    required => 1,
    isa => 'FTM::Time::Track',
    weak_ref => 1,
);

sub from_date_is_explicit { 1 }
sub until_date_is_explicit { 1 }
sub week_pattern { shift->track->fillIn->rhythm }

sub like {
    my ($self, $other) = @_;

    return ref($self) eq ref($other)
        && $self->track == $other->track
        && ( ref $self eq __PACKAGE__ || inner() )
        ;
}

sub new_alike {
    my $self = shift;
    my $args = @_ == 1 ? shift : { @_ };
    my $class = __PACKAGE__;

    my $content = (my @content = grep { exists $args->{$_} } qw(
        week_pattern_of_track section_from_track ref week_pattern
    ))[0];

    if ( $content && ref $self && exists $self->{$content} ) {
        $content = '' if !defined $args->{$content};
    }

    FTM::Error::Time::InvalidTrackData->throw(
        "Ambiguity: you passed ", join(" and ", @content), ". Decide"
    ) if @content > 1;

    $class = !defined($content)                  ? ref $self || $class
           : $content eq 'week_pattern_of_track' ? $class.'::BorrowedRhythm'
           : $content eq 'section_from_track'    ? $class.'::Section'
           : $content eq 'ref'                   ? $class.'::Descendent'
           : $content eq 'week_pattern'          ? $class.'::DifferentRhythm'
           :                                       die
           ;

    eval "use $class"; die $@ if $@;

    FTM::Error::Time::HasPast->throw( "New variation would touch the past" )
        if ref $self
        && !$self->ensure_coverage_is_alterable($args->{until_date})
        && $content
        ;

    for my $arg (
      qw/ from_date until_date name description inherit_mode apply track /,
      ref $self && !$content ? $self->_specific_fields : ()
    ) {
        next if exists $args->{$arg};
        next if !ref $self;
        $args->{$arg} = $self->{$arg} // next;
    }

    return $class->new($args);

}
sub _specific_fields {
    # Base class has none
}

sub dump {
    my ($self) = @_;
    my $href = {};
    for my $arg (qw/ from_date until_date name description inherit_mode /, $self->_specific_fields) {
        my $value = $self->$arg() // next;
        if ( index( ref $value, 'FTM::Time' ) == 0 ) {
            if ( ref $value eq 'FTM::Time::Spec' ) { $value = "".$value; }
            else { $value = $value->name }
        } 
        $href->{$arg} = "".$value;
    }
    if ( $self->apply ne "1" ) {
        $href->{apply} = $self->apply();
    }

    return $href;
}

sub span {
    my ($self) = @_;
    return FTM::Time::Span->new({
        variation => $self,
        map { my $v = $self->$_; defined($v) ? ($_ => $v) : () } qw(
            week_pattern description from_date until_date track
        )
    });
}

sub cmp_position_to {
    my ($left, $right) = @_;

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
    #       FTM::Error::Time::InterlacedVariations is thrown.
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

    FTM::Error::Time::InterlacedVariations->throw(
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

    FTM::Error::Time::InterlacedVariations->throw(
        left => $left, right => $right
    );

}

sub ensure_coverage_is_alterable {
    # prevent time variation from altering the past ("used past at least")
    my ($self, $until_date) = @_;
    my $track = $self->track;
    if ( $track->is_used ) {
       my $ref_time = $track->lock_until_date;
       $ref_time = FTM::Time::Spec->now if $ref_time->is_future;
       unless ( $self->from_date > $ref_time ) {
           return if $track->lock_from_date > $self->until_date;
           return if $self->until_date->last_sec > $ref_time
                  && $until_date &&  $until_date > $ref_time
                  ;
           FTM::Error::Time::HasPast->throw(
               "Variation cannot begin/end within the used coverage of the",
                   sprintf " track (%s--%s <= %s)", $self->from_date,
                       $until_date // $self->until_date, $ref_time
           );
       }
    }
    return 1;
}

sub __obsolete_change { # use `$obj = $obj->new_alike({ ... });`
    my ($self, $orig_args) = @_;

    my ($new_class, $args, $has_content) = $self->derive(%$orig_args);
    my $cur_class = ref $self;

    $self->let_alone_past if $has_content
                          || defined $args->{apply}
                          ;

    if ( $new_class eq $cur_class ) {
        while ( my ($key, $value) = each %$args ) {
            $self->$key($value);
        }
    }
    else {
        my $meta = (ref $self)->meta;
        if ( $cur_class ne __PACKAGE__ ) {
            $meta->rebless_instance_back();
        }
        if ( $new_class ne __PACKAGE__ ) {
            $meta->rebless_instance($self, $args);
        }
    }

    return $self;

}
        
sub _change_ref_track {
    my ($self, $new_track, $old_track) = @_;

    if ( $old_track ) {
        $old_track->_drop_ref_child( $self->track, $self->name );
    }
    if ( $new_track ) {
        $new_track->_add_ref_child( $self->track, $self->name );
    }

}
    
__PACKAGE__->meta->make_immutable;

package FTM::Error::Time::InterlacedVariations;
use Moose;
extends 'FTM::Error';

has left => ( is => 'ro', isa => 'FTM::Time::Variation' );
has right => ( is => 'ro', isa => 'FTM::Time::Variation' );

has '+message' => ( required => 0 );

around 'message' => sub {
    my ($orig, $self) = (shift, @_);

    if ( @_ > 2 ) { return $orig->(@_); }

    return $orig->(shift) //
        sprintf "Variations in %s may not be interlaced due to explicit dates: %s <-> %s",
            $self->left->track->name,
            $self->left->name // "left", $self->right->name // "right"
        ;
};

__PACKAGE__->meta->make_immutable;

1;
