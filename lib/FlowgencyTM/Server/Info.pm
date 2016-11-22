use strict;

package FlowgencyTM::Server::Info;
use Mojo::Base 'Mojolicious::Controller';

sub basic {
    my ($self) = @_;
    $self->stash(
        version => $FlowgencyTM::VERSION,
        commit_id => qx{git rev-list -1 HEAD} // "(unretrievable?)",
        changes => scalar qx{git diff-index --shortstat HEAD},
        server_started => FlowgencyTM::Server::get_started_time(),
    );
}

1;
