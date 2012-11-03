#!perl
use strict;
use utf8;

package Time::Cursor;
use Carp qw(croak carp);
use Moose;

has slices => (
    is => 'rw',
    isa => 'ArrayRef',
    auto_deref => 1,
);

has version => (
    is => 'rw',
    isa => 'Int',
    default => 0,
    init_arg => undef,
);

has timeline => (
    is => 'ro',
    isa => 'Time::Line',
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
    my $timeline = $self->timeline;
    my $from = $self->run_from;
    my $to = $self->run_until;
    croak "Cannot run backwards in time"
       if !$from->fix_order($to);
    $timeline->mustnt_start_later($from);
    $timeline->mustnt_end_sooner($to);
    $self->slices([]);
}
            
sub update {
    my ($self, $time ) = @_;

    my $old = {};
    my $ref_version = $self->timeline->version;
    if ( !@{$self->slices} or my $outdated = $self->version < $ref_version ) {
        for ( $self->slices ) { $old = $_->calc_pos_data($time); }
        $self->ensure_capacity if $outdated;
        $self->slices($self->timeline->calc_slices($self));
        $self->version($ref_version);
    }

    my %ret = map { $_ => 0 } qw(elapsed_pres remaining_pres
                                 elapsed_abs  elapsed_abs);
    $ret{old} = $old if $old;

    $_->calc_pos_data($time,\%ret) for $self->slices;

    return %ret, current_pos =>
        $ret{elapsed_pres} / ($ret{elapsed_pres} + $ret{remaining_pres})
        ;

}

1;
