use strict;

package FlowDB::TimeScheme;
use base 'DBIx::Class::Core';

__PACKAGE__->table('time_scheme');
__PACKAGE__->add_columns(qw/name title pattern propagate/);
__PACKAGE__->add_column( propagate => { is_nullable => 1 });
__PACKAGE__->add_column( inherit => { is_nullable => 1 });
__PACKAGE__->add_column( parent => { is_nullable => 1 });
__PACKAGE__->belongs_to(parent => __PACKAGE__, { 'foreign.name' => 'self.parent' }, { join_type => 'LEFT' });

__PACKAGE__->has_many(children => __PACKAGE__, { 'foreign.parent' => 'self.name'});

__PACKAGE__->has_many(variations => 'FlowDB::TimeVariation', { 'foreign.scheme' => 'self.name' });

__PACKAGE__->set_primary_key('name');

1;
