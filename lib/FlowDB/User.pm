use strict;

package FlowDB::User;

use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('user');
__PACKAGE__->add_columns(qw/
    id username password time_scheme
    weights priorities
/);

__PACKAGE__->has_many(tasks => 'FlowDB::Task',
    { 'foreign.user' => 'self.id' },
);

__PACKAGE__->set_primary_key('id');

1;
