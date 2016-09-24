use strict;

package FlowgencyTM::Server::Ranking;
use Mojo::Base 'Mojolicious::Controller';
use Carp qw(croak);

sub list {
    my $self = shift;
  
    my %args;
    for my $p_name (@{ $self->req->params->names }) {
        $args{$p_name} = $self->param($p_name);
    }
  
    if ( $args{keep} && $self->stash('is_remote') ) {
        croak 'Cannot set time in remote mode – Would affect other users, too.';
    }
  
    my @force_include = split q{,}, $args{force_include};
    $args{force_include} = \@force_include;
  
    my $tasks = $self->stash('user')->get_ranking( \%args );
  
    if ( $self->accepts('', 'json') ) {
        $self->render( json => $tasks );
    }
    else {  
        $self->res->headers->cache_control('max-age=1, no-cache');
        $self->render(
            %$tasks,
            force_include => \@force_include,
        );
    }

    return;
}

1;
