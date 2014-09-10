use strict;

package Task;
use 5.014;
use Moose;
use Algorithm::Dependency::Ordered;
use Algorithm::Dependency::Source::HoA;
use FlowDB::Task;

has _cursor => (
    is => 'ro',
    isa => 'Time::Cursor',
    required => 1,
    lazy => 1,
    builder => '_build_cursor',
    handles => {
        update_cursor           => 'update',
        probe_time_stages       => 'apply_stages',
        timestamp_at_net_second => 'timestamp_of_nth_net_second_since',
        map { $_ => $_ } qw(start_ts due_ts),
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
        main_step_row steps
    ]],
    required => 1,
    default => sub { # called after clearer has been called
        my $self = shift;
        $self->_tasks->tasks_rs->find({ name => $self->name });
    },
    clearer => 'release_row',
);


has progress => (
    is => 'ro',
    isa => 'Num',
    lazy => 1,
    default => sub { shift->main_step_row->calc_progress },
    clearer => 'clear_progress',
    init_arg => undef,
);

has _tasks => ( 
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
    FtError::Task::FailsToLoad->throw("Task record has no associated timestages") if !@ts;
    my $cursor = Time::Cursor->new({
        start_ts   => $row->from_date,
        timestages => [ $self->_tasks->bind_tracks(@ts) ],
    });
    return $cursor;
}

around priority => sub {
    my ($orig, $self) = (shift,shift);
    my $number = $self->$orig();
    return $self->_tasks->priority_resolver->( "p:$number" ) // $number;
};

sub current_focus {
    return shift->main_step_row->current_focus(@_);
}

sub redraw_cursor_way {
    my ($self, @stages) = @_;
    my $row = $self->dbicrow;
    my $cursor = $self->_cursor;

    if ( ref $stages[0] eq 'HASH' ) {
        $cursor->apply_stages( $self->_tasks->bind_tracks(@stages) );
        $row->timestages(
            map { $_->{track} = $_->{track}->id }
                $cursor->timeway_to_stage_hrefs
        );
    }

    elsif ( !@stages || (ref $stages[0] eq 'ARRAY' && @stages == 1) ) {
        my $list = shift @stages // [];
        my @stages = $self->_tasks->bind_tracks($row->timestages(@$list));
        $stages[0]{from_date} = ( $row->from_date );
        $cursor->change_way(@stages);
    }

    else { die }

    # Needed?: return wantarray ? $cursor->update : ();

}

sub store {
    my $self = shift;
    my %args = @_ % 2 ? %{ shift @_ } : @_;

    # Get name of upmost step to be stored 
    my $root = keys(%args) == 1
             ? do { # store() callable with { $step_name => \%data }:
                   my ($key, $value) = each %args;
                   %args = %$value;
                   $key;
               }
             : # or with { (step => $name), %further_data }:
               delete $args{step} // ''
             ; 

    $args{oldname} = $root;

    my $steps = delete $args{steps} // {};
    my $steps_rs = $self->dbicrow->steps_rs;
    my $root_step = $root && (
        $steps_rs->find({ name => $root })
            // FtError::Task::InvalidDataToStore->throw(qq{No step '$root'})
    );

    # As we want to be able to mention known steps in {substeps}
    # without declaring them manually in {steps} hash ...
    $steps->{ $_->name } //= {}
        for $root ? $root_step->and_below({}, { columns => ['name', 'ROWID', 'task' ] })
                  : $steps_rs->search(    {}, { columns => ['name'] })
        ;

    if ( $root_step ) {
        my $step = $root_step;
        for my $parent ( $step->ancestors_upto() ) {
            $steps->{ $step->name } = {
                _skip => "because it is above our hierarchy",
                 row => $step, parent => $parent->name,
            };
        }
        continue { $step = $parent; }
    }

    my $steps_aref; # list all upper steps before their lower levels
    if ( my $s = delete $args{substeps} ) {
        $steps_aref = _ordered_step_hrefs( $root, $s, %$steps );
    }
    else {
        $steps_aref = [];
    }

    $self->dbicrow->result_source->storage->txn_do( sub {
        $self->_store_root_step(\%args);
        $steps_rs = $self->dbicrow->steps_rs; # update resultset
        $self->_store_steps_below($root, $steps_rs, $steps_aref);
    });

    my @to_recalc;
    while ( my ($step, $args) = each %$steps ) {
        my @relevant = @{$args}{qw{ done checks expoftime_share }};
        next if !grep { defined($_) } @relevant;
        push @to_recalc, $args->{name} // $step;
    }

    $self->_tasks->recalculate_dependencies($self => @to_recalc);
    $self->clear_progress;

    return 1;

}

