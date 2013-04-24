#!perl
use strict;

package Time::Scheme;
use Moose;
use Carp qw(carp croak);
use Date::Calc;
use Time::Line;

has _timelines => (
    is => 'ro',
    isa => 'HashRef[Time::Line]',
    default => sub { {} },
    handles => [ 'get' ],
);

sub add_timeline {
    my $self = shift;
    my $args = ref $_[0] ? $_[0] : @_;
}

sub from_json {

    use Util::GraphChecker;
    use JSON qw(from_json);

    my $scheme = from_json;
    my (%tlines,$next_round_promise);

    my $grch = GraphChecker->new( axes => {
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

    PROP: while ( my ($key, $props) = each %$scheme ) {

        my $parent = $props->{parent};
        if ( defined($parent) && !ref($parent) ) {
            if ( defined $tlines{$parent} ) {
                $props->{parent} = $tlines{$parent};
                $next_round_promise++;
            }
            else {
                # dies if circular dependencies are detected
                $grch->declare( $key => parents => $parent );
                next PROP;
            }
        }

        my %explicitly_varied_by;

        foreach my $v ( @{ $props->{variations} } ) {

            while ( my ($key, $alias) = each %alias ) {
                $v->{$alias} = $_ if $_ = delete $v->{$key};
            }

            if ( blessed($v) ) {}
            elsif ( $parent and my $var = $parent->get_variation($v->{ref}) ) {
                $v = Time::Span->new( base_variation => $var, %$var, %$v );
            }
            elsif ( defined(my $tl = $tlines{$v->{ref}}) ) { 
                next if $v->{ignore};
                $next_round_promise++;
                $v = $tl->get_section( $v->{from}, $v->{until} );
            }
            elsif ( $v->{week_pattern} ) {
                $v = Time::Span->new(%$v, variation => $v);
            }
            else {
                # dies if circular dependencies are detected
                $grch->declare( $key => parents => $v->{ref} );
                next PROP;
            }

            $explicitly_varied_by{ refaddr $v->line // $v->base_variation } = 1; 
        }
        
        delete $scheme->{$key};
    
        my (@to_suggest, @to_impose);
        if ( $parent ) {
            @to_suggest = $parent->variations_to_suggest(\%explicitly_varied_by);
            @to_impose  = $parent->variations_to_impose(\%explicitly_varied_by);
        }
    
        if ( my $mode = $props->{inherited_variations_mode} ) {
            if ( $mode eq 'optional' ) {
                (@to_suggest, @to_impose) = ();
            }
            elsif ( $mode eq 'suggest' ) {
                # append @to_impose to @to_suggest & empty the former
                (@to_suggest, @to_impose) = (@to_suggest, @to_impose);
            }
            elsif ( $mode eq 'impose' ) {
                # prepend @to_suggest to @to_impose & empty the former
                (@to_impose, @to_suggest) = (@to_suggest, @to_impose);
            }
            else { die "unsupported inherited_variations_all mode: $mode!" }
        }

        my $tline = Time::Line->new(
            fillIn => Time::Span->new(
                week_pattern => $props->{pattern},
                from => 1, until => 1,
                     # 1 = first of current month
                     # (doesn't matter, dynamically adjusted anyway)
            ),
        );

        for my $v ( @to_suggest, @{$props->{variations}}, @to_impose ) {
            next if !blessed($v);
            $tline->respect($v);
        }
                       
        $tlines{ $key } = $tline;

    }
    
    if ( %$scheme ) {
        if ( $next_round_promise ) {
            $next_round_promise=0;
            goto PROP;
        }
        else {
            die "Timeline definitions with irresoluble dependencies: ",
               join ", ", keys $scheme;
        }
    }

    return $class->new( _timelines => \%tlines );

}

__PACKAGE__->meta->make_immutable;

1;
