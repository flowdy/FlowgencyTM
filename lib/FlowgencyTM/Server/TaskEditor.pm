use strict;

package FlowgencyTM::Server::TaskEditor;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use Mojo::JSON qw(from_json encode_json);
use Carp qw(croak);

sub form {
  # GET /newtask, stash: incr_prefix => 1
  # POST /newtask, stash: new => 'task'
  # PATCH /tasks/:name, stash: new => 0
  # GET /tasks/:name
  # PUT /tasks/:name, stash: reset => 1
  # POST /tasks/:name/form, stash: new => 0
  # POST /tasks/:name/steps, stash: new => 'step'
  # PUT /tasks/:name/steps/:step, stash: reset => 1
  # PATCH /tasks/:name/steps/:step, stash: new => 0

    my $self = shift;
    my $args = {};
    my $new_flag = $self->stash('new') // '';

    my $lazystr
        = ($self->req->headers->content_type//q{}) eq 'text/plain'
        ? $self->req->body : $self->param('lazystr');

    my $step = $self->stash('step');

    my ($task, %res, @res_tasks); 

    if ( $self->req->method eq 'GET' ) {

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

        %res = $self->stash("user")->get_task_data($args);

        FTM::Error::ObjectNotFound->throw( type => 'task', name => $task )
            if %$args && !$res{presets};

        if ( $step ) {
            $step = $res{presets}{steps}{$step}
                || FTM::Error::ObjectNotFound->throw(
                    type => 'step', name => $step
                );
            $self->render( json => $step );
            return;
        }

    }

    elsif ( $new_flag eq "task" ) {
        $args = $lazystr ? { _NEW_TASKS => $lazystr } : do {
            my $tasks = decode_json $self->req->body;
            my (%tasks, $count);
            for my $t ( ref $tasks eq 'ARRAY' ? @$tasks : $tasks ) {
                $tasks{ ( '_NEW_TASK_' . ++$count ) } = $t;
            }
            \%tasks;
        };
        $args->{ '-create' } = 1; 
        @res_tasks = $self->stash("user")->fast_bulk_update($args);
    }

    elsif ( my $id = $self->_get_task ) {
        my $ahref = $args->{$id} = decode_json $self->req->body;
        if ( $step ) { $ahref->{step} = $step }
        @{$args}{'-reset','-create'} = ( $self->stash('reset'), $new_flag);
        @res_tasks = $self->stash("user")->fast_bulk_update($args);
    }

    else {
        croak "Server::TaskEditor::form(): missing task name";
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

sub fast_bulk_update {
    my $self = shift;

    my ($data, %errors, $status);
    my $ct = $self->req->headers->content_type;
    if ( index( $ct, 'text/plain' ) == 0 ) {
        my $count;
        for my $t ( $self->_parser( -dry => 1 )->($self->req->body) ) {
            $data->{ $t->{name} || ( '_NEW_TASK_' . ++$count ) } = $t;
        }
    }
    elsif ( index($ct, 'application/json') > -1 ) {
        $data = decode_json $self->req->body;
    }
    elsif ( index($ct, 'application/x-www-form-urlencoded') == 0 ) {
        for my $task (@{ $self->req->params->names }) {
            my $tdata = $self->param($task);
            $data->{$task} = from_json $tdata;
        }
    }
    else {
        FTM::Error::->throw(
            http_status => 400,
            message =>
                "fast_bulk_update called " . (
                    $ct ? "with unsupported type of request body content: $ct"
                        : "without mandatory request body content"
                )
        )
    }

    $self->app->log->debug(
        "fast_bulk_update got following data to process: " . encode_json($data)
    );

    if ( $self->req->method eq 'PATCH' ) {
        $data->{ '-create' } = 0;
    }

    try {
        $errors{ $_ } = q{} for FlowgencyTM::user->fast_bulk_update($data); 
    }
    catch {
        if ( ref $_ eq 'FTM::Error::Task::MultiException' ) {
            %errors = %{ $_->all };
            while ( my ($task, $e) = each %errors ) {
                $self->app->log->error("Form processing failed for task $task: '$e'");
            }
            for my $e ( values %errors ) {
                $e = $e->can('message') ? $e->message : "$e" if ref $e;
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
        $dynamics = $dynamics->{$o} // FlowgencyTM::ObjectNotFound->throw(
            "Analysis aspect not known: $o"
        );
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
