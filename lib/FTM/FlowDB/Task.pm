
use strict;

package FTM::FlowDB::Task;
use Carp qw/croak/;
use Moose;
extends 'DBIx::Class::Core';

my ($MANDATORY, $OPTIONAL) = map { { is_nullable => $_ } } 0, 1;

has _multirel_cache => (
    is => 'ro',
    isa => 'HashRef',
    default => sub {{}},
    lazy => 1, # does not work without
);

has _upper_subtask_row => (
    is => 'rw',
    isa => __PACKAGE__,
);

__PACKAGE__->table('task');
__PACKAGE__->add_column( ROWID => { data_type => 'INTEGER' });
__PACKAGE__->add_columns(
    user             => $OPTIONAL, # Subtask ? null : not null
    name             => $OPTIONAL, # Subtask ? null : not null
    title            => $MANDATORY,
    main_step        => $OPTIONAL,
        # It's not really, but otherwise we would run into a race condition:
        # Because all steps (so main_step, too) have a foreign key constraint
        # matching our autoincremented primary key, the task record must be
        # inserted first. By deferring the step-side foreign key check, 
        # we would have to guess our primary key, but doing so smells of
        # pitfalls. So we have to ensure main_step is properly dealt with
        # afterwards in our insert and update wrappers below.
    from_date        => $MANDATORY,
    priority         => { %$MANDATORY, data_type => 'INTEGER' },
    open_since       => { %$OPTIONAL,  data_type => 'INTEGER' },
    archived_because => $OPTIONAL, # enum ('COMPLETE', 'PAUSED', 'CANCELLED')
    archived_ts      => $OPTIONAL,
    repeat_from      => $OPTIONAL,
    repeat_until     => $OPTIONAL, 
    frequency        => $OPTIONAL,
    client           => $OPTIONAL,
);

__PACKAGE__->belongs_to( user_row => 'FTM::FlowDB::User',
    { 'foreign.id' => 'self.user' }
);

__PACKAGE__->has_many( steps => 'FTM::FlowDB::Step',
    { 'foreign.task' => 'self.ROWID' },
    { cascade_copy => 1, cascade_delete => 1 },
);

__PACKAGE__->has_many(
    timestages => 'FTM::FlowDB::TimeStage',
    { 'foreign.task_id' => 'self.ROWID' }
);

__PACKAGE__->set_primary_key( 'ROWID' );

my @proxy_fields = qw(description done checks expoftime_share substeps);

__PACKAGE__->belongs_to( main_step_row => 'FTM::FlowDB::Step',
    { 'foreign.ROWID' => 'self.main_step'},
    { proxy => \@proxy_fields, } # wherefore this: cascade_update => 1 ?
);

sub _extract_proxy {
    my $args = shift;
    my %main_step_data;
    for my $pf ( @proxy_fields ) {
        next if !exists $args->{$pf};
        $main_step_data{$pf} = delete $args->{$pf}
    }
    return \%main_step_data;
}

around new => sub {
    my ($orig, $class) = (shift, shift);    
    my $args = @_ > 1 ? {@_} : shift // {};
    my $main_step = _extract_proxy($args);
    my $self = $class->$orig($args);
    $self->main_step_row($self->new_related(
        steps => $main_step,
    ));
    return $self;
};

around insert => sub {
    my ($orig, $self) = @_;
    my $cache = $self->_multirel_cache();
    if ( $self->_is_main ) {
        my $msr = $self->main_step_row // croak "Main row missing";
        $self->main_step_row(undef);
        $self->$orig();
        $msr->insert();
        $self->update({'main_step_row' => $msr });
    }
    else {
        $self->$orig();
    }
    $self->store_multirel_cache($cache);
};

around update => sub {
    my ($orig, $self) = (shift, shift);
    my $args = @_ % 2 ? shift // {} : {@_};
    my $main_step_data = _extract_proxy( $args );
    my $cache = $self->_multirel_cache();
    $self->$orig($args);
    if ( $cache ) {
        $self->store_multirel_cache($cache);
    }
    if ( $self->_is_main ) {
        $main_step_data->{name} = q{};
        $self->main_step_row->update($main_step_data);
    }
    return $self;
};

