package FlowgencyTM::Server::Admin;
use Mojo::Base 'Mojolicious::Controller';
use Carp qw(croak);

sub dash {
    my $self = shift;
    my $mailoop = FlowgencyTM::database->resultset("User")
        ->search(
              { 'mailoop.type' => { '!=' => undef } },
              { join => 'mailoop' }
          );

    $self->stash(mailoop => $mailoop);
}

sub view_user {
    my $self = shift;
    my $user = FlowgencyTM::database->resultset("User")->find(
        $self->param("id") // croak "No param 'id' defined"
    );
    $self->stash( admined_user => $user );
}

sub invite {
    my $self = shift;
    my $user = FlowgencyTM::database->resultset("User")->find(
        $self->param("id") // croak "No param 'id' defined"
    );
    $user->mailoop->delete;
}

sub reset_password {
    my $self = shift;
    my $user = FlowgencyTM::database->resultset("User")->find(
        $self->param("id") // croak "No param 'id' defined"
    );
    for my $ml ( $user->mailoop ) {
        $user->password($ml->value);
        $ml->delete;
    }
}

sub change_email {
    my $self = shift;
    my $user = FlowgencyTM::database->resultset("User")->find(
        $self->param("id") // croak "No param 'email' defined"
    );
    for my $ml ( $user->mailoop ) {
        $user->email($ml->value);
        $ml->delete;
    }
}

1;
