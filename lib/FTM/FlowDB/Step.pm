use strict;

package FTM::FlowDB::Step;

use Moose;
use Carp qw(croak);
use Scalar::Util qw(reftype);
use List::Util qw(first);
extends 'DBIx::Class::Core';

__PACKAGE__->table('step');

my @INTEGER = ( data_type => 'INTEGER' );
my @NULLABLE = ( is_nullable => 1 );

__PACKAGE__->add_columns(
    step_id         => { @INTEGER },
    checks          => { @INTEGER, default_value => 1 },
    done            => { @INTEGER, default_value => 0 },
    description     => { @NULLABLE },
    expoftime_share => { @INTEGER, default_value => 1 },
    name            => { default_value => '' },
    link_id         => { @INTEGER, @NULLABLE },
    parent_id       => { @INTEGER, @NULLABLE },
    pos             => { @NULLABLE, data_type => 'FLOAT' },
    task_id         => { @INTEGER },
); 
__PACKAGE__->set_primary_key("step_id");

__PACKAGE__->belongs_to(
    parent_row => 'FTM::FlowDB::Step',
    { 'foreign.step_id' => 'self.parent_id' }
);

__PACKAGE__->belongs_to(
    task_row => 'FTM::FlowDB::Task',
    'task_id'
);

# Bestimmte Schritte einer Aufgabe können eine Zeitbegrenzung, Priorität etc.
# haben, die von der eigentlich übergeordneten Aufgabe abweichen.
__PACKAGE__->belongs_to(
    subtask_row => 'FTM::FlowDB::Task',
    { 'foreign.main_step_id' => 'self.step_id' },
    { proxy => [qw/title timesegments from_date client/],
      is_foreign_key_constraint => 0,
    }
);

__PACKAGE__->belongs_to(
    link_row => 'FTM::FlowDB::Step',
    { 'foreign.step_id' => 'self.link_id', }
);

__PACKAGE__->has_many(
    substeps => 'FTM::FlowDB::Step',
    { 'foreign.parent_id' => 'self.step_id',
      'foreign.task_id' => 'self.task_id'
    },
    { cascade_copy => 0 }
);

__PACKAGE__->has_many(
    linked_by => 'FTM::FlowDB::Step', 'link_id',
    { cascade_copy => 0 }
);

