use strict;

package FTM::FlowDB::User;

use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('user');
__PACKAGE__->add_columns(qw/
    user_id username password
    weights time_model priorities
/);

__PACKAGE__->set_primary_key('user_id');

__PACKAGE__->has_many(tasks => 'FTM::FlowDB::Task',
    'user_id',
);

1;
