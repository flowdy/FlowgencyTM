#!perl
use strict;

package Time::Track;
use Moose;
use Time::Span;
use Carp qw(carp croak);
use Scalar::Util qw(blessed refaddr weaken);

has name => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has fillIn => (
    is => 'ro',
    isa => 'Time::Span',
    required => 1,
);

with 'Time::Structure::Chain';

has version => (
    is => 'rw',
    isa => 'Int',
    default => do { my $i; sub { ++$i } },
    lazy => 1,
    clearer => '_update_version',
);

has ['+start', '+end'] => (
    init_arg => 'fillIn'
);

has ['from_earliest', 'until_latest'] => (
    is => 'rw',
    isa => 'Time::Point',
    coerce => 1,
    trigger => sub {
        my $self = shift;
        if ( $self->find_span_covering(shift) ) {
            croak "Time track limits can be extended, not narrowed";
        }
        $self->_update_version;
    }
);

has successor => (
    is => 'ro',
    isa => 'Time::Track',
    trigger => sub {
        my ($self, $succ) = @_;
        $succ->mustnt_start_later($self->end->until_date->successor);
        $self->_update_version;
    }
);

has default_inherit_mode => (
    is      => 'rw',
    isa     => 'Str',
    default => 'optional',
);

has force_receive_mode => (
    is => 'rw',
    isa => 'Maybe[Str]',
);

has _parents => (
    is => 'ro',
    isa => 'ArrayRef[Time::Track]',
    init_arg => 'unmentioned_variations_from',
    default => sub { [] },
);

has _children => (
    is => 'ro',
    init_arg => undef,
    default => sub { [] },
);

has _variations => (
    is => 'ro',
    isa => 'ArrayRef[HashRef]',
    init_arg => 'variations',
    default => sub { [] },
    traits => [ 'Array' ],
    handles => { add_variations => 'push' },
);

around BUILDARGS => sub {
    my ($orig, $class) = (shift, shift);

    if ( @_ == 2 ? ref($_[1]) eq 'HASH' : @_ % 2 ) {
        my $day_of_month = (localtime)[3];
        my $fillIn = Time::Span->new(
            week_pattern => shift,
            from_date => $day_of_month,  # do really no matter; both time points
            until_date => $day_of_month, # are adjusted dynamically
        );
        my %opts = @_ == 1 ? %{+shift} : @_;
        return $class->$orig({ %opts, fillIn => $fillIn });
    }
 
    else {
        return $class->$orig(@_);
    }

};

sub BUILD {
    my $self = shift;

    for my $p (@{ $self->_parents }) {
        my $children = $p->_children;
        push @$children, $self;
        weaken $children->[-1];
    } 

    $self->apply_variations;

}

sub calc_slices {
    my ($self, $from, $until) = @_;
    $from = $from->run_from if $from->isa("Time::Cursor");

    return $self->find_span_covering($self->start, $from)
               ->calc_slices($from, $until);
}

around couple => sub {
    my ($wrapped, $self, $span, $truncate_if_off) = @_;

    my $last = $span->get_last_in_chain;
    my $sts = $self->from_earliest // $span->from_date;
    my $ets = $self->until_latest // $last->until_date;
    if ( $truncate_if_off ) {
        return if $span->from_date > $ets || $sts > $last->until_date;
        if ( $span->from_date < $sts->epoch_sec ) {
            until ( $span->covers_ts($sts) ) { $span = $span->next; }
            $span->from_date($sts);
        }
        if ( $ets->last_sec < $last->until_date ) {
            $last = $span;
            until ( $last->covers_ts($ets) ) { $last = $last->next; }
            $last->until_date($ets);
            $last->nonext;
        }
    }
    else {
        my $fail = !defined $truncate_if_off;
        ($fail ? croak "Span hits track coverage limits" : return)
            if $span->from_date < $sts->epoch_sec
            || $ets->last_sec < $last->until_date
            ;
    }
            
    $self->$wrapped($span);

    $self->_update_version;
    return 1;

};

