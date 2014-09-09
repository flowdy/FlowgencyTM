use strict;

package FlowDB::Step;

use Moose;
use Carp qw(croak);
use Scalar::Util qw(reftype);
extends 'DBIx::Class::Core';

__PACKAGE__->table('step');

my @INTEGER = ( data_type => 'INTEGER' );
my @NULLABLE = ( is_nullable => 1 );

__PACKAGE__->add_columns(
    checks          => { @INTEGER, default_value => 1 },
    done            => { @INTEGER, default_value => 0 },
    description     => { @NULLABLE },
    expoftime_share => { @INTEGER, default_value => 1 },
    name            => { default_value => '' },
    link            => { @NULLABLE },
    parent          => { @NULLABLE },
    pos             => { @NULLABLE, data_type => 'FLOAT' },
    ROWID           => { @INTEGER },
    task            => {},
); 
__PACKAGE__->set_primary_key("ROWID");

__PACKAGE__->belongs_to(
    parent_row => 'FlowDB::Step',
    { 'foreign.ROWID' => 'self.parent' }
);

__PACKAGE__->belongs_to(
    task_row => 'FlowDB::Task',
    { 'foreign.ROWID' => 'self.task' }
);

# Bestimmte Schritte einer Aufgabe können eine Zeitbegrenzung, Priorität etc.
# haben, die von der eigentlich übergeordneten Aufgabe abweichen.
__PACKAGE__->belongs_to(
    subtask_row => 'FlowDB::Task',
    { 'foreign.main_step' => 'self.ROWID' },
    { proxy => [qw/title timesegments from_date client/],
      is_foreign_key_constraint => 0,
    }
);

__PACKAGE__->belongs_to(
    link_row => 'FlowDB::Step',
    { 'foreign.ROWID' => 'self.link', }
);

__PACKAGE__->has_many(
    substeps => 'FlowDB::Step',
    { 'foreign.parent' => 'self.ROWID',
      'foreign.task' => 'self.task'
    },
    { cascade_copy => 0 }
);

__PACKAGE__->has_many(
    linked_by => 'FlowDB::Step',
    { 'foreign.link' => 'self.ROWID' },
    { cascade_copy => 0 }
);

sub sqlt_deploy_hook {
   my ($self, $sqlt_table) = @_;

   $sqlt_table->add_index(
       name => 'tree',
       fields => ['task','name'],
       type => 'unique'
   );

   $sqlt_table->add_index(
       name => 'links',
       fields => ['link'],
   );

}

has priority => (
    is => 'ro',
    isa => 'Int',
    lazy => 1,
    init_arg => undef,
    default => sub {
        my $self = shift;
        if ( my $str = $self->subtask_row ) { return $str->priority }
        elsif ( my $p = $self->parent_row ) { return $p->priority }
        else { die "Can't find out priority" }
    },
);

has is_parent => (
    is => 'rw', isa => 'Bool', lazy => 1,
    default => sub { !!(shift->substeps->count); },
);

before ['insert', 'update'] => sub {
    my ($self, $args) = @_;
    $args //= {};
    my $checks = $args->{checks}            // $self->checks          // 1;
    my $done   = $args->{done}              // $self->done            // 0;
    my $exp    = $args->{expoftime_share}   // $self->expoftime_share // 1;
    croak "done field cannot be negative" if $done < 0;
    croak "checks value cannot be negative" if $checks < 0;
    croak "expoftime_share value cannot be less than 1" if $exp < 1;
    croak "Checks must be >0 unless step is linked or has / will have substeps"
        if !$checks && !($self->link_row || $self->is_parent);
    croak "Step cannot have more checks done than available"
        if $done > $checks;
};

sub calc_progress {
    my ($self, $LEVEL) = @_;
    $LEVEL //= 0;

    my ($step, $exp, $share) = ($self, 0, 0);

    ONCE_OR_TWICE: {

        my ($checks, $my_exp)  = ($step->checks, $step->expoftime_share);
        $exp       += $checks ? $my_exp                         : 0;
        $share     += $checks ? $step->done / $checks * $my_exp : 0;

        my $substeps  = $step->substeps;
        while ( my $s = $substeps->next ) {
          my ($s_exp, $s_share) = $s->calc_progress($LEVEL+1);
          $exp   += $s_exp;
          $share += $s_share * $s_exp;
          #printf "#\t%d: E %.3f S %.3f\n", $LEVEL, $exp, $share;
        }

        #printf "# %d %s (%d): E %.3f, S %.3f\n",
        #    $LEVEL,
        #    $self == $step ? $step->name
        #                   : ">".$step->task_row->name."/".$step->name
        #                   ,
        #    $self->expoftime_share,
        #    $exp, $share;

        redo ONCE_OR_TWICE if $step = $step->link_row;

    }

    return $LEVEL ? $self->expoftime_share : (), $share / $exp;

}

