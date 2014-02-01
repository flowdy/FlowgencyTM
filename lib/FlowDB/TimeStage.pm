use strict;

package FlowDB::TimeSegment;;

use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('timesegment');
__PACKAGE__->add_columns(qw/ task_id until_date track /);
__PACKAGE__->add_column(lock_opt => { is_nullable => 1 });

__PACKAGE__->belongs_to("task", "FlowDB::Task", { "foreign.ROWID" => "self.task_id" });

1;

