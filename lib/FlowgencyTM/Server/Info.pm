use strict;

package FlowgencyTM::Server::Info;
use FlowgencyTM;
use Mojo::Base 'Mojolicious::Controller';

sub basic {
    my ($self) = @_;
    $self->stash(
        version => $FlowgencyTM::VERSION,
        commit_id => qx{git rev-list -1 HEAD},
        changes => qx{git diff-index --shortstat HEAD},
        server_started => scalar localtime(time),
    );
}

1;
