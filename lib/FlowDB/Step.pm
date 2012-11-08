use strict;

package FlowDB::Step;

use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('step');
__PACKAGE__->add_columns(qw/ROWID task parent name title/);

for (qw/pos done checks expoftime_share/) {
    __PACKAGE__->add_column($_ => { data_type => 'INTEGER', is_nullable => 0 });
}

__PACKAGE__->add_columns(
    description => { is_nullable => 1 },
    link => { is_nullable => 1 }
); 

__PACKAGE__->belongs_to(
    parent_row => 'FlowDB::Step',
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
    { proxy => [qw/timeline priority from_date until_date client/],
      # update_cascade => 1, # why?
    }
);

__PACKAGE__->belongs_to(
    link_row => 'FlowDB::Step',
    { 'foreign.ROWID' => 'self.link', }
);

__PACKAGE__->has_many(
    substeps => 'FlowDB::Step',
    { 'foreign.parent' => 'self.name',
      'foreign.task' => 'self.task'
    }
    { copy_cascade => 0 }
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

around [qw[title description done checks]] => sub {
    my ($orig, $self, $value) = @_;
    if ( my $link = $self->link_row ) { $link->$orig; }
    else { $self->$orig(exists $_[2] ? $value : 0) }
};

sub done_rate {
    my ($self, $LEVEL) = shift;

    my $exp = $self->expoftime_share;
    my $share = $self->done / $self->checks * $exp;

    ONCE_OR_TWICE: {
        my $substeps = $self->substeps;
        while ( my $s = $substeps->next ) {
          my ($s_exp, $s_share) = $c->done_rate($LEVEL+1);
          $exp   += $s_exp;
          $share += $s_share * $s_exp;
        }
        redo ONCE_OR_TWICE if $self = $self->link_row;
    }

    return $LEVEL ? $exp : (), $share / $exp;
}

sub prior_deps {
    my ($self, $task_name) = @_;
    my @ret;

    my $p = $self->parent_row;
    return if !$p;

    if ( my $l = $p->link_row ) {
        push @ret, $l->prior_deps($task_name)
    }

    my @prior_steps = $p->steps->search({ pos => { '<' => $self->pos } });
    while ( my $p = shift @prior_steps ) {
        unshift @prior_steps, $p->substeps;
        my $l = $p->link_row // next;

        push @ret, $l->task eq $task_name
                     ? $l->name
                     : $l->prior_deps($task_name)
                     ;

    }

    return @ret, $p->prior_deps($task_name);

}

sub and_below {
    my $self = shift;
    return $self, map { $_->and_below } $self->substeps;
}

sub climb_up {
    my ($self, $sub, $cont) = @_;

    my $p = $self;
    my @ret;
    while ( $p = $p->parent_row ) {
        @ret = $sub->($p,\$cont);
        next if $cont;
    }

    return @ret;
}

1;
