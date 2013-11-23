#!perl
use strict;
use utf8;

package Time::Cursor;
use Carp qw(croak carp);
use Scalar::Util qw(weaken);
use FlowTime::Types;
use Time::Point;
use Moose;

has _runner => (
    is => 'rw',
    isa => 'CodeRef',
    lazy_build => 1,
    init_arg => undef,
);

has version => (
    is => 'rw',
    isa => 'Int',
    default => 0,
    init_arg => undef,
);

has timeprofile => (
    is => 'ro',
    isa => 'Time::Profile',
    required => 1,
);

has [qw|run_from run_until|] => (
    is => 'rw',
    isa => 'Time::Point',
    required => 1,
    coerce => 1,
    trigger => sub {
        my ($self, $new, $old) = @_;
        $old and $self->ensure_capacity();
    },
);

sub BUILD {
    my $self = shift;
    $self->ensure_capacity(); 
}

sub ensure_capacity {
    my ($self) = @_;
    my $timeprofile = $self->timeprofile;
    my $from = $self->run_from;
    my $to = $self->run_until;
    croak "Cannot run backwards in time"
       if !$from->fix_order($to);
    $timeprofile->mustnt_start_later($from);
    $timeprofile->mustnt_end_sooner($to);
    $self->_clear_runner;
}
            
sub update {
    my ($self, $time) = @_;

    my $old = {};
    my $ref_version = $self->timeprofile->version;
    if ( $self->version < $ref_version ) {
        if ( $self->_has_runner ) {
            $old = $self->_runner->($time,0);
        }
        $self->ensure_capacity;
        $self->version($ref_version);
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

    my @slices = $self->timeprofile->calc_slices($self);

    return sub {
        my ($time) = @_;

        my %ret = map { $_ => 0 } qw(elapsed_pres remaining_pres
                                     elapsed_abs  elapsed_abs);

        $_->calc_pos_data($time,\%ret) for @slices;

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

1;
