use strict;

package FTM::Task;
use 5.014;
use Moose;
use FTM::FlowDB::Task;
use FTM::Util::DependencyResolver qw(ordered);
use Carp qw(croak);

has _cursor => (
    is => 'ro',
    isa => 'FTM::Time::Cursor',
    required => 1,
    lazy => 1,
    builder => '_build_cursor',
    handles => {
        update_cursor           => 'update',
        probe_time_stages       => 'apply_stages',
        timestamp_at_net_second => 'timestamp_of_nth_net_second_since',
        scan_cursor_between     => 'slicing_between',
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
    isa => 'FTM::FlowDB::Task', # which again is a DBIx::Class::Row
    handles => [
        qw( priority main_step_row steps )
    ],
    required => 1,
    default => sub { # called after clearer has been called
        my $self = shift;
        $self->_tasks->tasks_rs->find({ name => $self->name });
    },
    clearer => 'uncouple_dbicrow',
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
    isa => 'FTM::User::Tasks',
    required => 1,
);

has subtasks => (
    is => 'ro',
    isa => 'HashRef',
    init_arg => undef,
    lazy => 1,
    builder => '_init_subtasks',
);

has flowrank => (
    is => 'rw',
    isa => 'FlowRank::Score',

);

has is_open => (
    is => 'ro',
    isa => 'Maybe[Int]',
    init_arg => undef,
    lazy => 1,
    builder => '_when_put_on_desk'
);

sub _build_cursor {
    use FTM::Time::Cursor;

    my $self = shift;
    my $row = $self->dbicrow;
    my @ts = $row->timestages;

    FTM::Error::Task::FailsToLoad->throw(
        "FTM::Task record has no associated timestages"
    ) if !@ts;

    my $cursor = FTM::Time::Cursor->new({
        start_ts   => $row->from_date,
        timestages => [ $self->_tasks->bind_tracks(@ts) ],
    });

    return $cursor;

}

sub _init_subtasks {
    my ($self) = shift;

    my %subtasks = ( '' => $self );
    my (undef, @ordered_steps) = $self->main_step_row->and_below; 

    $self->_update_subtask_if_any($_, \%subtasks) for @ordered_steps;

    return \%subtasks;

}

sub _update_subtask_if_any {
    my ($self, $step, $subtasks_href) = @_;
    my $subtask_row = $step->subtask_row // return;
    $subtasks_href //= $self->subtasks; 

    require FTM::Task::SubTask;

    for my $subtask ( $subtasks_href->{ $step->name } ) {

        if ( defined $subtask ) {
            $subtask->redraw_cursor_way;
            $subtask->clear_progress;
        }

        else {

            my $p_row = $step;

            my $parent;

            UPPER:
            while ( $p_row = $p_row->parent_row ) {
                last UPPER if $parent = $subtasks_href->{ $p_row->name };
            }

            $subtask = FTM::Task::SubTask->new(
                task => $self, parent => $parent, dbicrow => $subtask_row
            );

            $subtask->_cursor;

        }
        
    }

    return;

}

sub _when_put_on_desk {
    my $self = shift;
    my $open_since_ts = $self->dbicrow->open_since;
    return if !$open_since_ts;
    $_ = FTM::Time::Point->parse_ts($_, $self->start_ts) for $open_since_ts;
    my %pos = $self->_cursor->update($open_since_ts);
    return $pos{elapsed_pres};
}

around is_open => sub {
    my ($orig, $self, $elapsed_pres) = @_;
    if ( !$elapsed_pres ) {
        return $self->$orig();
    }
    elsif ( defined(my $open_time = $self->$orig()) ) {
        return $elapsed_pres - $open_time;
    }
    else { return undef; }
};

sub is_archived {
    return defined shift->dbicrow->archived_ts;
}
sub open {
    my ($self) = @_;
    $self->store({ step => '', open_since => FTM::Time::Point->now });
    return;
}

sub close {
    my ($self) = @_;
    $self->store({ step => '', open_since => undef });
    return;
}   

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

    return;

}