sub get_section {
    my ($self, $props) = @_;

    my ( $from, $until ) = map { ref $_ or $_ = Time::Point->parse_ts($_) }
                               delete @{$props}{ 'from_date', 'until_date' }
                         ;

    $from->fix_order($until)
        or croak 'from and until arguments in wrong order';

    $self->mustnt_start_later($from);
    $self->mustnt_end_sooner($until);

    $props //= {};

    my $from_span = $self->find_span_covering($from);
    my $until_span = $self->find_span_covering($from_span, $until);

    if ( $from_span == $until_span ) {
        return $from_span->new_shared_rhythm($from, $until, $props);
    }

    my $start_span = $from_span->new_shared_rhythm($from, undef);

    my ($last_span, $cur_span) = ($start_span, $from_span->next);
    until ( $cur_span && $cur_span == $until_span ) {
        my $next_span = $cur_span->new_shared_rhythm(undef, undef, $props);
        $last_span->next( $next_span );
        $cur_span = $cur_span->next;
    }
    
    if ( $cur_span ) {
        my $tail = $cur_span->new_shared_rhythm(undef, $until, $props );
        $last_span->next($tail);
    }

    return $start_span;

}

sub dump {
    my ($self,$index,$length) = @_;
    my $span = $self->start;
    if ( defined $index ) {
        croak 'negative indices not supported' if $index < 0;
        $length //= 1;
    }
    else {
        $length //= -1;
    }
    1 while $index-- and $span = $span->next;
    my @dumps;
    while ( $length-- && $span ) {
        my $rhythm = $span->rhythm;
        push @dumps, {
            description => $span->description,
            from_date   => $span->from_date.q{},
            until_date  => $span->until_date.q{},
            rhythm      => {
                 patternId      => refaddr($rhythm->pattern),
                 description    => $rhythm->description,
                 from_week_day  => $rhythm->from_week_day,
                 until_week_day => $rhythm->until_week_day,
                 mins_per_unit  => 60 / $rhythm->hourdiv,
                 atomic_enum    => $rhythm->atoms->to_Enum,
            },
        };
    }
    continue {
        $span = $span->next;
    }
    return @dumps;
}

sub reset {
    my ($self) = @_;
    my $fillIn = $self->fillIn;
    $fillIn->nonext;
    $self->_set_start($fillIn);
    $self->_set_end($fillIn);
}

sub mustnt_start_later {
    my ($self, $tp) = @_;

    my $start = $self->start;

    return if $start->from_date <= $tp;

    croak "Can't start before minimal from_date"
        if $self->from_earliest && $tp < $self->from_earliest;

    $start = $start->alter_coverage($tp, undef, $self->fillIn);

    $self->_set_start($start);

}

sub mustnt_end_sooner { # recursive on successor if any
    my ($self, $tp, $extender) = @_;

    my $end = $self->end;
    my $successor = $self->successor;

    my $until_latest = $self->until_latest;
    
    return if ( !$until_latest || $end->until_date == $until_latest )
           && $tp <= $end->until_date;
        ;

    my $tp1 = $tp;
    if ( $until_latest && $tp > $until_latest ) {
        croak "Can't end after maximal until_date" . (
            $successor ? " (could do with a passed extender sub reference)"
                       : q{}
        ) if !($successor && $extender);
        $extender->($until_latest, $successor);
        $tp1 = $until_latest;
    }
    
    my $end_span = $end->alter_coverage( undef, $tp1, $self->fillIn );
    $self->_set_end($end_span);

    if ( $successor ) {
        $successor->mustnt_end_sooner($tp, $extender);
    }

    return;
}

around until_latest => sub {
    my ($wrapped, $self) = (shift, shift);

    return $self->$wrapped(@_) // do {
        if ( my $successor = $self->successor ) {
            my $from_earliest = $successor->from_earliest
                // croak "Cannot succeed at unknown point in time";
            $from_earliest->predecessor;
        }
        else { () }
    };

};

sub _populate {
    my ($properties, $var) = @_;
    while ( my ($key, $value) = each %$properties ) {
        next if exists $var->{$key};
        $var->{$key} = $value;
    }
}

