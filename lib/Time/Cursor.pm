#!perl
use strict;
use utf8;

package Time::Cursor;
use Carp qw(croak carp);
use Scalar::Util qw(weaken);
use Moose;

my $Config =;

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
    my $self = shift;

    my $old = {};
    my $ref_version = $self->timeprofile->version;
    if ( $self->version < $ref_version ) {
        if ( $self->runner_initialized ) {
            $old = eval { $self->runner->($time,0); } // { error => $@ };
        }
        $self->ensure_capacity;
        $self->version($ref_version);
    }

    my $data = $self->runner->(@_);
    $data{old} = $old if $old;

    return $data;
}

sub _build_runner {
    my ($self, $block_size, $count) = @_;

    my $slices = $self->timeprofile->calc_slices($self);

    # Schwäche Rückreferenzen, an Anfang und Ende aber nur dann, wenn es sich
    # um die von den jeweiligen Zeitspannen referenzierten Arrays handelt.
    # (Dazwischen gehen wir davon aus, wir wollen ja Speicher sparen.)
    weaken($_) for @{$slices}[ 1 .. @$slices-2 ],
                   grep { defined && $_ == $_->span->cached_slice }
                        @{$slices}[ 0,  -1 ]
               ;

    $block_size //= $config{block_size};
    my ($lcnt, $rcnt) = @{ $count // [
        $config{count_left}  // $config{count_both},
        $config{count_right} // $config{count_both},
    ]};

    return sub {
        my ($time) = @_;

        my %ret = map { $_ => 0 } qw(elapsed_pres remaining_pres
                                     elapsed_abs  elapsed_abs);
        $ret{old} = $old if $old;

        $_->calc_pos_data($time,\%ret) for $slices;

        $ret{current_pos} = $ret{elapsed_pres}
            / ( $ret{elapsed_pres} + $ret{remaining_pres} )
                          ;

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
