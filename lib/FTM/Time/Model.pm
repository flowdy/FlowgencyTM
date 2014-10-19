#!perl
use strict;

package FTM::Time::Model;
use Moose;
use Carp qw(carp croak);
use Date::Calc;
use Scalar::Util qw( blessed );
use FTM::Util::DependencyResolver qw( ordered );
use FTM::Time::Track;
use JSON ();

has _time_tracks => (
    is => 'ro',
    isa => 'HashRef[FTM::Time::Track]',
    traits => [ 'Hash' ],
    default => sub { {} },
    handles => { get_track => 'get', register_track => 'set' },
);

sub from_json {

    my $class = shift;

    my $model = JSON::from_json(shift);

    my %dependencies;

    while ( my ($id, $track_init_data) = each %$model ) {

        my $is_required = FTM::Time::Track->gather_dependencies($track_init_data);

        $dependencies{$id} = [ keys %$is_required ];

        $track_init_data->{ _requires } = $is_required;
        $track_init_data->{ name      } = $id;

    }

    for my $track ( @{$model}{ ordered(\%dependencies) } ) {
        _bind_tracks( $model => delete $track->{ _requires } );
        $track = FTM::Time::Track->new($track);
    } 
    
    return $class->new( _time_tracks => $model );

}

sub to_json {
    my ($self) = @_;
    my %dump = %{ $self->_time_tracks };
    for my $track ( values %dump ) {
        $track = $track->dump;
    }
    return JSON::to_json( \%dump );
}

sub update {
    my ($self, $tracks) = @_;

    my $dependencies;
    while ( my ($name, $data) = each %$tracks ) {
        my $track = $self->get_track($name);
        my $is_required = FTM::Time::Track->gather_dependencies($data);
        $dependencies->{$name} = [ keys %$is_required ];
        $self->_bind_tracks($is_required);
        for my $track ( map {${ $_->[0] }} values %$is_required ) {
            $track->gather_dependencies($dependencies);
        }
        if ( $track ) {
            my $family = $track->gather_family;
            delete $family->{$name};
            push @{$dependencies->{$_}}, $name for keys %$family;
        }
    }

    for my $name ( ordered( $dependencies ) ) {
        my $data = $tracks->{$name} // next;
        if ( my $track = $self->get_track($name) ) {
            $track->update($data);
        }
        else {
            $data->{name} = $name;
            $self->register_track(
                $name => FTM::Time::Track->new($data)
            );
        }
    }
}

sub _bind_tracks {
    my ($tracks, $requirements) = @_;
    $tracks = $tracks->_time_tracks if blessed $tracks;
    while ( my ($id, $refs) = each %$requirements ) {
        my $dep_track = $tracks->{$id};
        die "track $id not constructed" if !blessed($dep_track);
        for my $ref ( @$refs ) {
            if ( ref $$ref ) {
                die "Track instance claims it depends on '$id' "
                  . "but refers to another object: $$ref"
                  if $$ref != $dep_track;
            }
            else { $$ref = $dep_track; }
        }
    }
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Time::Model - collection of (perhaps interdependent) time tracks

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 COPYRIGHT

(C) 2012-2014 Florian Hess

=head1 LICENSE

This file is part of FlowTiMeter.

FlowTiMeter is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowTiMeter is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowTiMeter. If not, see <http://www.gnu.org/licenses/>.

