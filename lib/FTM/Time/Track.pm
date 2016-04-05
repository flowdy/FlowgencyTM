#!perl
use strict;

package FTM::Time::Track;
use Moose;
use FTM::Time::Span;
use FTM::Time::Variation;
use FTM::Error;
use Carp qw(croak);
use Scalar::Util qw(blessed refaddr weaken);
use List::MoreUtils qw(first_index);

has name => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has label => (
    is => 'rw',
    isa => 'Str',
);

has fillIn => (
    is => 'ro',
    isa => 'FTM::Time::Span',
    required => 1,
    writer => '_fillIn',
    trigger => sub {
        my ($self, $new, $old) = @_;
        for my $c ( values %{ $self->{_ref_children} } ) {
            next if !$c->[1];
            $c->[0]->_fillIn($new);
        }
        continue { $c->reset; }
        $self->reset;
    },
);

has lock_from_date => (
    is => 'ro',
    isa => 'FTM::Time::Spec',
    handles => { 'modifiable_before_ts' => 'get_qm_timestamp' },
);
sub _set_lock_from_earlier {
    my ($self, $new_ts, $cur_ts) = ( @_[0,1], \$_[0]->{lock_from_date} );
    return if $$cur_ts && $$cur_ts <= $new_ts;
    for ( $self->parents ) { $_->_set_lock_from_earlier($new_ts) }
    $$cur_ts = $new_ts;
}

has lock_until_date => (
    is => 'ro',
    isa => 'FTM::Time::Spec',
    predicate => 'is_used',
    handles => { 'modifiable_after_ts' => 'get_qm_timestamp' },
);
sub _set_lock_until_later {
    my ($self, $new_ts, $cur_ts) = ( @_[0,1], \$_[0]->{lock_until_date} );
    return if $$cur_ts && $new_ts <= $$cur_ts;
    for ( $self->parents ) { $_->_set_lock_until_later($new_ts) }
    $$cur_ts = $new_ts;
}

with 'FTM::Time::Structure::Chain';

has version => (
    is => 'rw',
    isa => 'Int',
    default => do { my $i; sub { ++$i } },
    lazy => 1,
    clearer => '_update_version',
);

has '+start' => (
    required => 0,
    predicate => 'variations_rendered',
    init_arg => undef,
);

before start => sub {
    &variations_rendered or &_apply_variations;
};


has '+end' => (
    init_arg => 'fillIn',   
);

for ( ['from_earliest', 'until_latest'] ) {
    has $_ => (
        is => 'rw',
        isa => 'FTM::Time::Spec',
        coerce => 1,
        trigger => \&_update_version,
    );
    before $_ => sub {
        my $self = shift;
        my $ts = @_ && $self->is_used ? shift : return;
        $ts = ref($ts) eq 'ARRAY' ? FTM::Time::Spec->from(@$ts)
            : !ref($ts)           ? FTM::Time::Spec->parse_ts($ts)
            : $ts
            ;
        FTM::Error::Time::InvalidTrackData->throw(
            "Time track limits can be extended, not narrowed"
        ) if $ts > $self->lock_from_date
          && $self->lock_until_date > $ts
        ;
    };
}

has successor => (
    is => 'rw',
    isa => 'FTM::Time::Track',
    trigger => \&_update_version,
    weak_ref => 1,
);
before successor => sub {
    my ($self, $succ) = @_;
    return if !$succ;
    if ( my $until_date = $self->{until_latest} ) {
        $succ->mustnt_start_later($until_date->successor);
    }
    elsif ( my $from_date = $succ->from_earliest ) {
        my ($self_name, $succ_name) = ($self->name, $succ->name);
        FTM::Error::Time::InvalidTrackData->throw(
            "It is too late for Track $succ_name to succeed $self_name: "
        ) if $self->is_used && $from_date < $self->lock_until_date;
    }
    else {
        FTM::Error::Time::InvalidTrackData->throw(
            "Cannot succeed at unknown point in time"
        );        
    }
    $self->{successor} = $succ;
};

has default_inherit_mode => (
    is      => 'rw',
    isa     => 'Str',
    default => 'optional',
    trigger => \&clear_inherited_variations,
);

has force_receive_mode => (
    is => 'rw',
    isa => 'Maybe[Str]',
    trigger => \&reset,
);


