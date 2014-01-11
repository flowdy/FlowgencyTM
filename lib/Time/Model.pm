#!perl
use strict;

package Time::Model;
use Moose;
use Carp qw(carp croak);
use Date::Calc;
use Time::Profile;

has _time_profiles => (
    is => 'ro',
    isa => 'HashRef[Time::Profile]',
    traits => [ 'Hash' ],
    default => sub { {} },
    handles => { time_profile => 'get' },
);

sub from_json {
    use Util::GraphChecker;
    use JSON ();

    my $class = shift;

    my $model = JSON::from_json(shift, { relaxed => 1 });

    my (%tprofiles,$next_round_promise);

    my $grch = Util::GraphChecker->new( axes => {
        parents => sub {
            my ($parent, $child) = @_;
            push @{$parent->{children}}, $child;
        },
        children => sub {
            my ($child, $parent) = @_;
            push @{$child->{parents}}, $parent;
        }
    });

    my %alias = ( from => 'from_date', until => 'until_date' );

    PROP: while ( my ($key, $props) = each %$model ) {

        my $parent = $props->{parent};
        if ( defined($parent) && !ref($parent) ) {
            if ( defined $tprofiles{$parent} ) {
                $props->{parent} = $tprofiles{$parent};
                $next_round_promise++;
            }
            else {
                # dies if circular dependencies are detected
                $grch->declare( $key => parents => $parent );
                next PROP;
            }
        }

        my ($to_suggest, $to_impose);
        if ( $parent ) {
            ($to_suggest, $to_impose) = $parent->inherit_variations(
                 $props->{variations}
            );
        }
    
        if ( my $mode = $props->{inherited_variations_all} ) {
            if ( $mode eq 'optional' ) {
                (@$to_suggest, @$to_impose) = ();
            }
            elsif ( $mode eq 'suggest' ) {
                # append @to_impose to @to_suggest & empty the former
                (@$to_suggest, @$to_impose) = (@$to_suggest, @$to_impose);
            }
            elsif ( $mode eq 'impose' ) {
                # prepend @to_suggest to @to_impose & empty the former
                (@$to_impose, @$to_suggest) = (@$to_suggest, @$to_impose);
            }
            else { die "unsupported inherited_variations_all mode: $mode!" }
        }

        foreach my $v ( @{ $props->{variations} } ) {

            while ( my ($key, $alias) = each %alias ) {
                $v->{$alias} = $_ if $_ = delete $v->{$key};
            }

            if ( $v->{obj} || $v->{week_pattern} ) {}
            elsif ( defined(my $tp = $tprofiles{$v->{ref}}) ) { 
                next if $v->{ignore} || !$v->{apply};
                $next_round_promise++;
                $v = $tp->get_section( $v->{from_date}, $v->{until_date} );
                1;
            }
            else {
                # dies if circular dependencies are detected
                $grch->declare( $key => parents => $v->{ref} );
                next PROP;
            }

        }
        
        delete $model->{$key};
    
        my $tprof = Time::Profile->new(
            $props->{pattern} // $parent->fillIn->description
        );

        $tprofiles{ $key } = $tprof;

        for my $v ( @$to_suggest, @{$props->{variations}}, @$to_impose ) {
            next if !(blessed($v) || $v->{reuse} || $v->{week_pattern});
            $tprof->respect($v);
        }
                       
    }
    
    if ( %$model ) {
        if ( $next_round_promise ) {
            $next_round_promise=0;
            goto PROP;
        }
        else {
            die "Time profile definitions with irresoluble dependencies: ",
               join ", ", keys $model;
        }
    }

    return $class->new( _time_profiles => \%tprofiles );

}

__PACKAGE__->meta->make_immutable;

1;
