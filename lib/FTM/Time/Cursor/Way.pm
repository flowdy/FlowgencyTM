package FTM::Time::Cursor::Way;
use Moose;
use FTM::Types;
use FTM::Time::Cursor::Stage;

with 'FTM::Time::Structure::Chain';

sub from_stage_hrefs {
    my ($class, @stages) = @_;

    my $start = shift @stages;

    $start->{from_date} //= $start->{until_date};

    my $last = $start = FTM::Time::Cursor::Stage->new($start);
    my $self = $class->new( start => $start );

    for my $s ( @stages ) {
        $s->{from_date} //= $last->until_date->successor;
        $self->couple( $last = FTM::Time::Cursor::Stage->new($s) );
    }

    return $self;

}

sub to_stage_hrefs {
    my $self = shift;
    
    my @stages;
    for my $stage ( $self->all ) {
        push @stages, {
            track => $stage->track,
            until_date => $stage->until_date.q{},
        };
    }

    return @stages;
}

sub dump {
    my $self = shift;

    return [ map { join ( " ", $_->name,
             "from", $_->from_date,
             "until", $_->until_date,
         );
       } $self->all ];

}

sub get_slices {
    my $self = shift;
    my @slices;

    for my $stage ( $self->all ) {
        $stage->add_slices_to_aref( \@slices );
    }

    return \@slices;

}
__PACKAGE__->meta->make_immutable;
__END__

=head1 NAME

FTM::Time::Cursor::Way - Enables the cursor to switch tracks as specified

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