has parents => (
    is => 'rw',
    isa => 'ArrayRef[FTM::Time::Track]',
    init_arg => 'unmentioned_variations_from',
    default => sub { [] },
    trigger => sub {
        my ($self, $new_value, $old_value) = @_;
        if ( $old_value ) {
            for my $p (@$old_value) { $p->_drop_child($self); }
        }
        for my $p (@$new_value) { $p->_add_child($self); }
        $self->clear_inherited_variations;
    }, 
    auto_deref => 1,
);

has _children => (
    is => 'bare',
    init_arg => undef,
    default => sub { {} },
);

has ref => (
    is => 'rw',
    isa => 'FTM::Time::Track',
    trigger => sub {
        my ($self, $new_value, $old_value) = @_;
        if ( my $p = $old_value ) {
            $p->_drop_ref_child($self);
        }
        $new_value->_add_ref_child($self);
        return if !$old_value; # why? - s. BUILDARGS
        $self->fillIn( $new_value->fillIn->new_alike );
        $self->reset;
    }, 
);

has _ref_children => (
    is => 'bare',
    init_arg => undef,
    default => sub { {} },
);

sub _children {
    my $self = shift;
    my $children = $self->{_children};
    wantarray ? values %$children : [ values %$children ];
}
sub _add_child {
    my ($self, $child, $ref) = @_;
    my $children = $ref ? $self->{_ref_children} : $self->{_children};
    for my $c ( $children->{ $child->name } ) { $c = $child; weaken $c; }
    $child->clear_inherited_variations;
}
sub _drop_child {
    my ($self, $child) = @_;
    delete $self->{_children}{ $child->name };
    $child->clear_inherited_variations;
}

sub _ref_children {
    my $self = shift;
    my @children = map { $_->[0] } values %{$self->{_ref_children}};
    wantarray ? @children : \@children;
}
sub _add_ref_child {
    my ($self, $other) = @_;
    my $var = do {
        if ( $other->isa("FTM::Time::Variation") ) {
            my $obj = $other;
            $other = $other->track;
            $obj;
        }
        else { undef }
    };

    my $aref = $self->{_ref_children}{ $other->name }
           //= do { my $ar = [ $other, 0 ]; weaken $ar->[0]; $ar }
             ;

    if ( $var ) {
        push @$aref, $var;
        weaken $aref->[ -1 ];
    }
    else {
        $aref->[1] = 1;
    }

}
sub _drop_ref_child {
    my ($self, $other) = @_;
    my $var = do {
        if ( $other->isa("FTM::Time::Variation") ) {
            my $obj = $other;
            $other = ($other)->track;
            $obj;
        }
        else { undef };
    };

    my $cref = $self->{_ref_children};
    my $aref = $cref->{ ($other)->name } // return;

    if ( $var ) {
        for my $i ( 2 .. @$aref-1 ) {
            next if $var == $aref->[$i];
            splice @$aref, $i, 1;
            last;
        }
    }
    else {
        $aref->[1] = 0;
    }

    if ( !$aref->[1] && @$aref < 3 ) {
        delete $cref->{ $other->name };
    }

}
    
has variations => (
    is => 'ro',
    isa => 'ArrayRef',
    init_arg => undef,
    default => sub { [] },
    auto_deref => 1,
);

has inherited_variations => (
    is => 'ro',
    isa => 'HashRef',
    lazy_build => 1,
    init_arg => undef,
    clearer => 'clear_inherited_variations',
    auto_deref => 1,
);

after clear_inherited_variations => sub {
    my ($self) = @_;
    for ( $self->_children ) {
        $_->clear_inherited_variations
    }
    $self->reset;
};


around BUILDARGS => sub {
    my ($orig, $class) = (shift, shift);

    my $args = $class->$orig(@_);

    my @content = grep { exists $args->{$_} } qw/week_pattern ref/;
    my $superfluous = join " and ", @content;
    FTM::Error::Time::InvalidTrackData->throw(
        "Both $superfluous passed which is ambiguous"
    ) if @content > 1;
    for my $fillIn ( $args->{fillIn} ) {
        FTM::Error::Time::InvalidTrackData->throw(
            "fillIn passed, but $superfluous too"
        ) if $fillIn && @content;
        my $day_of_month = (localtime)[3];
        $fillIn //= FTM::Time::Span->new(
            week_pattern => delete $args->{week_pattern} // do {
                my $ref = delete $args->{ref};
                FTM::Error::Time::InvalidTrackData->throw(
                    "Neither week_pattern nor ref defined"
                ) if !$ref;
                $ref->fillIn->rhythm;
            },
            from_date => $day_of_month,  # do really no matter; both time points
            until_date => $day_of_month, # are adjusted dynamically
        );
    }

    return $args;

};

