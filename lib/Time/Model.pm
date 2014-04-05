#!perl
use strict;

package Time::Model;
use Moose;
use Carp qw(carp croak);
use Date::Calc;
use Scalar::Util qw( blessed );
use Time::Track;

has _time_tracks => (
    is => 'ro',
    isa => 'HashRef[Time::Track]',
    traits => [ 'Hash' ],
    default => sub { {} },
    handles => { get_track => 'get' },
);

sub from_json {
    use Algorithm::Dependency::Ordered;
    use Algorithm::Dependency::Source::HoA;
    use JSON ();

    my $class = shift;

    my $model = JSON::from_json(shift);

    my %dependencies;

    while ( my ($id, $track_init_data) = each %$model ) {

        my %is_required; # keys:   $id_of_required_track
                         # values: \@scalar_refs_to_be_filled_with_track_oref

        # Prior to track $id being constructed, all its parents must be ready
        my $parents_key = 'unmentioned_variations_from';
        if ( my $p = $track_init_data->{$parents_key} ) {
            for my $p ( ref $p ? @$p : $track_init_data->{$parents_key} ) {
                push @{$is_required{$p}}, \$p;
            }
        }

        # ... and its successor, if any
        if ( my $succ = $track_init_data->{successor} ) {
            $is_required{ $succ } = [ \$track_init_data->{successor} ];
        }

        # ... to not forget its variations which are sections of another track
        for my $var ( @{ $track_init_data->{variations} } ) {
            my $s;
            if ( $s = $var->{track_section} ) {
                push @{$is_required{$s}}, \$var->{section_from};
            }
            elsif ( $s = $var->{ref} and $model->{$s} ) {
                push @{$is_required{$s}}, \$var->{ref};
            }
        }

        $dependencies{$id} = [ keys %is_required ];

        $track_init_data->{ _requires } = \%is_required;
        $track_init_data->{ name      } = $id;

    }

    my $order = Algorithm::Dependency::Ordered->new(
        source => Algorithm::Dependency::Source::HoA->new(\%dependencies),
    )->schedule_all;

    for my $track ( @{$model}{ @$order } ) {
        my $requirements = delete $track->{ _requires };
        while ( my ($id, $refs) = each %$requirements ) {
            my $dep_track = $model->{$id};
            die "track $id not constructed" if !blessed($dep_track);
            for my $ref ( @$refs ) { $$ref = $dep_track; }
        }
        $track = Time::Track->new(delete $track->{week_pattern}, $track);
    } 
    
    return $class->new( _time_tracks => $model );

}

__PACKAGE__->meta->make_immutable;

1;
