use strict;

package FlowDB::TimeLine;

use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('timeline');
__PACKAGE__->add_columns(qw/ task_id from_date timeprofile lock_opt /);

1;

