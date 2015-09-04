#!perl
use strict;

package FTM::Time::Track;
use Moose;
use FTM::Time::Span;
use Carp qw(carp croak);
use Scalar::Util qw(blessed refaddr weaken);

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
    is => 'rw',
    isa => 'FTM::Time::Span',
    required => 1,
    trigger => sub {
        my ($self, $new, $old) = @_;
        croak "You cannot change fillIn rhythm for used track"
            if $old && $self->is_used;
    },
);

has _lock_time => (
    is => 'rw',
    isa => 'FTM::Time::Spec',
    predicate => 'is_used',
    handles => { 'modifiable_after_ts' => 'get_qm_timestamp' },
);

with 'FTM::Time::Structure::Chain';

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
    isa => 'FTM::Time::Spec',
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
    is => 'rw',
    isa => 'FTM::Time::Track',
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
    is => 'rw',
    isa => 'ArrayRef[FTM::Time::Track]',
    init_arg => 'unmentioned_variations_from',
    default => sub { [] },
    trigger => sub {
        my ($self, $new_value, $old_value) = @_;
        if ( $old_value ) {
            for my $p (@$old_value) {
                $p->_drop_child($self);
            }
        }
        for my $p (@$new_value) {
            $p->_add_child($self);
        }
    }, 
    auto_deref => 1,
);

has _children => (
    is => 'bare',
    init_arg => undef,
    default => sub { {} },
);

has _ref_parent => (
    is => 'rw',
    isa => 'FTM::Time::Track',
    init_arg => 'ref',
    trigger => sub {
        my ($self, $new_value, $old_value) = @_;
        if ( my $p = $old_value ) {
            $p->_drop_ref_child($self);
        }
        $new_value->_add_ref_child($self);
        return if !$old_value;
        $self->fillIn( $new_value->fillIn->new_alike );
        $self->apply_variations;
    }, 
);

has _ref_children => (
    is => 'bare',
    init_arg => undef,
    default => sub { {} },
);

sub _children {
    my ($self, $ref) = @_;
    my $children = $ref ? $self->{_ref_children} : $self->{_children};
    wantarray ? values %$children : [ values %$children ];
}
sub _add_child {
    my ($self, $child, $ref) = @_;
    my $children = $ref ? $self->{_ref_children} : $self->{_children};
    for my $c ( $children->{ $child->name } ) { $c = $child; weaken $c; }
    $child->clear_inherited_variations if !$ref;
}
sub _drop_child {
    my ($self, $child, $ref) = @_;
    my $children = $ref ? $self->{_ref_children} : $self->{_children};
    delete $children->{$child->name};
    $child->clear_inherited_variations if !$ref;
}
sub _ref_children { _children(shift, 1) }
sub _add_ref_child { _add_child(shift, shift, 1) }
sub _drop_ref_child { _drop_child(shift, shift, 1) }


has _variations => (
    is => 'ro',
    init_arg => undef,
    default => sub { [] },
);

has inherited_variations => (
    isa => 'HashRef',
    lazy_build => 1,
    init_arg => undef,
    clearer => 'clear_inherited_variations',
);

