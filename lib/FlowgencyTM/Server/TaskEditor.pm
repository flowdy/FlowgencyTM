use strict;

package FlowgencyTM::Server::TaskEditor;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use Mojo::JSON qw(from_json encode_json decode_json);
use Encode qw(decode_utf8);
use Carp qw(croak);

sub form {
  # GET /task-form, stash
  # POST /task-form, stash

    my $self = shift;
    my $args = {};

    my $lazystr
        = ($self->req->headers->content_type//q{}) eq 'text/plain'
        ? $self->req->body : $self->param('lazystr');

    my ($task, %res, @res_tasks); 

    my $t = $self->every_param('copy');

    if ( defined $lazystr ) {
        $args->{lazystr} = $lazystr;
        $self->stash( incr_prefix => 1 );
    }
    elsif ( @$t ) {
        $args->{tasks} = $t;
    }
    elsif ( $t = $self->_get_task ) {
        $args->{task} = $t;
    }
    else {
        $self->stash( incr_prefix => 1 );
    }

    %res = $self->stash("user")->get_task_data($args);

    if ( %$args && !$res{presets} ) {
        my $e = FTM::Error::ObjectNotFound->new(
            type => 'task', name => $task
        );
        $self->reply->client_error($e);
        return;
    }

    if ( $self->stash("is_restapi_req") ) {
        $self->render( json => \%res );
    }
    else {
        $self->render( %res, bare => $self->param('bare') );
    }

    return;

}

sub open {
  # GET /tasks/:name/open
  # POST /tasks/:name/open, ensure => 1
  # POST /tasks/:name/close, ensure => 0
    my $self = shift;
    my $task = $self->_get_task;
    my $open = FlowgencyTM::user->open_task({
        id => $task,
        ensure => $self->stash('ensure'),
    });
    $self->render( id => $task, details => $open );
}

sub handle_single {
    my $self = shift;
    $self->stash("is_restapi_req" => 1);
    my $id = $self->_get_task;
    my $step = $self->stash('step');
    my $new = $self->stash('new') // '';
    my $meth = $self->req->method;
    my $commit;
    my $ahref = $commit->{$id} = decode_json $self->req->body;
    if ( $step ) { $ahref->{step} = $step }
    @{$commit}{'-reset','-create'} = ( $self->stash('reset'), $new );
    
    my $user = $self->stash("user");
    try {
        $commit && $user->apply_task_changes($commit);
        my %res = $user->get_task_data({ task => $id });
        my $presets = $res{presets};
        $presets = $presets->{steps}{$step} if $step;
        $self->render( json => $presets );
    }
    catch {
        if ( ref $_ eq 'FTM::Error::Task::MultiException' ) {
            die $_->all->{ $id };
        }
        else {
            die $_;
        }
    }
}

sub handle_multi {
    my $self = shift;
    $self->stash("is_restapi_req" => 1);
    my ($commit, %errors, $status);
    my $ct = $self->req->headers->content_type;
    if ( index( $ct, 'text/plain' ) == 0 ) {
        $commit = { -LAZYSTR => decode_utf8($self->req->body) };
    }
    elsif ( index($ct, 'application/json') > -1 ) {
        $commit = decode_json $self->req->body;
        if ( ref $commit eq 'ARRAY' ) {
            my ($count,%defs);
            for ( @$commit ) {
                $defs{ $_->{name} || ( '_NEW_TASK_' . ++$count ) } = $_;
            }
            $commit = \%defs;
        }
        elsif ( ref $commit eq 'HASH' ) {
            my $ti = $commit->{title};
            if ( $ti and !ref $ti ) {
                $commit = { '_NEW_TASK_0' => $commit }
            }
        }
        else {
            return $self->reply->client_error({
                http_status => 400,
                message =>
                    "Malformed content: expected json data-structure, "
                  . "but got a string"
            });
        }
    }
    elsif ( index($ct, 'application/x-www-form-urlencoded') == 0 ) {
        for my $task (@{ $self->req->params->names }) {
            my $tdata = $self->param($task);
            $commit->{$task} = from_json $tdata;
        }
    }
    else {
        return $self->reply->client_error({
            http_status => 400,
            message =>
                "fast_bulk_update called " . (
                    $ct ? "with unsupported type of request body content: $ct"
                        : "without mandatory request body content"
                )
        });
    }

    $self->app->log->debug(
        "fast_bulk_update got following data to process: " . encode_json($commit)
    );

    if ( $self->req->method eq 'PATCH' ) {
        $commit->{ '-create' } = 0;
    }

    try {
        $errors{ $_ } = q{} for FlowgencyTM::user->apply_task_changes($commit); 
    }
    catch {
        if ( ref $_ eq 'FTM::Error::Task::MultiException' ) {
            %errors = %{ $_->all };
            while ( my ($task, $e) = each %errors ) {
                next if !$e->{error};
                for my $e ( values %$e ) {
                    $e = $e->can('message') ? $e->message : "$e" if ref $e;
                    $self->app->log->error(
                        "Form processing failed for task $task: '$e'"
                    );
                    last; # expect hash to contain only one key/value pair
                }
            }
            $status = $_->http_status;
        }
        else {
            die $_;
        }
    };

    $self->render(status => $status // 200, json => \%errors )
        
}

sub analyze {
    my $self = shift;
    my $task = $self->_get_task;

    my $dynamics = FlowgencyTM::user->get_dynamics_of_task({ id => $task,  });

    if ( my $o = $self->param('only') ) {
        $dynamics = $dynamics->{$o};
        $self->reply->client_error({
            error => "ObjectNotFound",
            message => "Analysis aspect not known: $o",
        }) if !$dynamics;
    }

    $self->render(
        $self->stash('is_restapi_req') ? (json => $dynamics) : %$dynamics
    );
}

sub purge {
  # DELETE /tasks/:name
  # DELETE /tasks/:name/steps/:step
    my $self = shift;
    $self->stash("user")->delete_obj({
        task => $self->get_task,
        step => $self->stash("step"),
    });
}

sub _get_task {
    my $self = shift;
    my $id = $self->stash('name');
    return $id;
}

1;
