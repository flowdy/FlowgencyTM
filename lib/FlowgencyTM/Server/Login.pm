use strict;

package FlowgencyTM::Server::Login;
use FlowgencyTM;
use Mojo::Base 'Mojolicious::Controller';

sub form {}

sub token {
    my $self = shift;

    my $user_id = $self->param('user');
    my $password = $self->param('password');
    my $user = FlowgencyTM::database->resultset("User")->find($user_id);

    if ( $user && $user->password_equals($password) ) {
        $self->session("user_id" => $user_id);
        $self->redirect_to("home");
    }
    else {
        $self->render(template => 'login/form', retry => 1 );
        return;
    }


}

1;
