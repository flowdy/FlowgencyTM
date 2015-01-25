package FlowgencyTM::Server::Admin;
use Mojo::Base 'Mojolicious::Controller';

sub dash {
    my $self = shift;
    my $mailoop = FlowgencyTM::database->resultset("User")
        ->search(
              { 'mailoop.type' => { '!=' => undef } },
              { join => 'mailoop' }
          );

    $self->stash(mailoop => $mailoop);
}

1;
