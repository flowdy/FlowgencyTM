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
    my ($task, %res, @res_tasks); 
    my $args = {};
    my $new_flag = $self->stash('new') // '';
    my $lazystr = $self->req->content_type eq 'text/plain'
        ? $self->req->body
        : $self->param('lazystr')
        ;
    my $step = $self->stash('step');

    if ( $self->req->method eq 'GET' ) {

        if ( defined $lazystr ) {
            $args->{lazystr} = $lazystr;
            $self->stash( incr_prefix => 1 );
        }
        elsif ( my $d = $self->every_param('copy') ) {
            $args->{tasks} = $d;
        }
        else { $args = { task => $task }; }       

        %res = $self->stash("user")->get_task_data($args);

        FTM::Error::ObjectNotFound->throw( type => 'task', name => $task )
            if !$data{data};

        if ( $step ) {
            $step &&= $data{data}{steps}{$step}
                || FTM::Error::ObjectNotFound->throw(
                    type => 'step', name => $step
                );
            $self->render( json => $step );
            return;
        }
        elsif ( $data{data}{ '-next' } ) {
            my $task = $data{data};
            my @tasks = $task;
            while ( my $next = delete $tasks[-1]{ '-next' } ) {
                push @tasks, $next;
            }
            $res{data} = \@tasks;
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
        my $ahref = $ahref->{$id} = decode_json $self->req->body;
        if ( $step ) { $ahref->{step} = $step }
        @{$args}{'-reset','-create'} = ( $self->stash('reset'), $new_flag);
        @res_tasks = $self->stash("user")->fast_bulk_update($args);
    }

    else {
        croak "Server::TaskEditor::form(): general call error";
    }

    if ( @res_tasks ) {
        %res = $self->stash("user")->get_task_data({ tasks => \@res_tasks });
    }
    
    if ( $$self->accept('', 'json')
      || index( $self->req->content_type, '/json' ) > 0
    ) {
        $self->render( json => \%res );
    }
    else {
        $self->render( %res, bare => $self->param('bare') );
    }

    return;

}

sub post {
    #
    # OBSOLETE:
    #
    # my $self = shift;
    # my $task = $self->_get_task;
    # my $sub = $task ? sub { $_->{oldname} = $task->name } : sub {};

    # my $tfls = $self->param('tfls');
    # try { _parser->( $tfls, $sub ); }
    # catch {
    #      my $e = shift;
    #      $self->render(
    #          action => 'form', message => $e, input => $tfls,
    #          FlowgencyTM::user->get_task_data($task)
    #      );
    #      0;
    # } or return;

    # $self->redirect_to('home');
    #
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
    $self->render( details => $open );
}

sub fast_bulk_update {
    my $self = shift;

    my ($data, %errors, $status);
    my $ct = $self->req->content_type;
    if ( $ct eq 'text/plain' ) {
        my $count;
        for my $t ( $self->_parser( -dry => 1 )->($self->req->body) ) {
            $data->{ $t->{name} || ( '_NEW_TASK_' . ++$count ) } = $t;
        }
    }
    elsif ( $ct eq 'application/json' ) {
        $data = decode_json $self->req->body;
    }
    elsif ( $ct eq 'application/x-www-form-urlencoded' ) {
        for my $task (@{ $self->req->params->names }) {
            my $tdata = $self->param($task);
            $data->{$task} = from_json $tdata;
        }
    }
    else {
        FTM::Error::->throw(
            "fast_bulk_update called "
            . ( $ct ? "with unsupported type of request body content: $ct"
                    : "without mandatory request body content"
            )
        )
    }

    if ( $self->req->method eq 'PATCH' ) {
        $data->{ '-create' } = 0;
    }

    try {
        $errors{ $_ } = q{} for FlowgencyTM::user->fast_bulk_update($data); 
    }
    catch {
        if ( ref $_ eq 'FTM::Error::Task::MultiException' ) {
            %errors = %{ $_->all };
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

    my $dynamics = FlowgencyTM::user->get_dynamics_of_task({ id => $task });

    $self->render( %$dynamics );
}

sub purge {
  # DELETE /tasks/:name
  # DELETE /tasks/:name/steps/:step
    my $self = shift;
    my $task = $self->get_task;
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

sub _markdown {
    my ($text, %opts) = @_;
    
    return $text if !eval "require Text::Markdown";

    if ( my $add = $opts{incr_heading_level} ) {
        my $h = '#' x $add;
        $text =~ s{ ^ (\#+) }{$h.$1}egxms;
        $text =~ s{ ^ ([^\n]+) \n ([=-])\2+ }
                  { $h .( $2 eq '-' ? '##' : '#' ).' '.$1 }egxms;
    }

    return Text::Markdown::Markdown($text);
}

1;