sub sqlt_deploy_hook {
   my ($self, $sqlt_table) = @_;

   $sqlt_table->add_index(
       name => 'tree',
       fields => ['task_id','name'],
       type => 'unique'
   );

   $sqlt_table->add_index(
       name => 'links',
       fields => ['link_id'],
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

has future_focus_queue_len => (
    is => 'rw', isa => 'Num'
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
    my ($self, $out_fh, $limit) = @_;
    $out_fh //= wantarray && 0; # remains undef in void context 

    my @ret;
    my $print
        = $out_fh          ? sub { _print_fmtd_focus_step(@_ => $out_fh) }
        : defined($out_fh) ? sub { push @ret, [ @_[1, 0, 2] ] }
        :                    sub { _print_fmtd_focus_step(@_) }
        ;
 
    my @tree = $self->_focus_tree($limit);
    my @depth = ( scalar @tree );

    my ($link_substeps_blocked);

    ITEM:
    while ( my $step = shift @tree ) {

        $depth[-1]-- or next ITEM;

        my $is_link = !1;
        
        if ( ref $step eq 'ARRAY' ) {
            my $next = $tree[0];
            if ( ref($next) eq 'REF' && !$$next->is_within_focus ) {
                # If item is an array ref of substeps of a link,
                # we display them only if the linked row is currently
                # focussed in the scope of its associated task.
                next ITEM if $link_substeps_blocked = !$$next->is_completed;
            }
            unshift @tree, @$step;
            push @depth, scalar @$step;
            next ITEM;
        }

        elsif ( ref $step eq 'REF' ) {
            $step = $$step;
            $is_link = $link_substeps_blocked ? -1 : 1;
            $link_substeps_blocked = 0;
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
    my $pending = $self->future_focus_queue_len;   
    print {$out_fh} join " ",
                    $depth . "|", 
                    sprintf("%d/%d",$self->done, $self->checks),
         $is_link ? sprintf("%sLINK to %s:",
                      $is_link < 0 ? "BLOCKED " : "",
                      do {
                        join "/", $self->task_row->name, $self->name;
                      }
                  )
                  : (),
                    $self->title // $self->description // $self->name,
         $pending ? " (pending: $pending)" : q{},
                    "\n"
                  ;
}

sub _focus_tree {
    my ($self, $limit) = @_;
    $limit //= -1;

    my $substeps = $self->substeps;
    my $opts = { order_by => { -asc => 'pos' } };
    my $max_pos = $substeps->get_column('pos')->max // 1;
    my @uncomplete;
    my $pos = 0;

    my $pending_substeps_count = $substeps->count;

    if ( $limit ) {

        INCR_POS:
        until ( ++$pos > $max_pos ) {
            my $expr = { like => $pos.q{.%} };
            my @substeps = $substeps->search({ pos => $expr }, $opts);

            for my $step ( @substeps ) {
                push @uncomplete, $step->_focus_tree($limit-1);
            }

            $pending_substeps_count -= @substeps;

            last INCR_POS if @uncomplete;

        }

        for my $step ( $substeps->search({ pos => undef }, $opts) ) {
            push @uncomplete, $step->_focus_tree($limit-1);
            $pending_substeps_count--;
        }

        if ( @uncomplete ) {
            @uncomplete = ([ @uncomplete ]);
        }

        if ( my $link = $self->link_row ) {
            if ( my @steps = $link->_focus_tree($limit-1) ) {
                my $l = pop @steps;
                die "linked step not identical with itself" if $l != $link;
                unshift @uncomplete, @steps, \$l;
            }
        }

    }

    if ( @uncomplete ) {
        $self->future_focus_queue_len($pending_substeps_count);
    }
    if ( @uncomplete || !$self->is_completed ) {
        push @uncomplete, $self;
    }

    return wantarray ? @uncomplete : \@uncomplete;

}

sub is_within_focus {
    my ($self) = @_;

    my $trow = $self->task_row;

    my $id = $self->step_id;
    return !! first { $_->[1]->step_id eq $id }
              $trow->main_step_row->current_focus
        ;

}

sub substeps_chain {
    my ($self) = @_;

    my $substeps = $self->substeps->search(
        {}, { order_by => { -asc => ['pos'] } }
    );

    my (@groups, $unordered, $last_group);
    if ( $substeps->search({ pos => undef })->count ) {
        $last_group = $unordered = [];
    }

    my $last_pos = 0;
    for my $step ( $substeps->all ) {
        my $pos = int( $step->pos // 0 );
        if ( $pos > $last_pos ) {
            push @groups, $last_group = [];
        }
        push @$last_group, $step->name;
        $last_pos = $pos;
    }

    for my $group ( @groups, $unordered //= [] ) {
        $group = join '/', @$group;
    }

    my $chain = join q{,}, @groups;
    if ( length $unordered ) {
        $chain .= q{;} . $unordered; 
    }

    return $chain;   
}

sub is_completed {
    my ($self, $limit ) = shift;
    $limit //= 0;

    if ( $limit ) {
        return !1 if first { !$_->is_completed($limit-1) } $self->substeps;
    }

    return $self->done == $self->checks
}
       
sub prior_deps {
    my ($self, $task_id) = @_;
    my @ret;

    my $p = $self->parent_row;
    return if !$p;

    if ( my $l = $p->link_row ) {
        push @ret, $l->prior_deps($task_id);
    }

    my $opts = {
        columns => ['link_id','step_id','task_id'],
        order_by => { -asc => ['pos'] }
    };

    my $pos = $self->pos;
    my @prior_steps = $p->substeps->search({
        $pos ? ( pos => [ undef, { '<=' => $pos } ] ) : (),
        name => { '!=' => $self->name },
    }, $opts);

    while ( my $p = shift @prior_steps ) {
        unshift @prior_steps, $p->substeps->search({}, $opts);
        my $l = $p->link_row // next;

        push @ret, $l->task_id eq $task_id
                     ? $l->name
                     : $l->prior_deps($task_id)
                     ;

    }

    return @ret, $p->prior_deps($task_id);

}

sub isa_subtask {
    my ($self) = @_;
    my $subtask = $self->subtask_row // return;
    return 1;
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

sub dump {
    my ($self) = @_;
    my %data = $self->get_columns;
    if ( my $prow = $self->parent_row ) {
        $data{parent_id} = $prow->name;
        $data{link_id} = join ".", map { $_->task, $_->name }
             $self->link_row // ();
    }
    if ( my $srow = $self->subtask_row ) {
        my $data = $data{subtask_data} = { $srow->get_columns };
        $data->{timeway} = [
            map {{ $_->get_columns }} $srow->timestages
        ], 
    }
    $data{substeps} = $self->substeps_chain;
    return \%data;
}

1;

__END__

=head1 NAME

FTM::FlowDB::Step - Interface to the raw data stored to a task step

=head1 SYNOPSIS

 $step->current_focus;
 $step->calc_progress;
 $step->is_within_focus;
 $step->is_completed;
 $step->prior_deps;
 $step->isa_subtask;
 my @ancestors = $step->ancestors_upto( $ancestor // () );
 my (undef, @descendents) = $step->and_below;

=head1 DESCRIPTION

=head1 COPYRIGHT

(C) 2012-2014 Florian Hess

=head1 LICENSE

This file is part of FlowgencyTM.

FlowgencyTM is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowgencyTM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowgencyTM. If not, see <http://www.gnu.org/licenses/>.