sub store {
    my $self = shift;
    my %args = @_ == 1 ? %{ shift @_ } : @_;

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

    $args{_oldname} = $root;

    my $steps = delete $args{steps} // {};
    my $row = $self->dbicrow;
    my $steps_rs = $row->steps_rs;
    my $root_step = $root && (
        $steps_rs->find({ name => $root })
            // FTM::Error::Task::InvalidDataToStore->throw(qq{No step '$root'})
    );

    # As we want to be able to mention known steps in {substeps}
    # without declaring them manually in {steps} hash ...
    my @substep_hierarchy_fill = 
        $root ? $root_step->and_below({}, {
                    columns => ['name', 'step_id', 'task_id', 'parent_id']
                })
              : $steps_rs->search({}, {
                    columns => ['name', 'parent_id' ]
                })
              ;
    for my $step ( @substep_hierarchy_fill ) {
        my $name = $step->name;
        my $p;
        if ( $p = $step->parent_row ) { $p = $p->name }
        $steps->{ $name }->{_oldparent} = $p;
    }

    if ( $root_step ) {
        my ($step, @ancestors) = $root_step->ancestors_upto();
        for my $parent ( @ancestors ) {
            $steps->{ $step->name } = {
                _skip => "because it is above our hierarchy",
                 row => $step,
                 parent => $parent->name,
            };
        }
        continue { $step = $parent; }
    }
    $steps->{''} = {
        _skip => 'because it is always needed',
        row => $row,
    };

    if ( defined( my $substeps = delete $args{substeps} ) ) {
        my $step = $root_step ? $root_step->name : '';
        $steps->{$step}{substeps} = $substeps;
    }

    # list all upper steps before their lower levels
    my $steps_aref = _ordered_step_hrefs($root, %$steps);

    $self->dbicrow->result_source->storage->txn_do( sub {
        $self->_store_root_step(\%args);
        $self->_store_steps_below($root, $steps_aref);
        my @touched_timestructure;
        for my $step ( $root_step ? \%args : (), @$steps_aref ) {
            next if !grep { defined } @{$step}{'from_date','timestages'};
            push @touched_timestructure, $step->{name} // $step->{_oldname};
        }
        if ( @touched_timestructure ) {
            $self->check_timestructure(@touched_timestructure);
        }
        $self->archive_if_completed;
    });

    my (@to_recalc);
    while ( my ($step, $args) = each %$steps ) {
        my @relevant = @{$args}{qw{ done checks expoftime_share }};
        next if !grep { defined($_) } @relevant;
        push @to_recalc, $args->{name} // $step;
    }

    $self->_tasks->recalculate_dependencies($self => @to_recalc);
    $self->clear_progress;
    delete $self->{is_open};
    delete $steps->{$root_step};

    return 1;

}

