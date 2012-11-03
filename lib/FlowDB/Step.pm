use strict;

package FlowDB::Step;
use base 'DBIx::Class::Core';

__PACKAGE__->table('step');
__PACKAGE__->add_columns(qw/ROWID task parent name title/);

for (qw/pos done substeps expoftime_share/) {
    __PACKAGE__->add_column($_ => { data_type => 'INTEGER', is_nullable => 0 });
}

__PACKAGE__->add_column(description => { is_nullable => 1 });
__PACKAGE__->add_column(link => { is_nullable => 1 }); 

__PACKAGE__->belongs_to(
    parentNode => 'FlowDB::Step',
    { 'foreign.name' => 'self.parent',
      'foreign.task' => 'self.task'
    }
);

__PACKAGE__->belongs_to(
    task_row => 'FlowDB::Task',
    { 'foreign.name' => 'self.task' }
);

# Bestimmte Schritte einer Aufgabe können eine Zeitbegrenzung, Priorität etc.
# haben, die von der eigentlich übergeordneten Aufgabe abweichen.
__PACKAGE__->belongs_to(
    subtask_row => 'FlowDB::Task',
    { 'foreign.main_step' => 'self.ROWID' }
);

__PACKAGE__->belongs_to(
    link_row => 'FlowDB::Step',
    { 'foreign.ROWID' => 'self.link',
      #'foreign.task' => { "!=" => 'self.task' },
    }
);

__PACKAGE__->has_many(
    children => 'FlowDB::Step',
    { 'foreign.parent' => 'self.name',
      'foreign.task' => 'self.task'
    }
);

sub sqlt_deploy_hook {
   my ($self, $sqlt_table) = @_;

   $sqlt_table->add_index(
       name => 'tree',
       fields => ['task','parent','name'],
       type => 'unique'
   );

   $sqlt_table->add_index(
       name => 'tree_pos',
       fields => ['task','parent','pos'],
       type => 'unique'
   );

}

sub done_rate {
    my ($self, $level) = shift;

    my $exp = $self->expoftime_share;

    if ( my $l = $self->link ) { $self = $l }

    my $share = $self->done / $self->substeps * $exp;
    my $children = $self->children;
    while ( my $c = $children->next ) {
        my ($c_exp, $c_share) = $c->done_rate($level+1);
        $exp   += $c_exp;
        $share += $c_share * $c_exp;
    }

    return $level ? $exp : (), $share / $exp;
}

1;
