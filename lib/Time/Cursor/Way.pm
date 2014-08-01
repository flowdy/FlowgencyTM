package Time::Cursor::Way;
use Moose;
use FlowTime::Types;
use Time::Cursor::Stage;

with 'Time::Structure::Chain';

sub from_stage_hrefs {
    my ($class, @stages) = @_;

    my $start = shift @stages;

    $start->{from_date} //= $start->{until_date};

    my $last = $start = Time::Cursor::Stage->new($start);
    my $self = $class->new( start => $start );

    for my $s ( @stages ) {
        $s->{from_date} //= $last->until_date->successor;
        $self->couple( Time::Cursor::Stage->new($s) );
    }
    continue { $last = $s }

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
