use strict;

package FlowgencyTM::Server::TaskList;
use Mojo::Base 'Mojolicious::Controller';
use List::Util qw(first);
use Carp qw(croak);

sub todos {
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
    $tasks->{timestamp} //= FTM::Time::Spec->now;
  
    $self->res->headers->cache_control('max-age=1, no-cache');
    $self->render(
        %$tasks,
        force_include => \@force_include,
    );

    return;
}

sub dump_all {
  # GET /tasks
    my $self = shift;
    my $dump = $self->stash("user")->get_task_data();
    $self->render( json => $dump );
}

sub single {
  # GET /todo/:name
    my $self = shift;
    
    my $id = $self->_get_task;
    my $user = $self->stash("user");

    my %args;
    for my $p_name (@{ $self->req->params->names }) {
        $args{$p_name} = $self->param($p_name);
    }
    $args{force_include} = $id;
    my $render_data = $user->get_ranking(\%args);
    my $list = $render_data->{list};
    my $task = first { $_->{name} eq $id } @$list;
    FTM::Error::ObjectNotFound->throw(
            type => 'task', name => $id
    ) if !$task;
    @$list = $task;
    $self->respond_to( json => $task, html => $render_data );

    return;

}
1;
