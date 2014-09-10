
use strict;

package FlowDB::Task;
use Carp qw/croak/;
use Moose;
extends 'DBIx::Class::Core';

my ($MANDATORY, $OPTIONAL) = map { { is_nullable => $_ } } 0, 1;

has _multirel_cache => (
    is => 'ro',
    isa => 'HashRef',
    default => sub {{}},
    lazy => 1, # does not work without with DBIx::Class
);

__PACKAGE__->table('task');
__PACKAGE__->add_column( ROWID => { data_type => 'INTEGER' });
__PACKAGE__->add_columns(
    user             => $MANDATORY,
    name             => $MANDATORY,
    title            => $MANDATORY,
    main_step        => $OPTIONAL,
        # It's not really, but otherwise we would run into circular reference problems:
        # Because steps (like main_step) have a foreign key constraint matching our
        # autoincremented primary key, the task record must be inserted first.
        # By deferring the step-side foreign key check, we would have to guess our primary
        # key, but doing so smells of pitfalls. So we have to ensure main_step is properly
        # dealt with in our insert and update wrappers.
    from_date        => $MANDATORY,
    priority         => { %$MANDATORY, data_type => 'INTEGER' },
    archived_because => $OPTIONAL, # enum ('COMPLETE', 'PAUSED', 'CANCELLED')
    archived_ts      => $OPTIONAL,
    repeat_from      => $OPTIONAL,
    repeat_until     => $OPTIONAL, 
    frequency        => $OPTIONAL,
    client           => $OPTIONAL,
);

__PACKAGE__->belongs_to( user_row => 'FlowDB::User',
    { 'foreign.id' => 'self.user' }
);

__PACKAGE__->has_many( steps => 'FlowDB::Step',
    { 'foreign.task' => 'self.ROWID' },
    { cascade_copy => 1, cascade_delete => 1 },
);

__PACKAGE__->has_many(
    timestages => 'FlowDB::TimeStage',
    { 'foreign.task_id' => 'self.ROWID' }
);

__PACKAGE__->set_primary_key( 'ROWID' );

my @proxy_fields = qw(description done checks expoftime_share substeps);

__PACKAGE__->belongs_to( main_step_row => 'FlowDB::Step',
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
    my $msr = $self->main_step_row;
    $self->main_step_row(undef);
    my $cache = $self->_multirel_cache();
    $self->$orig();
    $self->store_multirel_cache($cache);
    $msr->insert();
    $self->update({'main_step_row' => $msr });
};

around update => sub {
    my ($orig, $self) = (shift, shift);
    my $args = @_ % 2 ? shift // {} : {@_};
    my $main_step_data = _extract_proxy( $args );
    my $cache = $self->_multirel_cache();
    $main_step_data->{name} = q{};
    $self->$orig($args);
    if ( $cache ) {
        $self->store_multirel_cache($cache);
    }
    $self->main_step_row->$orig($main_step_data);
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

# DBIx::Class accessors of type 'multi' pass any arguments through to search_related.
# As we search with $self->$acc->search({ ... }), we would rather have a read write accessor
# instead:

for my $acc ( 'timestages' ) {
    around $acc => sub {
        my ($orig, $self, $aref) = (shift, shift, @_);
        my $cache = $self->_multirel_cache;
        #if ( !defined $cache ) {
        #    $self->_multirel_cache($cache = {});
        #}
        die "No cache" if !$cache;
        if ( ref $aref eq 'ARRAY' ) {
            return $cache->{$acc} = $aref;
        }
        elsif ( @_ ) {
            return $self->$orig(@_);
        }
        else {
            return $cache->{$acc} // $self->$orig();
        }
    }
}

sub store_multirel_cache {
    my ($self, $cache) = @_;
    while ( my ($acc, $value) = each %$cache ) {
        $self->related_resultset($acc)->delete;
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

1;

