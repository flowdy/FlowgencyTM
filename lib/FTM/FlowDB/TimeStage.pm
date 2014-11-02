use strict;

package FTM::FlowDB::TimeStage;

use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('timesegment');
__PACKAGE__->add_columns(qw/ task_id until_date track /);
__PACKAGE__->add_column(lock_opt => { is_nullable => 1 });

__PACKAGE__->belongs_to("task", "FTM::FlowDB::Task", "task_id" );

1;

