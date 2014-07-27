use strict;

package Task;
use Moose;
use Carp qw(carp croak);

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
    my $root = keys(%$args) == 1 # store() callable with { $step_name => \%data }
             ? do {              # or with { (step => $name), %further_data }
                   my ($k) = keys %$args;   # ^ omitted? => task/main_step data
                   ($args) = values %$args;
                   $k;
               }
             : delete $args->{step} // ''; 

    $args->{oldname} = $root;

    my $steps = delete $args->{steps} // {};

    # Make sure %$steps sub-hash has all existing steps with value {} at least
    for my $step ( $self->steps->search( {}, { columns => [qw/name/] } ) ) {
        $steps->{ $step->name } //= {};
    }

    $steps = $args->{substeps} && [ # was hash, is now array reference
        $self->_sequence_step_data_hrefs(
            $root, $steps, delete $args->{substeps},
        )
    ];

    $self->dbicrow->result_source->storage->txn_do(
        \&_store_write_to_db => $self, $root, $args, $steps,
    );

    my @to_recalc;
    while ( my ($step, $args) = each %$steps ) {
        next if !grep { defined($_) } @{$args}{qw{ done checks exp_oftime }};
        push @to_recalc, $step;
    }
    $self->tasks->recalc_dependencies($self => @to_recalc);

    return 1;

}

sub _sequence_step_data_hrefs {
    my ($self, $parent_name, $steps_href, $top_sequence) = @_;

    my %parent_of;   # %seen with parent names as values:
                     # Used to prevent circular references that
                     # would certainly cause endless loops

    my $sequencer = sub {
        my $sequence = shift;

        my ($defined_pos, $undefined_pos) = split m{\s*;\s*}x, $sequence, 2;
        my  @defined_pos                  = split m{   ,\s*}x, $defined_pos;
        my ($order_num, @steps)           = ( undef, () );

        CLUSTER:
        for my $cl ( $undefined_pos, @defined_pos ) {

            next CLUSTER if !defined $cl;

            for my $step_name ( split m{ [/] }xms, $cl ) {
                my $step = $steps_href->{$step_name};

                croak qq{No step "$step_name" defined} if !$step;
                croak qq{Step already subordinated to $parent_of{$step}}
                    if $parent_of{$step};

                @{$step}{ 'oldname', 'parent',     'pos'      }
                    = ( $step_name,  $parent_name, $order_num );
                
                push @steps, $step;
   
                $parent_of{ $step } = $parent_name;
            }
            
        }
        continue {
            $order_num++;
        }
        
        return @steps;

    }; # end of $sequencer definition

    my @steps = $sequencer->($top_sequence);
    my @ordered_steps;

    while ( my $step = shift @steps ) {

        if ( my $substeps = delete $step->{substeps} ) {
            $parent_name = $step->{name} // $step->{old_name};
            unshift @steps, $sequencer->($substeps);
        }

        push @ordered_steps, $step;

    }

    if ( my @not_seen = grep { !defined $parent_of{$_} } keys %$steps_href ) {
        croak 'steps hash-ref contains keys not listed in any substeps entry'
            . ': ', join q{, }, @not_seen;
    }
    return @ordered_steps;

}

sub _store_write_to_db {
    my ($self, $root_step, $root, $steps_upd_data) = @_;

    my $row = $self->dbicrow;
    my $steps_rs = $row->steps;
    my %new_parents;

    my %steps2; # working copy to be rebuild on reentry
                # (e.g. database reconnection)
    while ( my ($step, $properties) = each %$steps_upd_data ) {
        $steps2{$step} = { %$properties };
    }

    if ( !length($root_step) ) {
        delete $root->{oldname};
        while ( my ($key, $value) = each %$root ) {
            $row->$key($value);
        }
        croak "root step cannot have a parent"
            if $root->{parent};
    }
    elsif ( my $p = $root->{parent} ) {
        croak "parent row with ID $p not found"
            if !$steps_rs->find($p);
    }
    else { croak "No parent" }

    my @NON_DB_FIELDS = qw/ substeps _ancestor _level _substeps_processed /;

    while ( my $step = $steps_rs->next ) {

        if ( my $s = delete $steps2{ $step->name } ) {

            for my $p ($s->{parent}) {
                last if $steps_rs->find($s->{parent});

                # can't have a nonexisting row as a parent,
                # so let's reset it to NULL temporarily
                push @{$new_parents{$p}}, $step->name;
                $p = undef;

            }

            delete @{$s}{@NON_DB_FIELDS};
                # If we kept emptied array-ref substeps here, DBIx::Class
                # would think $step hasn't any and erase what has just been
                # or is yet to be updated.
                # _level is needed for rows to insert only (s.b)

            $step->update($s);

        }

        else {
            # Forget all substeps unmentioned in the hierarchy
            # given that DBIx::Class will delete their descendents with
            # cascade_delete => 1 set.
    
            my ($ar,$ah) = ($step,undef);
            until ( $ah ) { $ar = $ar->parent_row;
                $step->delete if ($ah = $steps2{$ar->name})
                              && $ah->{substeps}
                              ;
            }
    
        }
    
    }

    # In order to not violate foreign key constraint (task,parent/name)
    # we insert new steps one level after another.
    for my $s ( sort { $a->{_level} <=> $b->{_level} } values %steps2 ) {
        delete @{$s}{@NON_DB_FIELDS};
        $row->add_to_steps($s);
    }

    while ( my ($name,$substeps) = %new_parents ) {
        $steps_rs->search({ name => { in => $substeps } })
                ->update({ parent => $name })
                ;
    }

    is_link_valid($_) for $steps_rs->search({ link => { '!=' => undef }});

    $row->main_step_row( $steps_rs->find({ name => '' }) );

    my $result;

    if ( $row->in_storage ) {
        
        $result = $row->update;
        $self->redraw_cursor_way;
        $self->_clear_progress; # to be recalculated on next progress() call

    }
    else {
        $result = $row->insert();
        for my $ts ( @{ $root->{timestages} } ) {
            $row->add_to_timestages($ts);
        }
        croak "Can't build cursor: $@" if !eval { $self->_cursor };
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
