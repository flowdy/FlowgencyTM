use strict;

package FlowDB::Task;

use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('task');
__PACKAGE__->add_columns(
    qw/ ROWID user main_step from_date until_date priority
        archived_ts archived_because
        repeat_from repeat_until frequency
        time_profile client
      /
);

__PACKAGE__->add_column( name => { auto_increment => 1 } );

__PACKAGE__->has_many(steps => 'FlowDB::Step',
    { 'foreign.task' => 'self.name' },
    { copy_cascade => 1 },
);

__PACKAGE__->belongs_to( main_step_row => 'FlowDB::Step',
    { 'foreign.ROWID' => 'self.main_step'},
    { proxy => [qw(title description done checks expoftime_share substeps)] },
);

__PACKAGE__->has_many(
    timeline_row => 'FlowDB::TimeLine',
    { 'foreign.task_id' => 'self.ROWID' }
);

__PACKAGE__->set_primary_key( 'ROWID' );

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
        $_->copy({ task => $c->name }) for $msr->and_below;
    }

    return $c;

};

1;

