use strict;

package Task;
use 5.014;
use Moose;
use Carp qw(carp croak);
use Algorithm::Dependency::Ordered;
use Algorithm::Dependency::Source::HoA;

has _cursor => (
    is => 'ro',
    isa => 'Time::Cursor',
    required => 1,
    lazy => 1,
    builder => '_build_cursor',
    handles => {
        update_cursor           => 'update',
        probe_time_stages       => 'apply_stages',
    },
);

has name => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    default => sub { shift->dbicrow->name },
    init_arg => undef,
);

has dbicrow => (
    is => 'ro',
    isa => 'FlowDB::Task', # which again is a DBIx::Class::Row
    handles => [qw[
        from_date client open_sec
        title description priority
        main_step steps
    ]],
    required => 1,
    clearer => 'release_row',
);

has progress => (
    is => 'ro',
    isa => 'Num',
    lazy => 1,
    default => sub { shift->main_step->calc_progress },
    clearer => '_clear_progress',
    init_arg => undef,
);

has tasks => ( # sub bind_tracks, link_step_row
    is => 'ro',
    weak_ref => 1,
    isa => 'User::Tasks',
    required => 1,
);

sub _build_cursor {
    use Time::Cursor;
    my $self = shift;
    my $row = $self->dbicrow;
    my @ts = $row->timestages;
    croak "Task record has no associated timestages" if !@ts;
    my $cursor = Time::Cursor->new({
        start_ts   => $row->from_date,
        timestages => [ $self->tasks->bind_tracks(@ts) ],
    });
    return $cursor;
}

sub redraw_cursor_way {
    my ($self, @stages) = @_;
    my $row = $self->dbicrow;
    my $cursor = $self->_cursor;

    my $tasks = $self->tasks;

    if ( ref $stages[0] eq 'HASH' ) {
        $cursor->apply_stages( $tasks->bind_tracks(@stages) );
        $row->timestages(
            map { $_->{track} = $_->{track}->id }
                $cursor->timeway_to_stage_hrefs
        );
    }

    elsif ( !@stages || (ref $stages[0] eq 'ARRAY' && @stages == 1) ) {
        my $list = shift @stages // [];
        my @stages = $tasks->bind_tracks($row->timestages(@$list));
        $stages[0]{from_date} = ( $row->from_date );
        $cursor->change_way(@stages);
    }

    else { die }

    # Needed?: return wantarray ? $cursor->update : ();

}

sub store {
    my $self = shift;
    my $args = @_ % 2 ? shift : { @_ };

    # Get name of upmost step to be stored 
    my $root = keys(%$args) == 1
             ? do { # store() callable with { $step_name => \%data }:
                   my ($k) = keys %$args;
                   ($args) = values %$args;
                   $k;
               }
               # or with { (step => $name), %further_data }:
             : delete $args->{step} // ''; 

    $args->{oldname} = $root;

    # As we want to be able to mention known steps in {substeps}
    # without declaring them in {steps} hash ...
    my $new_steps = do {
        my $steps_href = delete $args->{steps} // {};
        my $steps_rs  = $self->dbicrow->steps_rs;
        my @search_args = ( {}, { columns => [qw/name/] } );
        $steps_href->{ $_->name } //= {}
            for $root ? $steps_rs->find($root)->and_below(@search_args)
                      : $steps_rs->search(@search_args)
                      ;
        $steps_href;
    };

    # We expect all upper steps before their lower levels
    my @steps;
    if ( my $s = delete $args->{substeps} ) {
        @steps = $self->_sequence_step_data_hrefs( $root, $new_steps, $s );
    }
    else {
        @steps = values %$new_steps;
    }

    $self->dbicrow->result_source->storage->txn_do(
        \&_store_write_to_db => $self, $args, @steps
    );

    my @to_recalc;
    while ( my ($step, $args) = each %$new_steps ) {
        next if !grep { defined($_) }
             @{$args}{qw{ done checks expoftime_share }};
        push @to_recalc, $step;
    }
    $self->tasks->recalculate_dependencies($self => @to_recalc);

    return 1;

}

