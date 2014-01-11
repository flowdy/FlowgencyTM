#!perl
use strict;
use utf8;

package Time::Cursor;
use Carp qw(croak carp);
use Scalar::Util qw(weaken);
use List::Util qw(sum);
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
    isa => 'Float',
    default => 0.0,
    init_arg => undef,
);

{ use Moose::TypeConstraints;
  coerce 'Time::Cursor::ProfileChain',
    from 'HashRef|ArrayRef[HashRef]',
    via {
        my $list = shift;
        my $last = ref $list eq 'HASH' ? do { my $l = $list; $list=[]; $l }
                                       : shift @$list
                 ;
        my $until = $last->{until_date};
        $last->{from_date} //= $until; # temporarily
        my $inilink = Time::Cursor::ProfileChain::Link->new($last);
        my $pc = Time::Cursor::ProfileChain->new( start => $inilink );
        for my $l ( @$list ) {
            $l->{from_date} //= $last->until_date->successor;
            $l = Time::Cursor::ProfileChain::Link->new($l);
            $pc->respect($l);
        }
        continue { $last = $l }
        return $pc;
    }
}

has timeprofiles => (
    is => 'ro',
    isa => 'Time::Cursor::ProfileChain',
    auto_deref => 1,
    required => 1,
    coerce => 1,
);

sub run_from {  shift->timeprofiles->start->from_date(@_)  }
sub run_until { shift->timeprofiles->end->until_date(@_)   }

sub update {
    my ($self, $time) = @_;

    my @timeprofiles = $self->timeprofiles->all;
    my $version_hash = sum map { $_->version } @timeprofiles;

    my $old;
    if ( $self->version != $version_hash ) {
        if ( $self->_has_runner ) {
            $old = $self->_runner->($time,0);
            $_->_onchange_until($_->until_date)
                for @timeprofiles;
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

    my @slices;

    my $span = $self->timeprofiles;

    while ( my $tp = $self->timeprofiles ) {
        $tp->add_slices(\@slices);
    }

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

use 5.014;

package Time::Cursor::ProfileChain {

use Moose;
use FlowTime::Types;
with 'Time::Structure::Chain';

sub dump {
    my ($self) = @_;

    return [ map { join ( " ", $span->name,
             "from", $span->from_date,
             "until", $span->until_date,
         );
       } $self->all ];

}

sub all {
    my ($self) = @_;
    my @links;
    my $span = $self->start;
    while ( $span ) {
        push @links, $span;
        $span = $span->next;
    }
    return @links;
}


}

package Time::Cursor::ProfileChain::Link {

use Moose;
use FlowTime::Types;
use List::MoreUtils qw(zip);
with 'Time::Structure::Link';

has profile => ( is => 'ro', isa => 'Time::Profile', required => 1 );

has _partitions => (
    is => 'rw',
    isa => 'Maybe[' . __PACKAGE__ . ']',
    predicate => 'block_partitioning',
    clearer => '_clear_partitions',
);

sub BUILD {
    my $self = shift;
    my ($from, $to) = ($self->from_date, $self->until_date);
    $self->_onchange_until($to);
    $self->_onchange_from($from);
    return 1;
}
            
sub like {
    my ($self, $other) = @_;
    return $self->profile eq $other->profile;
}

sub new_alike {
    my ($self, $args) = @_;

    $args->{profile} = $self->profile;

    return __PACKAGE__->new($args);

}

sub version {
    my ( $profile, $from, $until ) = map { $_[0]->$_() } 
        qw/ profile from_date until_date /
    ;
    my @from  = reverse split //, $from->epoch_sec =~ s/0*$//r;
    my @until = reverse split //, $until->last_sec =~ s/0*$//r;
    return $profile->version . q{.} . join "", zip @from, @until; 
}

sub _onchange_from {
    my ($self, $date) = @_;
    $self->profile->mustnt_start_later($date);
    if ( my $part = $self->_partitions ) {
        $part->from_date($date);
    }
    return;
}

sub _onchange_until {
    my ($self, $date) = @_;
    my ($last_piece, $profile) = (undef, $self->profile);

    # Redoing our partitions to reflect the until_latest/successor
    # settings of our profile (if any).
    #
    $self->_clear_partitions if $self->partitions;
                              # ^^^ not using predicate here!

    my $extender = !$self->block_partitioning && sub {
       my ($until_date, $next_profile) = @_;

       $from_date = $last_piece
                  ? $last_piece->until_date->successor
                  : $self->from_date
                  ;

       my $span = __PACKAGE__->new({
           from_date  => $from_date // $until_date,
           until_date => $until_date,
           profile    => $profile,
           partitions => undef, # to block recursion
       });

       if ( $last_piece ) {
           $last_piece->next($span);
       }
       else {
           $self->partitions($span);
       }

       $profile = $next_profile;
       $last_piece = $span;

    };

    $self->profile->mustnt_end_sooner($date, $extender);

    if ( $last_piece ) {
        $last_piece->next(__PACKAGE__->new(
            from_date  => $last_piece->until_date->successor,
            until_date => $date,
            profile    => $profile,
            partitions => undef,
        ));
    }

    return;
}

sub add_slices ($\@) {
    my ($self, $slices) = shift;
    my ($profile, $from, $until, $part)
       = map { $self->$_() } qw/profile from_date until_date partitions/;

    my $i = 1;
    if ( !$part ) {
        push @$slices, $profile->calc_slices( $from, $until );
    }

    while ( $part ) {
        ($profile, $from, $until) =
             map { $self->$_() } qw/profile from_date until_date/;
        push @$slices, $profile->calc_slices( $from, $until );
        ++$i if $part = $part->next;
    }

    return $i;

}

}

package main;

my $l = Time::Link->new({ from_date => "6. 18:00", until_date => "20.1. 12:00", name => "foo" });

my $c = Time::Chain->new({ start => $l, end => $l });

my $l2 = Time::Link->new({ from_date => "2. 15:30", until_date => "7. 14:00", name => "bar" });

$c->respect($l2);

$c->respect(new Time::Link { from_date => "20.1. 12:01:01", until_date => "3.2. 10:00", name => "zed" });

$DB::single=1;
1;
1;