sub current_focus {
    my ($self, $out_fh) = @_;
    $out_fh //= wantarray && 0;

    my @ret;
    my $print
        = $out_fh          ? sub { _print_fmtd_focus_step(@_ => $out_fh) }
        : defined($out_fh) ? sub { push @ret, [ @_[1, 0, 2] ] }
        :                    sub { _print_fmtd_focus_step(@_) }
        ;
 
    my @tree = $self->_focus_tree;
    my @depth = ( scalar @tree );

    ITEM:
    while ( my $step = pop @tree ) {

        $depth[-1]-- or next ITEM;

        if ( ref $step eq 'ARRAY' ) {
            push @tree, @$step;
            push @depth, scalar @$step;
            next ITEM;
        }

        my $is_link = !1;
        if ( ref $step eq 'REF' ) {
            $step = $$step;
            $is_link = 1;
        }

        $print->($step, $#depth, $is_link);

    }
    continue {
        pop @depth if !$depth[-1];
    }
    
    return if !@ret;
    return wantarray ? @ret : \@ret;    

}

sub _print_fmtd_focus_step {
    my ($self, $depth, $is_link, $out_fh) = @_;
    $out_fh //= \*STDOUT;
    if ( reftype($out_fh) eq 'SCALAR' ) {
        my $sref = $out_fh;
        open $out_fh, '>', $sref;
    }
    print {$out_fh} join " ",
                    $depth . "|", 
                    sprintf("%d/%d",$self->done, $self->checks),
         $is_link ? sprintf("LINK to %s:", do {
                        join "/", $self->task_row->name, $self->name;
                    })
                  : (),
                    $self->title // $self->description // $self->name,
                    "\n"
                  ;
}

sub _focus_tree {
    my ($self) = @_;

    my $substeps = $self->substeps;
    my $opts = { order_by => { -asc => 'pos' } };
    my $max_pos = $substeps->get_column('pos')->max // 1;
    my (@uncomplete, $pos);

    INCR_POS:
    until ( ++$pos > $max_pos ) {
        my $expr = $pos ? { like => $pos.q{.%} } : undef;
        my @substeps = $substeps->search({ pos => $expr }, $opts);

        my @uncmpl_sub;

        for my $step ( @substeps ) {
            push @uncmpl_sub, $step->_focus_tree($pos);
        }

        if ( @uncmpl_sub || !@substeps ) {
            push @uncomplete, @uncmpl_sub;
            if ( $pos ) { $pos = 0; redo INCR_POS; }
            else { last INCR_POS; }
        }
        elsif ( !$pos ) {
            # all substeps have been processed
            last INCR_POS;
        }

    }

    if ( @uncomplete ) {
        @uncomplete = ([ splice @uncomplete ]);
    }

    if ( my $link = $self->link_row ) {
        if ( my ($l, @steps) = $link->_focus_tree ) {
            die "linked step not identical with itself" if $l != $link;
            push @uncomplete, \$l, @steps;
        }
    }

    if ( @uncomplete || $self->done < $self->checks ) {
        unshift @uncomplete, $self;
    }

    return wantarray ? @uncomplete : \@uncomplete;

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

    my $pos = $self->pos;
    my @prior_steps = $p->substeps->search({
        $pos ? ( pos => [ undef, { '<=' => $pos } ] ) : (),
        name => { '!=' => $self->name },
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

sub isa_subtask {
    my ($self) = @_;
    my $subtask = $self->subtask_row // return;
    return ($subtask->name // '') eq $self->task;
}

sub ancestors_upto {
    my ($self, $upto) = @_;
    $upto //= $self->name;

    my ($p, @rows) = ($self, ());
    while ( $p = $p->parent_row() ) {
        last if $p->name eq $upto;
        push @rows, $p;
    }

    return @rows;
}

sub and_below {
    my ($self) = shift;
    my @args = @_ ? @_ : ({});
    return $self, map { $_->and_below(@args) }
                      $self->substeps->search(@args);
}

1;
