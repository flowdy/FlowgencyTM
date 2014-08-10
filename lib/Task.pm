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
    clearer => 'clear_progress',
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
                   my ($key) = keys %$args;
                   ($args) = values %$args;
                   $key;
               }
             : # or with { (step => $name), %further_data }:
               delete $args->{step} // ''
             ; 

    $args->{oldname} = $root;

    my $steps = delete $args->{steps} // {};
    my $steps_rs = $self->dbicrow->steps_rs;
    my $root_step
        = $root && ($steps_rs->find($root) // croak qq{No step '$root'})
        ;

    # As we want to be able to mention known steps in {substeps}
    # without declaring them manually in {steps} hash ...
    $steps->{ $_->name } //= {}
        for $root ? $root_step->and_below({}, { columns => ['name'] })
                  : $steps_rs->search(    {}, { columns => ['name'] })
        ;

    if ( $root_step ) {
        for my $parent ( $root_step->ancestors_upto() ) {
            $steps->{ $root_step->name } = {
                _skip => "because it is above our hierarchy",
                 row => $root_step, parent => $parent->name,
            };
        }
        continue { $root_step = $parent; }
    }

    my $steps_aref; # list all upper steps before their lower levels
    if ( my $s = delete $args->{substeps} ) {
        $steps_aref = _ordered_step_hrefs( $root, $s, %$steps );
    }
    else {
        $steps_aref = [];
    }

    $self->dbicrow->result_source->storage->txn_do( sub {
        $self->_store_root_step($args);
        $steps_rs = $self->dbicrow->steps_rs; # update resultset
        _store_steps_below($root, $steps_rs, $steps_aref);
    });

    my @to_recalc;
    while ( my ($step, $args) = each %$steps ) {
        next if !grep { defined($_) }
             @{$args}{qw{ done checks expoftime_share }};
        push @to_recalc, $args->{name} // $step;
    }
    $DB::single=1;
    $self->tasks->recalculate_dependencies($self => @to_recalc);

    return 1;

}

