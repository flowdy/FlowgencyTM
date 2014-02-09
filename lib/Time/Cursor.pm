package Time::Cursor;
use Carp qw(croak carp);
# use Scalar::Util qw(weaken); # apparently no more needed
use List::Util qw(sum);
use FlowTime::Types;
use Moose;
use Time::Cursor::Way;
use Time::Point;

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
    isa => 'Time::Cursor::Way',
    required => 1,
);

around BUILDARGS => sub {
    my ($orig, $class, @args) = @_;

    my $args = $class->$orig(@args);

    if ( my $t = $args->{timestages} ) {
        croak "timestages attribute not an array-ref"
            if ref $t ne "ARRAY";
        $t->[0]->{from_date} = $args->{start_ts}
            // croak "missing start_date attribute";
        $args->{_timeway} = Time::Cursor::Way->from_stage_hrefs(@$t);
    }
    else {
        croak "Missing mandatory attribut timestages used ".
              "to initialize internal _timeway";
    }

    return $args;

};

sub start_ts {  shift->_timeway->start->from_date(@_)  }
sub due_ts { shift->_timeway->end->until_date(@_)   }

sub change_way {
    return shift->_timeway( Time::Cursor::Way->from_stage_hrefs(@_) );
}

sub apply_stages {
    my $way = shift->_timeway;
    for my $stage_href ( @_ ) {
        my $stage = Time::Cursor::Stage->new($stage_href); 
        $way->couple($stage);
    }
}

sub update {
    my ($self, $time) = @_;

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
            $old = $self->_runner->($time,0);
            $self->_clear_runner;
        }
        $self->version($version_hash);
    }

    my $data = $self->_runner->($time);
    $data->{old} = $old if $old;

    my $current_pos = $data->{elapsed_pres} /
        ( $data->{elapsed_pres} + $data->{remaining_pres} )
                          ;

    return %$data, current_pos => $current_pos;
}

sub _build__runner {
    my ($self) = @_;

    my $slices = $self->_timeway->get_slices;

    return sub {
        my ($time) = @_;

        my %ret = map { $_ => 0 } qw(elapsed_pres remaining_pres
                                     elapsed_abs  elapsed_abs);

        $_->calc_pos_data($time,\%ret) for @$slices;

        return \%ret;
    }
}

sub alter_coverage {
    my ($self, $from, $until) = @_;
    $_ = Time::Point->parse_ts($_) for $from, $until;
    if ( $from->fix_order($until) ) {
        $self->run_from($from);
        $self->run_until($until);
    }
    else {
        $self->run_until($until);
        $self->run_from($from);
    }
}

__PACKAGE__->meta->make_immutable;