sub _ordered_step_hrefs {
    my ($root_name, $top_sequence, %steps) = @_;

    # Let's protect incoming data from our changes
    $_ = { %$_ } for values %steps;

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
                    FtError::Task::InvalidDataToStore->throw(
                        qq{Step $step_name can't have parent $parent_name }
                      . qq{since it is subordinated to $dep->[0]}
                    );
                }

                my $step = $steps{$step_name}
                    // FtError::Task::InvalidDataToStore->throw(
                           qq{No step "$step_name" defined or found} . (
                               $root_name && qq{ below "$root_name"}
                           )
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
        FtError::Task::InvalidDataToStore->throw(
             "Some steps of which the data provided in {steps}"
            ." are not hooked in any {substeps} order chain: "
            . join q{, }, @orphans
        );
    }
    
    return $ordered_steps;

}

sub _store_root_step {
    my ($self, $data) = @_;
    my $row = $self->dbicrow;
    my $steps_rs = $row->steps;
    my $root_name = delete $data->{oldname};

    my $store_mode = length($root_name) ? 'step' : 'task';

    if ( $store_mode eq 'step' ) {

        my $step_row = $steps_rs->find({ name => $root_name });
        $data->{name} //= $root_name;

        my $p = $data->{parent};
        FtError::Task::InvalidDataToStore->throw(
            "Not found: parent for step '$root_name' with name $p"
        ) if $p && !$steps_rs->find({ name => $p });

        if ($step_row) { $row = $step_row; }

        elsif ( $p && exists $data->{pos} ) {
            $row = $steps_rs->new_result();
        }

        else {
            FtError::Task::InvalidDataToStore->throw(
                "New step must have a parent and a position"
            );
        }

        $self->_handle_subtask_data_of( $data );

        if ( my $l = delete $data->{link} ) {
            $self->_tasks->link_step_row( $row => $l );
        }
        
    }
    else {
        FtError::Task::InvalidDataToStore->throw(
            "root step cannot have a parent"
        ) if defined $data->{parent};
        $self->_normalize_task_data($data => $row);
    }

    while ( my ($key, $value) = each %$data ) {
        $row->$key($value);
    }

    my $result;

    if ( $row->in_storage ) {
        $self->redraw_cursor_way if $store_mode eq 'task'
                                 || $data->{subtask_row};
        $result = $row->update;
    }
    else {
        $result = $row->insert;
        FtError::Task::InvalidDataToStore->throw(
            "Cursor setup failed: $@"
        ) if !eval { $self->_cursor };
    }

    # to avoid any inconsistencies, notice any defaults, etc.
    $row->discard_changes();

    return $result;
}

