use strict;

package FlowDB::TimeLine;

use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('timeline');
__PACKAGE__->add_columns(qw/ task_id until_date profile lock_opt /);

1;

