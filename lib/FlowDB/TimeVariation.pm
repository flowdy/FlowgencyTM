use strict;

package FlowDB::TimeVariation;
use base 'DBIx::Class::Core';

__PACKAGE__->table('time_variation');
__PACKAGE__->add_columns(qw/scheme name pos/);
for (qw/title from_date until_date pattern propagate/) {
    __PACKAGE__->add_column($_ => { is_nullable => 1 });
}
__PACKAGE__->belongs_to(scheme_row => 'FlowDB::TimeScheme', { 'foreign.name' => 'self.scheme' });

sub sqlt_deploy_hook {
   my ($self, $sqlt_table) = @_;

   $sqlt_table->add_index(
       name => 'scheme_name_i',
       fields => ['scheme','name'],
       type => 'unique'
   );

   $sqlt_table->add_index(
       name => 'scheme_pos_i',
       fields => ['scheme','pos'],
       type => 'unique',
   );

}

1;