around copy => sub {
    my ($orig, $self, $args) = @_;
    ( $args //= {} )->{main_step} = undef;
   
    my $name = $self->name;
    my $msr = $self->main_step_row;
    my $c = $self->$orig($args);
    if ( $msr->task eq $name ) {
        $c->update({ main_step_row => $c->steps->find({ name => q{} }) });
    }
    else {
        $_->copy({ task => $c->ROWID }) for $msr->and_below;
    }

    return $c;

};


for my $acc ( 'timestages' ) {
    around $acc => sub {
        my ($orig, $self, $aref) = (shift, shift, @_);
        my $cache = $self->_multirel_cache;
        die "No cache" if !$cache;
        if ( ref $aref eq 'ARRAY' ) {
            return $cache->{$acc} = $aref;
        }
        elsif ( @_ ) {
            push @{ $cache->{$acc} //= [undef] }, @_;
        }
        else {
            return $cache->{$acc} // $self->$orig();
        }
    }
}

sub store_multirel_cache {
    my ($self, $cache) = @_;
    while ( my ($acc, $value) = each %$cache ) {
        if ( defined $value->[0] ) {
            $self->related_resultset($acc)->delete;
        }
        else {
            shift @$value;
        }
        substr $acc, 0, 0, "add_to_";
        $self->$acc($_) for @$value;
    }
    %$cache = ();
    return 1;
}

sub sqlt_deploy_hook {
   my ($self, $sqlt_table) = @_;

   $sqlt_table->add_index(
        name => 'user_task',
        fields => ['user', 'name'],
        type => 'unique'
   );
   $sqlt_table->add_index(
        name => 'task_mainstep',
        fields => ['main_step'],
        type => 'unique'
   );

}

{
my %_properties;
foreach my $col ( __PACKAGE__->columns ) {
     $_properties{$col} = 'column';
}
foreach my $rel ( 'timestages' ) { # TODO add later: tags annotations ...
     $_properties{$rel} = 'multirel';
}
delete $_properties{ROWID};

sub list_properties {
    my ($self, $sort) = @_;
    return keys %_properties if !$sort;
    return grep { $_properties{$_} eq $sort } keys %_properties;
}}

# DBIx::Class accessors of type 'multi' pass any arguments through to
# search_related. As we search with $self->$acc->search({ ... }), we prefer
# having a read write accessor instead:
# 
  
for my $acc ( list_properties(undef, 'multirel') ) {
    around $acc => sub {
        my ($orig, $self, $aref) = (shift, shift, @_);
        my $cache = $self->_multirel_cache;
        die "No cache" if !$cache;
        if ( ref $aref eq 'ARRAY' ) {
            return $cache->{$acc} = $aref;
        }
        elsif ( @_ ) {
            push @{ $cache->{$acc} //= [undef] }, @_;
        }
        else {
            return $cache->{$acc} // $self->$orig();
        }
    }
}

    
for my $acc ( list_properties() ) {
    { no strict 'refs'; *{"own_".$acc} = \&{$acc}; }
    around $acc => sub {
        my ($orig, $self, @args) = @_;
        if ( @args ) { $self->$orig(@args); }
        else {
            my @val = wantarray # retain calling context
                    ? $self->$orig()
                    : scalar( $self->$orig() ) // ();
            if ( @val ) { return splice @val; } 
            elsif ( my $upper = $self->_upper_subtask_row ) {
                return $upper->$acc;
            }
            else { return }
        }
    };
}
       
sub _is_main {
    my ($self) = @_;
    if ( defined $self->user ) {
        return 1 if length $self->name;
        croak "Task has no name";
    }
    else {
        croak "Subtask may not have a name"
            if !defined $self->name;
        croak "Subtask has no main_row with parent"
            if !defined $self->main_step_row->parent;
        croak "Subtask has no assigned upper subtask or task"
            if !$self->_upper_subtask_row;
        return 0;
    }
}

1;

__END__

=head1 NAME

FTM::FlowDB::Task - Interface to the raw data stored to tasks

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 COPYRIGHT

(C) 2012-2014 Florian Hess

=head1 LICENSE

This file is part of FlowTiMeter.

FlowTiMeter is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowTiMeter is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowTiMeter. If not, see <http://www.gnu.org/licenses/>.