sub BUILD {
    my ($self, $args) = @_;
    if ( my $vars = $args->{variations} ) {
        $self->update_variations($vars);
    }
    $self->fillIn->track($self);
    return;
}

sub calc_slices {
    my ($self, $from, $until) = @_;

    $self->_set_lock_from_earlier($from);
    $self->_set_lock_until_later($until);

    $from = $from->run_from if $from->isa("FTM::Time::Cursor");

    my $start_span = $self->find_span_covering($self->start, $from);

    FTM::Error::Time::Gap->throw(
        "No span found that covers timestamp $from"
    ) if !$start_span;

    return $start_span->calc_slices($from, $until);

}

around couple => sub {
    my ($wrapped, $self, $span, $opts) = @_;
    $opts //= {};

    my $last = $span->get_last_in_chain;
    my $sts = $self->from_earliest // $span->from_date;
    my $ets = $self->until_latest // $last->until_date;
    if ( $opts->{ trimmable } ) {
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
        if ( $span->from_date < $sts->epoch_sec
          || $ets->last_sec < $last->until_date
        ) {
            if ( defined $opts->{trimmable} ) { return }
            else {
                FTM::Error::Time::InvalidTrackData->throw(
                    "Span hits track coverage limits"
                );
            }
        }
    }
            
    $span->track($self);

    $self->$wrapped($span);

    if ( caller ne __PACKAGE__ ) {
        # we assume reset() has not been called
        $self->_update_version;
    }

    return 1;

};

sub get_section {
    my ($self, $props) = @_;

    my ( $from, $until ) = map { ref $_ or $_ = FTM::Time::Spec->parse_ts($_) }
                               delete @{$props}{ 'from_date', 'until_date' }
                         ;

    $from->fix_order($until)
        or FTM::Error::Time::InvalidSpec->throw(
           'from and until arguments in wrong order'
        );

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
    my ($self) = @_;

    my $successor = $self->successor;
    my $ref = $self->ref;
    my $p = $self->parents;

    my %hash = (

        @$p ? (unmentioned_variations_from => [ map { $_->name } @$p ] )
            : (),

        (map {
            my $value = $self->$_();
            $value ? ($_ => $value) : ()
         } qw(
            name label default_inherit_mode force_receive_mode
            from_earliest until_latest
        )),

        $successor ? (successor => $successor->name) : (),

        $ref ? ( ref => $ref->name )
             : ( week_pattern => $self->fillIn->rhythm->description )
             ,

    );

    my @variations = @{ $self->variations };
    for my $var ( @variations ) {
        $var = $var->dump();
    }
    $hash{variations} = \@variations if @variations;

    return \%hash;
}

sub dump_spans {
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
    $self->fillIn->nonext;
    delete @{$self}{'start', 'end'};
    $self->_update_version;
}

sub mustnt_start_later {
    my ($self, $tp) = @_;

    my $start = $self->start;

    return if $start->from_date <= $tp;

    FTM::Error::Time::Gap->throw(
        "Can't start before from_earliest of ". $self->name
    ) if $self->from_earliest && $tp < $self->from_earliest;

    $start = $start->alter_coverage($tp, undef, $self->fillIn);

    $self->_set_start($start);

}

sub mustnt_end_sooner { # recursive on successor if any
    my ($self, $tp, $extender) = @_;

    my $end = $self->end;
    my $successor = $self->successor;

    my $until_latest = $self->until_latest;
    
    return if ( !$until_latest || $end->until_date == $until_latest )
           && $tp->last_sec <= $end->until_date;
        ;

    my $tp1 = $tp;
    if ( $until_latest && $tp > $until_latest ) {
        FTM::Error::Time::Gap->throw(
            "Can't end after maximal until_date" . (
                $successor ? " (could do with a passed extender sub reference)"
                           : q{}
            )
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
                // FTM::Error::Time::Gap->throw(
                       "Cannot succeed at unknown point in time"
                   );
            $from_earliest->predecessor;
        }
        else { () }
    };

};

