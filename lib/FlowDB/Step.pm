use strict;

package FlowDB::Step;

use Moose;
extends 'DBIx::Class::Core';

__PACKAGE__->table('step');

__PACKAGE__->add_columns(
    task => { is_nullable => 0 },
    name => { is_nullable => 0 },
    title => { is_nullable => 0 },
    description => { is_nullable => 1 },
    link => { is_nullable => 1 },
    pos => { data_type => 'INTEGER' },
    done => { data_type => 'INTEGER' },
    expoftime_share => { data_type => 'INTEGER', is_nullable => 0, }
); 

__PACKAGE__->add_columns(qw/ROWID parent/);

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
    { 'foreign.main_step' => 'self.ROWID' },
    { proxy => [qw/timeline from_date until_date client/],
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
    },
    { copy_cascade => 0 }
);

__PACKAGE__->has_many(
    linked_by => 'FlowDB::Step',
    { 'foreign.link' => 'self.ROWID' },
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

   $sqlt_table->add_index(
       name => 'links',
       fields => ['link'],
   );

}

around [qw[title description done checks]] => sub {
    my ($orig, $self, $value) = @_;
    if ( my $link = $self->link_row ) { $link->$orig; }
    else { $self->$orig(exists $_[2] ? $value : ()) }
};

has priority => (
    is => 'ro',
    isa => 'Int',
    lazy => 1,
    builder => sub {
        my $self = shift;
        if ( my $str = $self->subtask_row ) { return $str->priority }
        elsif ( my $p = $self->parent_row ) { return $p->priority }
        else { die "Can't find out priority" }
    },
),

sub calc_progress {
    my ($self, $LEVEL) = @_;

    my $checks = $self->checks;
    my $orig_exp = $self->expoftime_share;
    my $exp   = $checks ? $orig_exp                    : 0;
    my $share = $checks ? $self->done / $checks * $exp : 0;

    ONCE_OR_TWICE: {
        my $substeps = $self->substeps;
        while ( my $s = $substeps->next ) {
          my ($s_exp, $s_share) = $s->calc_progress($LEVEL+1);
          $exp   += $s_exp;
          $share += $s_share * $s_exp;
        }
        redo ONCE_OR_TWICE if $self = $self->link_row;
    }

    return defined($LEVEL) ? $orig_exp : (), $share / $exp;

}

sub get_focus {
    my ($self) = @_;

    my $substeps = $self->substeps->search(
        {}, { order_by => { -asc => ['pos'] } }
    );

    my (@focus, @multi);
    while ( my $s = $substeps->next ) {
        if ( !defined($s->pos) ) {
            push @multi, $s->get_focus();
        }
        elsif ( !@focus ) {
           @focus = $s->get_focus();
        }
    }

    my $linked = $self->link_row;

    return if !@focus && (
        $linked ? $linked->calc_progress == 1
                : $self->done == $self->checks
        );

    return @focus, [$self, @multi];
}

sub prior_deps {
    my ($self, $task_name) = @_;
    my @ret;

    my $p = $self->parent_row;
    return if !$p;

    if ( my $l = $p->link_row ) {
        push @ret, $l->prior_deps($task_name);
    }

    my $opts = { columns => ['link'], order_by => { -asc => ['pos'] } };

    my @prior_steps = $p->substeps->search({
        pos => { '<=' => $self->pos }
    }, $opts);

    while ( my $p = shift @prior_steps ) {
        unshift @prior_steps, $p->substeps->search({}, $opts);
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
    return $self, map { $_->and_below } $self->substeps->all;
}

1;
