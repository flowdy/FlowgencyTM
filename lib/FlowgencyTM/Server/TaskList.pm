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

sub all {
  # GET /tasks
    my $self = shift;
    my %args = (map({ $_ => 1 } qw/desk tray archive/), drawer => 3 );
    my $list = $self->stash("user")->get_ranking(\%args);

    my %tasks;
    while ( my $t = shift @$list ) {
        next if !ref $t;
        $tasks{ $t->{name} } = $t;
    }

    $self->render( json => \%tasks );
}

sub single {
  # GET /tasks/:name
  # GET /tasks/:name/steps/:step
    my $self = shift;
    
    my $id = $self->_get_task;
    my $user = $self->stash("user");

    if ( my $step = $self->stash('step') ) {
        my $task = $user->get_task_data({ task => $id })
            or FTM::Error::ObjectNotFound->throw(
                message => "Could not find a task '$task'", http_status => 404
            );
        $step = $task->{step}{$step}
            || FTM::Error::ObjectNotFound->throw(
                message => "Could not find a step '$step'", http_status => 404
            );
        $c->render( json => $step );
    }    
    else {
        my %args;
        for my $p_name (@{ $self->req->params->names }) {
            $args{$p_name} = $self->param($p_name);
        }
        $args{force_include} = $id;
        my $render_data = $user->get_ranking(\%args);
        my $list = $render_data->{list};
        my $task = first({ $_->{name} eq $id } @$list)
            // FTM::Error::ObjectNotFound->throw(
                message => "Could not find a $task", http_status => 404
            );
        @$list = $task;
        $c->respond_to( json => $task, html => $render_data );
    } 

    return;
}
1;