sub _register_variations_in {
    my ($self, $variations, $ancestry) = @_;

    my $track_name = $self->name;

    if ( defined $ancestry ) {
        push @$ancestry, $track_name;
    }
    else { $ancestry = [ $track_name ]; }

    for my $p (@{ $self->_parents }) {
        $p->_register_variations_in( $variations, $ancestry );
        pop @$ancestry;
    }

    my %seen;
    my $cnt = keys %$variations;

    VARIATION:
    for my $var ( map { {%$_} } @{ $self->_variations } ) {
        my ($name, $ref) = delete @{$var}{'name', 'ref'};

        $var->{ "_for_$track_name" } = delete $var->{apply} // 1;
        $var->{ "_pos" }             = $cnt++; # increment after assignment

        if ( $name and my $props = $variations->{$name} ) {

            # Keep variation untouched unless it is inherited from ancestry
            if ( !$props->{ _inherited_by }{ $track_name } ) {
                carp "Variation $name left untouched: "
                   . "originates from a sibling's ancestry";
                next VARIATION;
            }
            elsif ( $props->{inherit_mode} eq 'block' ) {
                carp "Variation $name has been blocked from inheritance. "
                   . "If you need, reuse it by 'ref' attribute";
                next VARIATION;
            }

            # When reusing a name, we must accept the rhythm
            # of the original variation
            for my $key (qw(week_pattern ref section_from)) {
                next if !defined $var->{$key};
                croak "'$key' property present"
                    . "but name '$name' used in upper levels"
                    ;
            }

            _populate( $props => $var );
            
        }

        elsif ( defined $ref ) {

            if ( blessed($ref) && $ref->isa("Time::Track") ) {
                $var->{base} = $ref->fillIn;
            }
            else {

                my $properties = $variations->{$ref}
                    // croak "Track $track_name, variation $name: ",
                        ref $ref
                            ? "'ref' is $ref, i.e. neither a variation "
                              . "name nor a reference to another track"
                            : "No base variation with name '$ref' registered"
                            ;

                for my $key (qw( week_pattern section_from )) {
                    next if !defined $var->{$key};
                    croak "$name: $key property present "
                        . "but bases on $ref"
                        ;
                }

                _populate( $properties => $var );

                $var->{base} = delete $var->{_span_obj};

            }
        }

        elsif ( my $p = delete $var->{week_pattern} ) {
            my $span = Time::Span->new(
                %$var,
                week_pattern => $p,
                track => $self
            );
            $var->{ _span_obj } = $span;
        }

        elsif ( !$var->{base} ) {
            $var->{base} = $self->fillIn;
        }

        $var->{ inherit_mode  }
            //= defined $name ? $self->default_inherit_mode : 'optional';

        $var->{ _inherited_by } //= { map { $_ => 1 } @$ancestry };

        $name        //= "_unnamed_" . refaddr $var;
        $seen{ $name } = 1;

        $variations->{ $name } = $var;
    }

    return \%seen;

}

sub apply_variations {
    my ($self) = @_;

    my (%levels, %variations);
    my @ORDER = qw( bottom suggest middle impose top );
    
    if ( $self->start->next ) { $self->reset; }

    my $seen = $self->_register_variations_in( \%variations );

    my $force_inh = $self->force_receive_mode;
    for my $key ( @ORDER ) { $levels{ $key } = [] }

    VARIATION:
    while ( my ($name, $properties) = each %variations ) {

        my $level;

        if ( $seen->{ $name } ) {

            my $apply = delete $properties->{ "_for_" . $self->name };

            next VARIATION if !$apply || lc $apply eq 'ignore';

            $level = $levels{ $apply eq 1           ? 'middle'
                            : lc $apply eq 'bottom' ? 'bottom'
                            : lc $apply eq 'top'    ? 'top'
                            :     croak "apply = $apply"
                     } // die $apply
                     ;
        }

        else {

            my $inh = $properties->{ inherit_mode };
            next VARIATION if lc $inh eq 'block';
            $inh = $force_inh // $inh;
            next VARIATION if lc $inh eq 'optional';
            $level = $levels{ lc $inh eq 'suggest' ? 'suggest'
                            : lc $inh eq 'impose'  ? 'impose'
                            : croak "unsupported inherit_mode = $inh"
                     } // die $inh
                     ;

        }

        delete $properties->{ inherit_mode };
        push @$level, $properties;

    }

    my @arranged_variations
        = map { sort { $a->{_pos} <=> $b->{_pos} } @$_ } @levels{ @ORDER };

    my @ATTRIBUTES = qw(from_date until_date description);

    for my $span ( @arranged_variations ) {

        my ($name, $base, $track, $obj)
            = delete @{$span}{qw( name base section_from _span_obj )};

        my $attr = {
            map({
                exists $span->{$_} ? ($_ => delete $span->{$_}) : ()
            } @ATTRIBUTES),
            track => $self
        };

        if ( my @unprocessed = grep { !/^_/ } keys %$span ) {
            croak "Unprocessed attributes for variation '$name': "
                . join q{, }, @unprocessed
                ;
        }

        $span = $base  ? $base->new_alike( $attr )
              : $track ? $track->get_section( $attr )
              : $obj   // croak "Not enough data to make span $name"
        ;

        $self->couple( $span, 1 );

    }
    
}

