use strict;

package FTM::FlowDB::Mailoop;
use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('mailoop');

__PACKAGE__->add_column('user_id');
__PACKAGE__->add_column('type');
__PACKAGE__->add_column('token');
__PACKAGE__->add_column('value' => { is_nullable => 1 });
__PACKAGE__->add_column('request_date' => {
    data_type => 'DATETIME',
    is_nullable => 1,
});

__PACKAGE__->set_primary_key('user_id');

__PACKAGE__->belongs_to('user', 'FTM::FlowDB::User', 'user_id');

sub sqlt_deploy_hook {
   my ($self, $sqlt_table) = @_;

   $sqlt_table->add_index(
        name => 'token',
        fields => ['token'],
        type => 'unique'
   );

}

1;