around BUILDARGS => sub {
    my ($orig, $class) = (shift, shift);

    my $args = $class->$orig(@_);

    for my $fillIn ( $args->{fillIn} ) {
        if ( $fillIn ) {
            my $superfluous = join ( " and ", grep { exists $args->{$_} }
                                  qw/week_pattern ref/
                              );
            carp "fillIn passed, but $superfluous too - will be ignored"
               if $superfluous;
        }
        my $day_of_month = (localtime)[3];
        $fillIn //= FTM::Time::Span->new(
            week_pattern => delete $args->{week_pattern} // do {
                my $ref = delete $args->{ref};
                croak "Neither week_pattern nor ref defined" if !$ref;
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

    if ( my $v = $args->{variations} ) {
        $self->_edit_variations($v);
    }

    $self->apply_variations;

}

sub calc_slices {
    my ($self, $from, $until) = @_;
    if ( !$self->is_used || $until > $self->_lock_time ) {
        $self->_lock_time($until);
    }
    $from = $from->run_from if $from->isa("FTM::Time::Cursor");

    return $self->find_span_covering($self->start, $from)
               ->calc_slices($from, $until);
}

around couple => sub {
    my ($wrapped, $self, $span, $opts) = @_;
    $opts //= {};

    if ( $self->is_used ) {
       my $ref_time = $self->_lock_time;
       $ref_time = FTM::Time::Spec->now if $ref_time->is_future;
       if ( !$opts->{ _may_modify_past } && $span->from_date <= $ref_time ) {
           croak "Span cannot begin within the used coverage of the track ",
               sprintf("(%s <= %s)", $span->from_date, $ref_time);
       }
    }

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
        my $fail = !defined $opts->{trimmable};
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

    my ( $from, $until ) = map { ref $_ or $_ = FTM::Time::Spec->parse_ts($_) }
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
    my ($self) = @_;

    my $successor = $self->successor;
    my $ref_parent = $self->_ref_parent;

    my %hash = (

        @{$self->_parents} ? (unmentioned_variations_from => [
            map { $_->name } $self->_parents
        ]) : (),

        (map {
            my $value = $self->$_();
            $value ? ($_ => $value) : ()
         } qw(
            name label default_inherit_mode force_receive_mode
            from_earliest until_latest
        )),

        $successor ? (successor => $successor->name) : (),

        $ref_parent ? ( ref => $ref_parent->name )
                    : ( week_pattern => $self->fillIn->rhythm->description )
                    ,

    );

    my @variations = @{ $self->_variations };
    for my $var ( @variations ) {
        $var->_clear_modify_past;
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
           && $tp->last_sec <= $end->until_date;
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
        my ($name, $ref, $ref_track)
            = delete @{$var}{'name', 'ref', 'week_pattern_of_track'};

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
            my @must_be_empty = grep { defined }
                @{$var}{'week_pattern','section_from_track'}, $ref_track
                ;
            croak "Reuse of a variation name ($name), but the rhythm is"
                . "overwritten by an attribute" if @must_be_empty;

            _populate( $props => $var );
            
        }

        elsif ( defined $ref_track ) {
            croak 'ref and week_pattern_of_track defined at the same time'
                if defined $ref;
            $var->{base} = $ref_track->fillIn;
        }

        elsif ( defined $ref ) {

            my $properties = $variations->{$ref}
                // croak "Track $track_name, variation $name: ",
                    ref $ref
                        ? "'ref' is $ref, i.e. neither a variation "
                          . "name nor a reference to another track"
                        : "No base variation with name '$ref' registered"
                        ;

            for my $key (qw( week_pattern section_from_track )) {
                next if !defined $var->{$key};
                croak "$name: $key property present "
                    . "but bases on $ref"
                    ;
            }

            _populate( $properties => $var );

            $var->{base} = delete $var->{_span_obj};

        }

        elsif ( my $p = delete $var->{week_pattern} ) {
            my $span = FTM::Time::Span->new(
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
            = delete @{$span}{qw( name base section_from_track _span_obj )};

        my $_may_modify_past = $span->may_modify_past;

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

        $self->couple( $span, {
            trimmable => 1,
            _may_modify_past => $_may_modify_past,
        });

    }
    
}

sub update {
    my ($self, $args) = @_;

    my ($base, $week_pattern) = delete @{$args}{'ref','week_pattern'};
    if ( $base ) {
        $self->fillIn( $base->fillIn->new_alike );
        $self->_ref_parent($base);
    }
    elsif ( $week_pattern ) {
        my $old_fillIn = $self->fillIn;
        my $from_date = $old_fillIn->from_date;
        my $until_date = $old_fillIn->until_date;
        $self->fillIn(
            FTM::Time::Span->new(
                week_pattern => $week_pattern,
                from_date => $from_date,
                until_date => $until_date,
            )
        );
    }
    if ( my $variations = delete $args->{variations} ) {

        if ( !defined $variations->[0] ) { shift @$variations; }
        else { $self->{_variations} = []; }

        $self->_edit_variations(@$variations);

    }
    elsif ( $base || $week_pattern ) {
        $self->apply_variations;
    }

    if ( my $p = delete $args->{unmentioned_variations_from} ) {
        $self->_parents($p);
    }
    while ( my ($attr,$value) = each %$args ) {
        $self->$attr($value);
    }

}

sub _edit_variations {
    my ($self, @variations) = @_;

    my $inh_vars = $self->_inherited_variations;

    for my $new_var ( @variations ) {
        
        my $found;
        my $variations = $self->_variations;

        for my $old_var ( $new_var->{name} ? @$variations : () ) {
            if ( $old_var->name eq $new_var->{name} ) {
                if ( my $new_inh_ref = delete $new_var->{ref} ) {
                    $old_var->ref($inh_vars->{$new_inh_ref});
                }
                $old_var->change( $new_var );
                $found = 1;
                last;
            }
            else {
                $old_var->may_modify_past(1);
            }
            
        }

        if ( !$found ) {
            push @$variations, FTM::Time::Track::Variation->new($new_var);
        }

    }

    for my $desc ( values %{ $self->gather_family } ) {
        @$_ = sort { $a->cmp_position_to($b) } @$_ for $self->_variations;
        $desc->apply_variations;
    }
}

around 'inherited_variations' => sub {
    my ($orig, $self) = @_;

    my $inh = $self->$orig();

    if ( wantarray ) {
        my $max = 0;
        for ( values %$inh ) {
            my $seqno = $_->seqno;
            $max = $seqno if $seqno > $max;
        }
        return $max, %$inh;       
    }
    else { return $inh; }

};

sub _build_inherited_variations {
    my ($self) = @_;

    my %variations;
    my ($next_incr, $incr) = (0, 0);
    for my $p ( $self->_parents ) {
        while ( my ($name, $var) = each %{ $self->all_variations } ) {
            ...
        }
    }
    
}

sub all_variations {
    my ($self) = @_;

    my ($i, %variations) = $self->inherited_variations;

    for my $v ( $self->_variations ) {
        $v->seqno(++$i);
        $variations{ $v->name } = $v;
    }

    return %variations;

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
    if ( my $p = $self ? $self->_parents : $data->{$parents_key} ) {
        for my $p (
            ref $p ? @$p : $self ? $p : $data->{$parents_key}
        ) {
            push @{$is_required{$p}}, \$p;
        }
    }

    for my $r ( $self ? $self->_ref_parent // () : $data->{ref} // () ) {
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
        @{ $self ? $self->_variations : $data->{variations} }
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
            # TO FIX error: after storing data to a task that has been previously
            # given multiple time-track segments, cursor cannot fully restore here? 
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

    return FTM::Time::Spec->from_epoch(
        $ts->epoch_sec + $net_seconds + $rem_abs, 
    );
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Time::Track - (irr-)Regularly interchanging working- and off-time periods

=head1 SYNOPSIS

=head1 DESCRIPTION

A time track has a week_pattern to cover a arbitrary time span, whatever the cursors demand, but not beyond the limits indicated by from_earliest and until_latest, if provided.

Beside their basic week pattern, tracks can include variations with different patterns, restricted to a specified coverage in time (from_date/until_date).

Caution: FTM::Time::Track instances can be linked to each other via several axes. It is very easy to make circular constructions. FTM::Time::Model has means some in place to detect that and warn the user.

=head1 COPYRIGHT

(C) 2012-2014 Florian Hess

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

