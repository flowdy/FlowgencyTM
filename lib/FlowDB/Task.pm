
use strict;

package FlowDB::Task;
use Carp qw/croak/;
use Moose;
extends 'DBIx::Class::Core';


my ($MANDATORY, $OPTIONAL) = map {{ is_nullable => $_ }} 0, 1;

__PACKAGE__->table('task');
__PACKAGE__->add_column( ROWID => { data_type => 'INTEGER' });
__PACKAGE__->add_columns(
    user             => $MANDATORY,
    name             => $MANDATORY,
    title            => $OPTIONAL,
    main_step        => $OPTIONAL,
        # It's not really, but otherwise we would run into circular reference problems:
        # Because steps (like main_step) have a foreign key constraint matching our
        # autoincremented primary key, the task record must be inserted first.
        # By deferring the step-side foreign key check, we would have to guess our primary
        # key, but doing so smells of pitfalls. So we have to ensure main_step is properly
        # dealt with in our insert and update wrappers.
    from_date        => $MANDATORY,
    priority         => $MANDATORY,
    archived_because => $OPTIONAL, # enum ('COMPLETE', 'PAUSED', 'CANCELLED')
    archived_ts      => $OPTIONAL,
    repeat_from      => $OPTIONAL,
    repeat_until     => $OPTIONAL, 
    frequency        => $OPTIONAL,
    client           => $OPTIONAL,
);

__PACKAGE__->has_many( steps => 'FlowDB::Step',
    { 'foreign.task' => 'self.ROWID' },
    { copy_cascade => 1 },
);

__PACKAGE__->has_many(
    timesegments => 'FlowDB::TimeSegment',
    { 'foreign.task_id' => 'self.ROWID' }
);

__PACKAGE__->set_primary_key( 'ROWID' );

{ my %tmp_msr;
  my @proxy_fields = qw(description done checks expoftime_share substeps);

__PACKAGE__->belongs_to( main_step_row => 'FlowDB::Step',
    { 'foreign.ROWID' => 'self.main_step'},
    { proxy => \@proxy_fields },
);

sub _tmp_main_step {
    my $args = shift;
    my $main_step = do {
        if ( my $row = shift ) {
            if ( exists $tmp_msr{$row} ) { delete $tmp_msr{$row}; }
            else { $tmp_msr{$row} = {} }
        }
        else { {} }
    };
    for ( @proxy_fields ) {
        my $val = delete $args->{$_} // next;
        $main_step->{$_} = $val;
    }
    return $main_step;
}

around new => sub {
    my ($orig, $class) = (shift, shift);    
    my $args = @_ > 1 ? { @_ } : shift;
    my $main_step = _tmp_main_step($args);
    my $self = $class->$orig($args);
    $tmp_msr{ $self } = $main_step;
    return $self;
};

for my $field ( @proxy_fields ) {
    around $field => sub {
        my ($orig, $self) = (shift, shift);
        if ( $self->in_storage ) { $self->$orig(@_); }
        elsif ( @_ ) { $tmp_msr{$self}{$field} = shift; }
        else { return $tmp_msr{$self}{$field}; }
    };
}

sub DEMOLISH {
    my $self = shift;
    delete $tmp_msr{$self};
}

}

sub sqlt_deploy_hook {
   my ($self, $sqlt_table) = @_;

   $sqlt_table->add_index(
        name => 'user_task',
        fields => ['user', 'name'],
        type => 'unique'
   );
   $sqlt_table->add_index(
        name => 'task_mainstep',
        fields => ['main_step'],
        type => 'unique'
   );

}

around copy => sub {
    my ($orig, $self, $args) = @_;
    ( $args //= {} )->{main_step} = undef;
   
    my $name = $self->name;
    my $msr = $self->main_step_row;
    my $c = $self->$orig($args);
    if ( $msr->task eq $name ) {
        $c->update({ main_step_row => $c->steps->find({ name => q{} }) });
    }
    else {
        $_->copy({ task => $c->ROWID }) for $msr->and_below;
    }

    return $c;

};

around insert => sub {
    $DB::single = 1;
    my ($orig, $self) = (shift, shift);
    my $args = @_ > 1 ? { @_ } : shift;
    my $main_step = _tmp_main_step($args => $self );
    $main_step->{name} = q{};
    $self->result_source->storage->txn_do(sub {
         $self->$orig($args);
         $main_step = $self->add_to_steps($main_step);
         $self->update({ main_step_row => $main_step });
    });
    return $self;
};

around update => sub {
    $DB::single = 1;
    my ($orig, $self) = (shift, shift);
    my $args = @_ > 1 ? {@_} : shift;
    my $main_step = _tmp_main_step( $args => $self );
    $main_step->{name} = q{};
    $self->$orig($args);
    $self->main_step_row->$orig($main_step);
    return $self;
};

1;

