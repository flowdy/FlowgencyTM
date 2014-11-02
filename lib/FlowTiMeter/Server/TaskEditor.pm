package FlowTiMeter::Server::TaskEditor;
use FlowTiMeter;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;

sub form {
    my $self = shift;
}

my $parser = FlowTiMeter::user->tasks->get_tfls_parser;
sub post {
    my $self = shift;
    my $task = $self->_get_task;
    my $sub = $task ? sub { $_->{oldname} = $task->name } : sub {};

    my $tfls = $self->param('tfls');
    try { $parser->( $tfls, $sub ); }
    catch {
         my $e = shift;
         $self->render( action => 'form', message => $e, input => $tfls );
         0;
    } or return;

    $self->redirect_to('home');
}

sub open {
    my $self = shift;
    my $task = $self->_get_task;
    $task->open;
    $self->render( details => { focus => [ $task->current_focus ] }, format => 'txt' );
}
sub close {
    my $self = shift;
    my $task = $self->_get_task;
    $task->close;
    $self->redirect_to('home');
}

sub _get_task {
    my $self = shift;
    my $id = $self->stash('id');
    return if !length $id;
    return FlowTiMeter::user->tasks->get($id);
}