sub _apply_variations {
    my $self = shift;

    my $variations = $self->all_variations;
    my @ORDER = qw( bottom suggest middle impose top );
    my $force_inh = $self->force_receive_mode;

    my %levels = map { $_ => [] } @ORDER;

    VARIATION:
    for my $var ( values %$variations ) {

        my $level;

        if ( defined(my $apply = $var->apply) ) {

            next VARIATION if !$apply || lc $apply eq 'ignore';

            $level = $levels{ $apply eq 1           ? 'middle'
                            : lc $apply eq 'bottom' ? 'bottom'
                            : lc $apply eq 'top'    ? 'top'
                            :     croak "apply = $apply"
                            }
                         ;

        }

        else {

            my $inh = $var->inherit_mode;
            next VARIATION if lc $inh eq 'block';
            $inh = $force_inh // $inh;
            next VARIATION if lc $inh eq 'optional';
            $level = $levels{ lc $inh eq 'suggest' ? 'suggest'
                            : lc $inh eq 'impose'  ? 'impose'
                            : croak "unsupported inherit_mode = $inh"
                     } // die $inh
                     ;

        }

        push @$level, $var;

    }

    $self->_set_start($self->fillIn);
    
    $self->couple( $_->span, { trimmable => 1 })
        for map {
              sort { $a->seqno <=> $b->seqno } @$_
            } @levels{ @ORDER }
    ;

}

sub update {
    my ($self, $args) = @_;

    my $week_pattern = delete $args->{week_pattern};
    if ( $self->is_used && ( $args->{ref} || $week_pattern ) ) {
        FTM::Error::Time::HasPast->throw(
            "You cannot change fillIn rhythm of a used track"
        );
    }
    elsif ( $args->{ref} && $week_pattern ) {
        FTM::Error::Time::InvalidTrackData->throw(
            "Both ref and week_pattern passed which is ambiguous"
        );
    }
    elsif ( $week_pattern ) {
        my $old_fillIn = $self->fillIn;
        my $from_date = $old_fillIn->from_date;
        my $until_date = $old_fillIn->until_date;
        $self->_fillIn( FTM::Time::Span->new(
            week_pattern => $week_pattern, track => $self,
            from_date => $from_date, until_date => $until_date,
        ));
    }

    if ( my $variations = delete $args->{variations} ) {
        $self->update_variations($variations);
    }

    while ( my ($attr,$value) = each %$args ) {
        $self->$attr($value);
    }

}

sub unlock {
    my $self = shift;
    delete @{$self}{'lock_from_date','lock_until_date'};
    $self->reset;
}

sub update_variations {
    my ($self, $variations) = @_;
    my $stored_variations = $self->variations;

    if ( @$variations && !defined $variations->[0] ) {
        $stored_variations = [];
        shift @$variations;
    }
    
    my $inh_vars = $self->inherited_variations;

    my $count_inh_vars = keys %$inh_vars;

    VARIATION:
    for my $new_var ( @$variations ) {
        
        $new_var->{track}   = $self;
        $new_var->{apply} //= 1;

        my $i = 0;
        for my $old_var ( $new_var->{name} ? @$stored_variations : () ) {
            next if $old_var->name ne $new_var->{name};
            for ( $new_var->{ref} // () ) {
                $_ = $inh_vars->{$_}
                    // FTM::Error::Time::InvalidTrackData->throw(
                           "No variation '$_' found"
                    );
            }
            $new_var = $old_var->new_alike( $new_var );
            $new_var->ensure_coverage_is_alterable;
            splice @$stored_variations, $i, 1;
            next VARIATION;
        }
        continue { $i++; }

        my $old_obj = $new_var->{name} && delete $inh_vars->{ $new_var->{name} };

        if ( defined $old_obj ) {
            $new_var = $old_obj->new_alike($new_var);
        }
        else {
            my $new_obj = FTM::Time::Variation->new_alike( $new_var );
            $new_obj->ensure_coverage_is_alterable;
            $new_var = $new_obj;
        }
                
    }

    $self->reset;
    my @to_sort_anew;

    my %family = %{ $self->gather_family };
    delete $family{ $self->name };
    for ( values %family ) {
        $_->clear_inherited_variations;
        my $vars = $_->variations;
        push @to_sort_anew, $vars; 
    }

    for ( $variations ) {
        unshift @$_, @$stored_variations;
        push @to_sort_anew, $_; 
    }

    for my $vars ( @to_sort_anew ) {
        @$vars = sort { $a->cmp_position_to($b) } @$vars;
    }

    for ( @$variations ) {
        $_->seqno( ++$count_inh_vars );
    }

    $self->{variations} = $variations;

    return;
}