sub _ordered_step_hrefs {
    my ($root_name, $top_sequence, %steps) = @_;

    my %dependencies;      # %seen with parent names as values:
                           # Used to prevent circular references that
                           # would certainly cause endless loops

    my $ROOTID = '#ROOT#'; # External module doesn't support zero-length keys
    $dependencies{$ROOTID} = [];

    my $sequencer = sub {
        my ($parent_name, $sequence) = @_;

        my ($defined_pos, $undefined_pos) = split m{\s*;\s*}x, $sequence, 2;
        my  @defined_pos                  = split m{   ,\s*}x, $defined_pos;
        my $order_num;

        for ( $undefined_pos, @defined_pos ) {
            next if !defined;
            my @cluster = split m{ \s* [|/] \s* }xms;
            my $order_plus = 0;

            for my $step_name ( @cluster ) {
                    
                if ( my $dep = $dependencies{$step_name} ) {
                    croak qq{Step $step_name can't have parent $parent_name }
                        . qq{since it is subordinated to $dep->[0]}
                }

                my $step = $steps{$step_name}
                    // croak qq{No step "$step_name" defined or found} . (
                           $root_name && qq{ below "$root_name"}
                    );

                $step->{parent} = $parent_name;
                $step->{pos}    = $order_num && ( $order_num + $order_plus );
                
                $dependencies{$step_name} = [
                    length($parent_name) ? $parent_name : $ROOTID
                ];

            }
            continue {
                $order_plus += 1 / @cluster;
            }

        }
        continue {
            $order_num++;
        }
        
    }; # end of $sequencer definition

    $sequencer->($root_name => $top_sequence);

    while ( my ($step,$md) = each %steps ) {
        $md->{oldname} = $step;
        $sequencer->( $step => $md->{substeps} // next );
    }

    my $ado = Algorithm::Dependency::Ordered->new(
        source => Algorithm::Dependency::Source::HoA->new(\%dependencies)
    );

    my $ordered_steps = $ado->schedule_all
        // die "ADO failed to resolve order of steps"
        ;

    if ( $ordered_steps->[0] eq $ROOTID ) {
        shift @$ordered_steps;
        delete $steps{''};
    }
    for my $step ( @$ordered_steps ) {
        $step = delete $steps{$step};
    }

    if ( my @orphans = keys %steps ) {
        croak "Some steps of which the data provided in {steps}"
            ." are not hooked in any {substeps} order chain: "
            . join q{, }, @orphans
        ;
    }
    
    return $ordered_steps;

}

sub _store_root_step {
    my ($self, $data) = @_;
    my $row = $self->dbicrow;
    my $steps_rs = $row->steps;
    my $root_name = delete $data->{oldname};

    if ( length $root_name ) {
        my $step_row = $steps_rs->find($root_name);
        $data->{name} //= $root_name;
        my $p = $data->{parent};
        croak "Not found: parent for step '$root_name' with name $p"
            if $p && !$steps_rs->find($p);
        if ($step_row) { $row = $step_row; }
        elsif ( $p && exists $data->{pos} ) {
            $row = $steps_rs->new($data);
        }
        else {
            croak "New step must have a parent and a position"
        }
    }
    else {
        croak "root step cannot have a parent"
            if defined $data->{parent};
        while ( my ($key, $value) = each %$data ) {
            $row->$key($value);
        }
    }

    my $result;

    if ( $row->in_storage ) {
        $result = $row->update;
        $self->redraw_cursor_way;
    }
    else {
        $result = $row->insert;
        for my $ts ( @{ $data->{timestages} } ) {
            $row->add_to_timestages($ts);
        } 
        croak "Cursor setup failed: $@" if !eval { $self->_cursor };
    }
}

sub _store_steps_below {
    my ($root_name, $steps_rs, $steps_aref) = @_;
    
    my %rows_tmp;
    while ( @$steps_aref ) {
        last if !$steps_aref->[0]{_skip};
        my ($name,$step) = @{ shift @$steps_aref }{'oldname','row'};
        $rows_tmp{$name} = $step;
    }

    my %in_hierarchy;
    for my $step ( @$steps_aref ) {
        my $name = $step->{oldname};
        my $substeps = delete($step->{substeps}) // next;
        next if !defined $step->{parent}; # avoid breaks in hierarchy chain
        my %substeps = map { $_ => 1 } split /[,;|\/\s]+/, $substeps;
        croak qq{$root_name can't be substep of $name }
            . q{(circular dependency)}
            if $substeps{$root_name};
        $in_hierarchy{ $step->{oldname} } = \%substeps;
    }

    # Why not fuse the for-loops to one pass?
    #   Because we do not know if steps not in the parent/substeps
    #   dependency graph come always last in @$steps_aref.
    for my $step ( @$steps_aref ) {

        my $name = delete $step->{oldname};
        $step->{name} //= $name;
        my $step_row;

        if ( %$step ) {
            my $p = delete $step->{parent}
                // die "Substep $name missing its parent"
            ;
            my $p_row = length $p ? $rows_tmp{$p}
                      :             $steps_rs->find({ name => '' })
                      ;

            if ( $step_row = $steps_rs->find({ name => $name }) ) {

                # Check if there are circular dependencies
                if ( $in_hierarchy{$name} ) {
                    # Algorithm::Dependency::Ordered cared already
                }
                else { # step $name has no explicit substeps

                    my (undef, @descendents) = $step_row->and_below(
                        {}, { -columns => ['name'] }
                    );

                    for my $d ( map { $_->name } @descendents ) {
                        next if !$rows_tmp{$d};
                        my $line = join "/", $d->ancestors_upto($name);
                        $line = $line ? "descendent (via $line)" : "substep";
                        croak qq{Circular dependency detected: $d can't be }
                            . qq{$line and ancestor at the same time}
                            ;
                    }
                
                }
    
                $step->{parent_row} = $p_row;
                $step_row->update($step);

            }

            else { 
                croak "Didn't cache parent $p for step $name"
                    if !defined $p_row;
                $rows_tmp{ $name } = $step_row
                    = $p_row->add_to_substeps($step);
            }

        }

        else {
            # Even neither {parent} nor {pos} exist, so forget all substeps
            # unmentioned in the hierarchy given that DBIx::Class will delete
            # their descendents (cascade_delete => 1 set if not implied).
            $step_row = $steps_rs->find({ name => $name });
            my $ar = $step_row;
            my $inhier;
            while ( $ar = $ar->parent_row ) {
                next if !($inhier = $in_hierarchy{ $ar->name });
                $inhier->{$step} or $step_row->delete;
                last;
            }
            continue {
                $step = $ar->name;
            }
            
        }

        is_link_valid($step_row) if defined $step_row->link;

    }

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
