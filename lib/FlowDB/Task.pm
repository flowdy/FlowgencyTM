use strict;

package FlowDB::Task;
use base 'DBIx::Class::Core';

__PACKAGE__->table('task');
__PACKAGE__->add_columns(qw/name main_step from_date until_date priority timeline client/);
__PACKAGE__->has_many(steps => 'FlowDB::Step', { 'foreign.task' => 'self.name' });
__PACKAGE__->belongs_to( main => 'FlowDB::Step', { 'foreign.ROWID' => 'self.main_step'}, { proxy => [qw(title description done expoftime_share)], copy_cascade => 1 });
__PACKAGE__->belongs_to( timeline_row => 'FlowDB::TimeScheme', { 'foreign.name' => 'self.timeline' });
__PACKAGE__->set_primary_key( 'name' );

sub sqlt_deploy_hook {
   my ($self, $sqlt_table) = @_;

   $sqlt_table->add_index(
        name => 'mainstep',
        fields => ['main_step'],
        type => 'unique'
   );

}

1;