sub _build_inherited_variations {
    my ($self) = @_;
    my %variations;
    my ($next_incr, $incr) = (0, 0);
    for my $p ( $self->parents ) {
        my $all_variations = $p->all_variations;
        while ( my ($name, $var) = each %$all_variations ) {
            $var = $var->meta->clone_object($var, apply => undef);
            my $seqno = $var->seqno;
            $next_incr = $seqno if $seqno > $next_incr;
            $var->seqno( $incr + $seqno );
            $variations{$name} = $var;
        }
        
    }
    continue {
        $incr += $next_incr;
        $next_incr = 0;
    }

    for my $v ( $self->variations ) {
        $v->seqno( ++$incr );
    }

    return \%variations;
    
}

sub all_variations {
    my ($self) = @_;
    my %variations = $self->inherited_variations;

    for my $v ( $self->variations ) {
        $variations{ $v->name } = $v;
    }

    return \%variations;

}

sub gather_dependencies {
    my ($class, $data, $dependencies) = @_;

    my $self;                   # This method can be invoked with the class
    if ( ref $class ) {         # or with an instance of the class.
        $self = $class;
        $dependencies = $data;
    }

    my %is_required; # keys:   $id_of_required_track
                     # values: \@scalar_refs_to_be_filled_with_track_oref

    # Prior to track $id being constructed, all its parents must be ready
    my $parents_key = 'unmentioned_variations_from';
    if ( my $p = $self ? $self->parents : $data->{$parents_key} ) {
        push @{ $is_required{$_} }, \$_ for @{
            ref $p ? $p : do {
                # normalize to array ref: (in-place modification!)
                $_ = [ split /\W\s*/ ] for $data->{$parents_key};
                $data->{ $parents_key }
            }
        };
    }

    for my $r ( $self ? $self->ref // () : $data->{ref} // () ) {
        push @{$is_required{$r}}, \$r;
    }

    # ... and its successor, if any
    if ( my $succ = $self ? $self->successor : $data->{successor} ) {
        $is_required{ $self ? $succ->name : $succ } = [
            $self ? \$succ : \$data->{successor}
        ];
    }

    # ... to not forget its variations which are sections of another track
    for my $var (
        @{ ($self ? $self->variations : $data->{variations}) // [] }
    ) {
        defined $var or next;
        my $s;
        if ( $s = $var->{section_from_track} ) {
            $s = $s->name if $self;
            push @{$is_required{$s}}, \$var->{section_from_track};
        }
        elsif ( $s = $var->{week_pattern_of_track} ) {
            $s = $s->name if $self;
            push @{$is_required{$s}}, \$var->{week_pattern_of_track};
        }
    }

    if ( $self ) {
        for my $track ( values %is_required ) {
            ${$track->[0]}->gather_dependencies($dependencies);
        }
        $dependencies->{ $self->name } = [ keys %is_required ];
    }

    return \%is_required;

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
    croak 'The number of net seconds may not be negative'
        if $net_seconds < 0;
    croak 'Missing timestamp from when to count (argument #2)'
        if !( ref($ts) ? blessed($ts) && $ts->isa('FTM::Time::Spec') : $ts );

    # If correspondent FTM::Time::Cursor method has called us: Get extended data
    my ($next_stage, $signal_slice, $last_sec) = do {
        if ( $early_pass and my $p = $early_pass->() ) {
            my $slice = $p->pass_after_slice;
            $p, $slice, $slice->position + $slice->length - 1;
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
            : (0, 0)
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

    return FTM::Time::Spec->from_epoch(
        $ts->epoch_sec + $net_seconds + $rem_abs, 
    );
}

sub DEMOLISH {
    my $self = shift;

    if ( $self and my $p = $self->ref ) {
        $p->_drop_ref_child($self);
    }

}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Time::Track - Regularly and irregularly interchanging working- versus off-time periods

=head1 SYNOPSIS

=head1 DESCRIPTION

A time track has a week_pattern to cover a arbitrary time span, whatever the cursors demand, but not beyond the limits indicated by from_earliest and until_latest, if provided.

Beside their basic week pattern, tracks can include variations with different patterns, restricted to a specified coverage in time (from_date/until_date).

Caution: FTM::Time::Track instances can be linked to each other via several axes. It is very easy to make circular constructions. FTM::Time::Model has some means in place to detect that and warn the user.

=head1 COPYRIGHT

(C) 2012-2015 Florian Hess

=head1 LICENSE

This file is part of FlowgencyTM.

FlowgencyTM is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowgencyTM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowgencyTM. If not, see <http://www.gnu.org/licenses/>.