sub _ordered_step_hrefs {
    my ($root_name, %steps) = @_;

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
        my @defined_pos                   = split m{,\s*}x, $defined_pos//q{};
        my $order_num;

        for ( $undefined_pos, @defined_pos ) {
            next if !length;
            my @cluster = split m{ \s* [|/] \s* }xms;
            my $order_plus = 0;

            for my $step_name ( @cluster ) {
                    
                if ( my $dep = $dependencies{$step_name} ) {
                    $dep = $dep->[0];
                    FTM::Error::Task::InvalidDataToStore->throw(
                        qq{Step $step_name can't have parent $parent_name }
                      . qq{since it is subordinated to $dep}
                    ) if defined $dep;
                }

                my $step = $steps{$step_name}
                    // FTM::Error::Task::InvalidDataToStore->throw(
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

    while ( my ($step,$md) = each %steps ) {
        $md->{_oldname} = $step;
        if ( defined( my $substeps = $md->{substeps} ) ) {
            $sequencer->( $step => $substeps );
        }
        else { next; }
    }

    while ( my ($step,$md) = each %steps ) {
        next if !length($step) || $dependencies{$step};
        my $p = $md->{_oldparent};
        $p = $ROOTID if !length $p;
        $dependencies{ $step } = [ $p ];
    }

    my $ordered_steps = ordered(\%dependencies);

    $_ = $_ eq $ROOTID ? '' : $_ for $ordered_steps->[0];

    #if ( $ordered_steps->[0] eq $ROOTID ) {
    #    shift @$ordered_steps;
    #    delete $steps{''};
    #}

    for my $step ( @$ordered_steps ) {
        $step = delete $steps{$step};
        delete $step->{_oldparent};
    }

    for my $orphan ( values %steps ) {
        if ( $orphan->{_skip} ) { unshift @$ordered_steps, $orphan; }
        else { push @$ordered_steps, $orphan; }
    }
    
    return $ordered_steps;

}

sub _store_root_step {
    my ($self, $data) = @_;
    my $row = $self->dbicrow;
    my $steps_rs = $row->steps;
    my $root_name = delete $data->{_oldname};

    my $store_mode = length($root_name) ? 'step' : 'task';

    if ( $store_mode eq 'step' ) {

        my $step_row = $steps_rs->find({ name => $root_name });
        $data->{name} //= $root_name;

        my $p = delete $data->{parent};
        FTM::Error::Task::InvalidDataToStore->throw(
            "Not found: parent for step '$root_name' with name $p"
        ) if $p && !($data->{parent_row} = $steps_rs->find({ name => $p }));

        if ($step_row) { $row = $step_row; }

        elsif ( $p && exists $data->{pos} ) {
            $row = $steps_rs->new_result();
        }

        else {
            FTM::Error::Task::InvalidDataToStore->throw(
                "New step must have a parent and a position"
            );
        }

        $self->_handle_subtask_data_of( $data );

        if ( my $l = delete $data->{link_id} ) {
            $self->_tasks->link_step_row( $row => $l );
        }
        
    }
    else {
        FTM::Error::Task::InvalidDataToStore->throw(
            "root step cannot have a parent"
        ) if defined $data->{parent};
        $self->_normalize_task_data($data => $row);
    }

    while ( my ($key, $value) = each %$data ) {
        $row->$key($value);
    }

    my $result;

    if ( $row->in_storage ) {
        $self->redraw_cursor_way if $store_mode eq 'task';
        $result = $row->update;
    }
    else {
        $result = $row->insert;
        FTM::Error::Task::InvalidDataToStore->throw(
            "Cursor setup failed: $@"
        ) if !eval { $self->_cursor };
    }

    if ( $store_mode eq 'step' ) {
        $self->_update_subtask_if_any($row);
    }
    
    # to avoid any inconsistencies, notice any defaults, etc.
    $row->discard_changes();

    return $result;
}

sub _store_steps_below {
    my ($self, $root_name, $steps_aref) = @_;
    my $steps_rs = $self->dbicrow->steps_rs; # update resultset

    my %in_hierarchy;
    for my $step ( @$steps_aref ) {
        my ($name, $row) = ($step->{_oldname}, $step->{row});
        my $substeps = delete $step->{substeps} // do {
            if ( $row ) { join q{,}, $row->substeps->get_column('name')->all }
            else { next; }
        };
        $step->{is_parent} = $substeps =~ /\w/ if defined($substeps);

        # avoid breaks in hierarchy chain:
        next if $name && !defined $step->{parent}; 

        my %substeps = map { length($_) ? ($_ => 1) : () }
            split /[,;|\/]\s*/, $substeps, -1;
        FTM::Error::Task::InvalidDataToStore->throw(
           qq{$root_name can't be substep of $name }
            . q{(circular dependency)}
        ) if !$row && $substeps{$root_name};
        $in_hierarchy{ $step->{_oldname} } = \%substeps;
    }

    my %rows_tmp;
    while ( @$steps_aref ) {
        last if !$steps_aref->[0]{_skip};
        my ($name,$step) = @{ shift @$steps_aref }{'_oldname','row'};
        $rows_tmp{$name} = $step;
    }

    for my $step ( @$steps_aref ) {

        die q{Oops, did not expect "_skip"ped steps here:}, $step->{_oldname}
            if $step->{_skip};

        my $name = delete $step->{_oldname};

        my $step_row  = $steps_rs->find({ name => $name });

        if ( %$step ) {
            $step->{name} //= $name;
            my ($parent, $is_parent, $link)
                = delete @{$step}{ 'parent', 'is_parent', 'link_id' };
            # Commented out that since steps hash can contain data to store
            # without there being hierarchical reorganisation:
            # die "Substep $name is missing its parent" if !defined $parent;

            my $p_row = length $parent  ? $rows_tmp{$parent}
                      : defined $parent ? $steps_rs->find({ name => '' })
                      : undef
                      ;

            if ( $step_row ) {

                $self->_handle_subtask_data_of($step);

                # Check if there are circular dependencies
                if ( $in_hierarchy{$name} ) {
                    # Algorithm::Dependency::Ordered cared already
                }
                else { # step $name has no explicit substeps

                    my (undef, @descendents) = $step_row->and_below(
                        {}, { -columns => ['name','step_id','task_id'] }
                    );

                    for my $d ( map { $_->name } @descendents ) {
                        next if !$rows_tmp{$d};
                        my $line = join "/", $d->ancestors_upto($name);
                        $line = $line ? "descendent (via $line)" : "substep";
                        FTM::Error::Task::InvalidDataToStore->throw(
                            qq{Circular dependency detected: $d can't be }
                          . qq{$line and ancestor at the same time}
                        );
                    }
                
                }
    
                $step_row->parent_row($p_row) if defined $p_row;
                $step_row->set_columns($step);
                $rows_tmp{$name} = $step_row;

            }

            elsif ( $p_row )  { 
                $step->{task_row} = $rows_tmp{''};
                $rows_tmp{$name} = $step_row
                    = $p_row->new_related(substeps => $step);
            }

            else {

                FTM::Error::Task::InvalidDataToStore->throw(
                    "step $name has no parent, i.e. is not included in a"
                   ."substeps chain of another step"
                ) if !defined $parent;

                FTM::Error::Task::InvalidDataToStore->throw(
                    "Didn't cache parent $parent for step $name"
                ) if !defined $p_row;
                
            }

            if ( defined $is_parent ) {
                $step_row->is_parent($is_parent);
                if ( !$is_parent && $step_row->in_storage ) {
                    $step_row->substeps->delete;
                }
            }

            if ( defined $link ) {
                $self->_tasks->link_step_row($step_row => $link);
            }

            $step_row->update_or_insert;
            $self->_update_subtask_if_any($step_row);
        }

        elsif ( my $ar = $step_row ) {
            # Even neither {parent} nor {pos} exist, so forget all substeps
            # unmentioned in the hierarchy given that DBIx::Class will delete
            # their descendents (cascade_delete => 1 set if not implied).
            my $inhier;
            while ( $ar = $ar->parent_row ) {
                next if !($inhier = $in_hierarchy{ $ar->name });
                if ( !$inhier->{$name} ) {
                    #warn "Delete step ", $step_row->name, " as it is not",
                    #     " found in current step hierarchy\n";
                    eval { $step_row->delete };
                    if ( $@ ) {
                        warn "Deletion failed for $name: $@\n"
                    }
                }
                last;
            }
            continue {
                $name = $ar->name;
            }
            
        }

    }

}

sub check_timestructure {
    my ($self,@steps_to_check) = shift;
    
    if ( !@steps_to_check ) {
        @steps_to_check = $self->dbicrow->steps->get_column('name');
    }

    my %checked;

    ...

    # TODO: Check if the time configurations of subtasks overlap each other. Plus, the initial
    # time tracks of descendent subtasks may not begin earlier than those of the surrounding
    # upper subtask, likewise the final timetracks of descendent subtasks may not end later 
    # accordingly.

    # What complicates things is that expoftime_share, pos and time patterns (i.e. number of net 
    # seconds in a given time period) have to be considered to calculate if they match with the
    # assigned timespans. Not only this is to do with subtasks under the same parent step, but
    # as well with those of different ancestors, even if levels below, until down to a subtask in
    # question, are unpositioned.
}

my %SUBTASK_EXT = map { $_ => 1 } FTM::FlowDB::Task->list_properties;
delete $SUBTASK_EXT{'name'};
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
        $f = q{}.( FTM::Time::Point->parse_ts($f)->fill_in_assumptions );
    }
    for my $o ( $data->{open_since} // () ) { $o = $o.q{} }

    for my $p ( $data->{priority} // () ) {
        my $num = $self->_tasks->priority_resolver->("n:$p");
        if ( $num ) { $p = $num }
        elsif ( $p !~ m{ \A [1-9] [0-9]* \z }xms ) {
            FTM::Error::Task::InvalidDataToStore->throw(
                "unknown priority label: $p"
            );
        }
    }

}

for my $col ( FTM::FlowDB::Task->list_properties( 'column' ), "description" ) {
    no strict 'refs';
    next if defined &{$col};
    *{$col} = sub {
        my $self = shift;
        croak "No arguments supported. Use store({ $col => ... }) instead"
            if @_;
        $self->dbicrow->$col();
    }
}

around priority => sub {
    my ($orig, $self) = @_;
    croak "No arguments supported. Use store({ priority => ... }) instead"
        if @_ > 2;
    my $number = $self->$orig();
    return $self->_tasks->priority_resolver->( "p:$number" ) // $number;
};

sub priority_num { shift->dbicrow->priority };

sub step { shift->steps->find({ name => shift }) }

sub archive_if_completed {
    my ($self) = @_;
    my $uncompleted_own_steps = $self->steps({
        done => { '<' => { -ident => 'checks' } }
    });
    if ( !$uncompleted_own_steps || $self->current_focus ) {
        $self->dbicrow->update({ archived_because => undef, archived_ts => undef });
    }
    else {
        $self->dbicrow->update({
            archived_because => 'done',
            archived_ts => FTM::Time::Point->now_as_string(),
        });
    }
}
 
__PACKAGE__->meta->make_immutable();

package FTM::Error::Task::FailsToLoad;
use Moose;
extends 'FTM::Error';

package FTM::Error::Task::InvalidDataToStore;
use Moose;
extends 'FTM::Error';

__END__

__END__

=head1 NAME

FTM::Task - Binds the database row to dynamic, cached data used for scoring

=head1 SYNOPSIS

=head1 DESCRIPTION

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