sub _sequence_step_data_hrefs {
    my ($self, $parent_name, $steps_href, $top_sequence) = @_;

    my %dependencies;   # %seen with parent names as values:
    my %parent_of;      # Used to prevent circular references that
                        # would certainly cause endless loops

    my $sequencer = sub {
        my ($parent_name, $sequence) = @_;
        return [] if !length $sequence;

        my ($defined_pos, $undefined_pos) = split m{\s*;\s*}x, $sequence, 2;
        my  @defined_pos                  = split m{   ,\s*}x, $defined_pos;
        my ($order_num, @steps)           = ( undef, () );

        CLUSTER:
        for my $cl ( $undefined_pos, @defined_pos ) {

            next CLUSTER if !defined $cl;

            my @cluster = split m{ [|/] }xms, $cl;
            
            my $order_plus = 0;

            for my $step_name ( @cluster ) {
                my $step = $steps_href->{$step_name};
                my $order_num = $order_num && ( $order_num + $order_plus );
                croak qq{No step "$step_name" defined} if !$step;
                croak qq{Step already subordinated to $parent_of{$step}}
                    if $parent_of{$step_name};

                @{$step}{ 'parent', 'pos' } = ( $parent_name, $order_num );
                
                push @steps, $step_name;
   
                $parent_of{$step_name} = $parent_name;

            }
            continue {
                $order_plus += 1/@cluster;
            }
        }
        continue {
            $order_num++;
        }
        
        return \@steps;

    }; # end of $sequencer definition

    $parent_name = '#ROOT#' if !length $parent_name;
    $dependencies{$parent_name} = $sequencer->(q{} => $top_sequence);

    while ( my ($step,$md) = each $steps_href ) {
        $md->{oldname} = $step;
        $dependencies{$step} = $sequencer->($step => $md->{substeps});
    }

    my $dep_source
        = Algorithm::Dependency::Source::HoA->new(\%dependencies)
        ;
    my $resolved_order = Algorithm::Dependency::Ordered->new(
        source => $dep_source
    )->schedule_all // croak "ADO failed to resolve order of steps";

    my @ordered_steps = reverse @$resolved_order;

    if ( $ordered_steps[0] eq q{#ROOT#} ) {
        shift @ordered_steps;
        delete $steps_href->{''};
    }
    for my $step ( @ordered_steps ) {
        $step = delete $steps_href->{$step};
    }

    if ( my @orphans = keys %$steps_href ) {
        croak "Some steps of which the data provided in {steps}"
            ." are not hooked in any {substeps} order chain: "
            . join q{, }, @orphans
        ;
    }
    
    
    return @ordered_steps;

}

sub _store_write_to_db {
    my ($self, $root, @steps_upd_data) = @_;

    ########################################################
    ## 1. Save the data of the root step
    #####################################/
    my $row = $self->dbicrow;
    my $steps_rs = $row->steps;
    my %new_parents;
    my $name = delete $root->{oldname};

    if ( length $name ) {
        my $step_row = $steps_rs->find($name);
        $root->{name} //= $name;
        my $p = $root->{parent};
        croak "Not found: parent row for step '$name' with ID $p"
            if $p && !$steps_rs->find($p);
        if ($step_row) { $row = $step_row; }
        elsif ( $p && exists $root->{pos} ) {
            $row = $steps_rs->new({ name => $name });
        }
        else {
            croak "New step must have a parent and a position"
        }
    }
    else {
        croak "root step cannot have a parent"
            if $root->{parent};
        while ( my ($key, $value) = each %$root ) {
            $row->$key($value);
        }
    }

    my $result;

    if ( $row->in_storage ) {
        $result = $row->update;
        $self->redraw_cursor_way;
        $self->_clear_progress; 
            # to be recalculated on next progress() call
    }
    else {
        $result = $row->insert();
        for my $ts ( @{ $root->{timestages} } ) {
            $row->add_to_timestages($ts);
        }
        eval { $self->_cursor } or croak "Can't build cursor: $@";
    }

    ###########################################################
    ## 2. Save or remove the data of the steps below
    #################################################/
    my %in_hierarchy = map {
        my $substeps = delete $_->{substeps};
        $_->{oldname} => (defined $_->{parent} && defined $substeps);
    } @steps_upd_data;
    my %rows_cache;

    for my $step ( @steps_upd_data ) {
        my $name = delete $step->{oldname};
        $step->{name} //= $name;
        my $step_row;

        if ( %$step ) {
            my $p = delete $step->{parent};
            my $p_row = length $p ? $rows_cache{ $p }
                      :           $row->main_step_row;
            croak "Can't find parent row '$p' for step '$name'"
                if !$p_row;
            $rows_cache{ $name } = $step_row
                = $p_row->update_or_create_related(
                    substeps => $step
                );
        }

        else { # even neither {parent} nor {pos} exist 
            # Forget all substeps unmentioned in the hierarchy
            # given that DBIx::Class will delete their descendents
            # with cascade_delete => 1 set. Climb hierarchy up to
            # the first having {substeps} which doesn't contain
            # parent as it did once
            $step_row = $steps_rs->find({ name => $name });
            my $ar = $step_row;
            while ( $ar = $ar->parent_row ) {
                next if !$in_hierarchy{ $ar->name };
                $step_row->delete;
                last;
            }
            
        }

        is_link_valid($step_row) if defined $step_row->link;

    }

    return $result;
}

sub is_link_valid {
    my ($self) = @_;

    my $req_step = $self->link_row // return;

    croak "Steps may not be subtasks and links at the same time"
        if $self->subtask_row;

    croak "Can't have multiple levels of indirection/linkage"
        if $req_step->link;

    my %is_successor;
    $is_successor{ $_->name }++ for grep !$_->link, $self->and_below;
    my ($p,$ch) = ($self, $self);
    while ( $p = $p->parent_row ) {
        $is_successor{ $_->name }++ for $p->substeps->search({
            link => undef,
            pos => { '>=' => $ch->pos }
        }, { columns => ['name'] });
    } continue { $ch = $p; }

    my @conflicts = grep $is_successor{$_}, $req_step->prior_deps($self->name);
    if ( @conflicts ) {
        croak "Circular or dead-locking dependency in ",
            $self->dbicrow->name, " from ", $req_step->name, " to ",
            join ",", @conflicts;
    }

    return;         
}

1;