sub edit_variations {
    my ($self, @variations) = shift;

    for my $new_var ( @variations ) {
        
        my $found;
        my $variations = $self->_variations;

        for my $old_var ( $new_var->{name} ? @$variations : () ) {
            next if $old_var->{name} ne $new_var->{name};
            _populate($old_var => $new_var);
            $old_var = $new_var;
            $found = 1;
        }

        if ( !$found ) {
            push @$variations, $new_var;
        }

    }

    for my $desc ( values %{ $self->gather_family } ) {
        $desc->apply_variations;
    }
}

sub gather_family {
    my ($self, $desc) = @_;
    $desc //= {};
    $desc->{ $self->name } = $self;
    for my $child ( @{ $self->_children } ) {
        $child->gather_family( $desc );
    }
    return $desc;
}

sub timestamp_of_nth_net_second_since {
    my ($self, $net_seconds, $ts, $early_pass) = @_;
    
    # Argument validation
    croak 'The number of net seconds (argument #1) is undefined'
        if !defined $net_seconds;
    croak 'Missing timestamp from when to count (argument #2)'
        if !( ref($ts) ? blessed($ts) && $ts->isa('Time::Point') : $ts );

    # If correspondent Time::Cursor method has called us: Get extended data
    my ($next_stage, $signal_slice, $last_sec) = do {
        if ( $early_pass and my $p = $early_pass->() ) {
            my $slice = $p->pass_after_slice;
            $p, $slice, $slice->position + $slice->length;
        }
        else { undef, undef, undef; }
    };

    # Pass through to all slices up to a) where next stage says so
    # or b) all net seconds are found or c) our spans are exhausted.
    my $span = $self->start; 
    my $pos = { remaining_pres => -($net_seconds||1) };
    my $lspan;
    my $epts = ref $ts ? $ts->epoch_sec : $ts;
    while ( $pos->{remaining_pres} < 0 && $span ) {         # b), c)
        if ( $last_sec && $span->covers_ts($last_sec) ) {   # a)
            $signal_slice->calc_pos_data( $epts, $pos );
            return $next_stage->track->timestamp_of_nth_net_second_since(
                abs $pos->{remaining_pres}, $next_stage->from_date, $early_pass
            );
        }
        else {
            $span->slice->calc_pos_data( $epts, $pos );
        }
    }
    continue {
        $lspan = $span;
        $span  = $span->next;
    }

    my ($rem_abs, $rem_pres) = @{ $pos }{qw{ remaining_abs remaining_pres }};
    if ( $rem_pres < 0 ) {
        # There still are net seconds remaining so we must gather them
        # in our base rhythm, respecting however any until_latest setting ...

        my $find_pres_sec = abs $rem_pres;
        my $seek_from_ts = $lspan->until_date->successor;
        my $successor = $self->successor;
        my $rhythm = $self->fillIn->rhythm;
        my $coverage = $successor && (
            $self->until_latest->last_sec - $seek_from_ts->epoch_sec
        );

        my ($found_pres_seconds, $plus_rem_abs)
          = $rhythm->net_seconds_per_week
            ? $rhythm->count_absence_between_net_seconds(
                $seek_from_ts, $find_pres_sec,
                $coverage && ($coverage - $find_pres_sec)
              )
            : 0
            ;

        $rem_abs += $plus_rem_abs;

        if ( my $remaining = $find_pres_sec - $found_pres_seconds ) {
            die "no successor to gather $remaining seconds" if !$successor;
            die "remaining seconds negative" if $remaining < 0;
            my $start_ts = $self->until_latest->successor;
            return $successor->timestamp_of_nth_net_second_since(
                $remaining, $start_ts
            );
        }

    }

    elsif ( $rem_pres ) {
       # If we have gone to far, we will have to go back
       $rem_abs -= $lspan->slice->absence_in_presence_tail($rem_pres);
    }

    else {}

    return Time::Point->from_epoch(
        $ts->epoch_sec + $net_seconds + $rem_abs, 
    );
}

__PACKAGE__->meta->make_immutable;

1;
