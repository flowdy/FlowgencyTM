use strict;

package FlowgencyTM::Server::TaskEditor;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use Mojo::JSON qw(from_json encode_json);
use Carp qw(croak);

sub form {
    my $self = shift;
    my $task; 

    my $args = {};

    if ( defined( my $lazystr = $self->param('lazystr') ) ) {
        $args->{lazystr} = $lazystr;
        $self->stash( incr_prefix => 0 );
    }
    elsif ( my $id = $self->_get_task ) {
        $args->{task} = $id;
    }

    $self->render(
        FlowgencyTM::user->get_task_data($args),
        bare => $self->param('bare')
    );

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
    my $self = shift;
    my $task = $self->_get_task;
    $self->render( details => FlowgencyTM::user->open_task({ id => $task }) );
}

sub fast_bulk_update {
    my $self = shift;

    my (%data, %errors, $status);
    for my $task (@{ $self->req->params->names }) {

        my $data = $self->param($task);

        $data{$task} = from_json $data;

    }

    try {
        $errors{ $_ } = q{} for FlowgencyTM::user->fast_bulk_update(\%data); 
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

sub _get_task {
    my $self = shift;
    my $id = $self->stash('id');
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