sub _store_steps_below {
    my ($self, $root_name, $steps_rs, $steps_aref) = @_;
    
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
        $step->{is_parent} = 1 if $substeps =~ /\w/;
        next if !defined $step->{parent}; # avoid breaks in hierarchy chain
        my %substeps = map { $_ => 1 } split /[,;|\/\s]+/, $substeps;
        FtError::Task::InvalidDataToStore->throw(
           qq{$root_name can't be substep of $name }
            . q{(circular dependency)}
        ) if $substeps{$root_name};
        $in_hierarchy{ $step->{oldname} } = \%substeps;
    }

    # Why not fuse the for-loops to one pass?
    #   Because we do not know if steps missing in the parent/substeps
    #   dependency graph come always last in @$steps_aref.
    for my $step ( @$steps_aref ) {

        die q{Oops, did not expect "_skip"ped steps here:}, $step->{oldname}
            if $step->{_skip};

        my $name = delete $step->{oldname};
        $step->{name} //= $name;

        my $step_row  = $steps_rs->find({ name => $name });

        if ( %$step ) {
            my ($parent, $is_parent, $link)
                = delete @{$step}{ 'parent', 'is_parent', 'link' };
            die "Substep $name is missing its parent" if !defined $parent;

            my $p_row = length $parent
                      ? $rows_tmp{$parent}
                      : $steps_rs->find({ name => '' })
                      ;

            if ( $step_row ) {

                $self->_handle_subtask_data_of($step);

                # Check if there are circular dependencies
                if ( $in_hierarchy{$name} ) {
                    # Algorithm::Dependency::Ordered cared already
                }
                else { # step $name has no explicit substeps

                    my (undef, @descendents) = $step_row->and_below(
                        {}, { -columns => ['name','ROWID','task'] }
                    );

                    for my $d ( map { $_->name } @descendents ) {
                        next if !$rows_tmp{$d};
                        my $line = join "/", $d->ancestors_upto($name);
                        $line = $line ? "descendent (via $line)" : "substep";
                        FtError::Task::InvalidDataToStore->throw(
                            qq{Circular dependency detected: $d can't be }
                          . qq{$line and ancestor at the same time}
                        );
                    }
                
                }
    
                $step->{parent_row} = $p_row;
                $step_row->set_columns($step);

            }

            else { 
                FtError::Task::InvalidDataToStore->throw(
                    "Didn't cache parent $parent for step $name"
                ) if !defined $p_row;
                $rows_tmp{ $name } = $step_row
                    = $p_row->new_related(substeps => $step);
                
            }

            if ( defined $is_parent ) {
                $step_row->is_parent($is_parent);
            }

            if ( defined $link ) {
                $self->_tasks->link_step_row($step_row => $link);
            }

            $step_row->update_or_insert;

        }

        else {
            # Even neither {parent} nor {pos} exist, so forget all substeps
            # unmentioned in the hierarchy given that DBIx::Class will delete
            # their descendents (cascade_delete => 1 set if not implied).
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

    }

}

my %SUBTASK_EXT = map { $_ => 1 } FlowDB::Task->columns, 'timestages';
delete @SUBTASK_EXT{'name'};
sub _handle_subtask_data_of {
    my ($self, $step) = @_;
    my %subtask_row;
    for my $key ( grep { $SUBTASK_EXT{$_} } keys %$step ) {
        $subtask_row{$key} = delete $step->{$key};
    }
    $self->_normalize_task_data(\%subtask_row);
    if ( %subtask_row ) {
        $step->{subtask_row} = \%subtask_row;
    }
}

sub _normalize_task_data {
    my ($self, $data) = @_;

    for my $f ( $data->{from_date} // () ) {
        $f = q{}.( Time::Point->parse_ts($f)->fill_in_assumptions );
    }

    for my $p ( $data->{priority} // () ) {
        my $num = $self->_tasks->priority_resolver->("n:$p");
        if ( $num ) { $p = $num }
        elsif ( $p !~ m{ \A [1-9] [0-9]* \z }xms ) {
            FtError::Task::InvalidDataToStore->throw(
                "unknown priority label: $p"
            );
        }
    }

}

sub step { shift->steps->find({ name => shift }) }

__PACKAGE__->meta->make_immutable();

package FtError::Task::FailsToLoad;
use Moose;
extends 'FtError';

package FtError::Task::InvalidDataToStore;
use Moose;
extends 'FtError';

1;
