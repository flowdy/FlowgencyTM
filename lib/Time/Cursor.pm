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
    isa => 'Str',
    default => '',
    init_arg => undef,
);

has timeprofiles => (
    is => 'rw',
    isa => 'Time::Cursor::Profile',
    required => 1,
    coerce => 1,
);

around BUILDARGS => sub {
    my ($orig, $class, @args) = @_;

    my $args = $class->$orig(@args);

    $_ = $class->timeprofiles($_)
        for $args->{timeprofiles};

    return $args;

};

sub run_from {  shift->timeprofiles->start->from_date(@_)  }
sub run_until { shift->timeprofiles->end->until_date(@_)   }

sub reprofile {
    my $self = shift;

    my $list = @_ > 1 ? \@_ : @_ ? shift
             : croak "Time::Cursor::reprofile() missing LIST or ARRAY-ref
        
    my $last = ref $list eq 'HASH'  ? do { my $l = $list; $list=[]; $l }
             : ref $list eq 'ARRAY' ? shift @$list
             :                        return $self->timeprofiles($list);
             ;

    my $until = $last->{until_date};
    $last->{from_date} //= ref $self ? $self->run_from : $until; # temporarily

    my $inilink = Time::Cursor::Profile::Segment->new($last);
    my $pc = Time::Cursor::Profile->new( start => $inilink );
    for my $l ( @$list ) {
        $l->{from_date} //= $last->until_date->successor;
        $l = Time::Cursor::Profile::Segment->new($l);
        $pc->respect($l);
    }
    continue { $last = $l }

    return $self->timeprofiles($pc);

}

sub update {
    my ($self, $time) = @_;

    my @timeprofiles = $self->timeprofiles->all;
    my @ids;
    my $version_hash = sum map {
        push @ids, $_->profile->id;
        $_->version
    } @timeprofiles;
    $version_hash .= "::".join(",", @ids);

    my $old;
    if ( $self->version ne $version_hash ) {
        if ( $self->_has_runner ) {
            $old = $self->_runner->($time,0);
            for ( @timeprofiles ) {
                $_->_onchange_until($_->until_date);
                $_->_onchange_from($_->from_date);
            }
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

package Time::Cursor::Profile {

use Moose;
use FlowTime::Types;
with 'Time::Structure::Chain';

sub dump {
    my ($self) = @_;

    return [ map { join ( " ", $_->name,
             "from", $_->from_date,
             "until", $_->until_date,
         );
       } $self->all ];

}

}

package Time::Cursor::Profile::Segment {

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

    my $extender = !$self->block_partitioning && sub {
       my ($until_date, $next_profile) = @_;

       my $from_date = $last_piece
           ? $last_piece->until_date->successor
           : $self->from_date
           ;

       my $span = __PACKAGE__->new({
           from_date  => $from_date // $until_date,
           until_date => $until_date, profile => $profile,
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
            until_date => $date, profile => $profile,
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

1;
