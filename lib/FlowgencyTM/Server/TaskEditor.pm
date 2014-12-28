use strict;

package FlowgencyTM::Server::TaskEditor;
use FlowgencyTM;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use Mojo::JSON qw(from_json encode_json);
use Carp qw(croak);

sub form {
    my $self = shift;
    my $task = $self->_get_task;

    $self->render( _task_dumper($task), bare => $self->param('bare') );

}

sub _task_dumper {
    my ($task, $steps) = shift;

    if ( $task ) {
        $steps = { map { $_->name => $_->dump } $task->main_step_row, $task->steps };
    }

    my $priodir = FlowgencyTM::user->get_labeled_priorities;
    my $priocol = FlowgencyTM::user->tasks->task_rs
        ->search({ archived_because => undef })->get_column('priority');
    @{$priodir}{'_max','_avg'} = ($priocol->max, $priocol->func('AVG') );

    return
        steps => $steps, _priodir => $priodir,
        tracks => [ FlowgencyTM::user->get_available_time_tracks ],
}

my $parser = FlowgencyTM::user->tasks->get_tfls_parser;
sub post {
    my $self = shift;
    my $task = $self->_get_task;
    my $sub = $task ? sub { $_->{oldname} = $task->name } : sub {};

    my $tfls = $self->param('tfls');
    try { $parser->( $tfls, $sub ); }
    catch {
         my $e = shift;
         $self->render(
             action => 'form', message => $e, input => $tfls,
             _task_dumper($task)
         );
         0;
    } or return;

    $self->redirect_to('home');
}

sub open {
    my $self = shift;
    my $task = $self->_get_task;
    $task->open;
    $self->render( details => { focus => [ $task->current_focus ] } );
}

sub fast_bulk_update {
    my $self = shift;

    my $log = Mojo::Log->new();

    for my $task ( $self->param() ) {

        my $data = $self->param($task);
        $log->info("For task $task update: $data");

        my $is_new = $task =~ s/^_NEW_TASK_\d+$//;
        $_ = from_json $_ for $data;

        my $method = $is_new ? 'add'
                   : $data->{incr_name_prefix} ? 'copy'
                   : 'update';

        $data->{step} //= '';

        $task = FlowgencyTM::user->tasks->$method($task || (), $data);

    }

    $self->rendered(204); # no content
        
}

sub _get_task {
    my $self = shift;
    my $id = $self->stash('id');
    return if !$id;
    return FlowgencyTM::user->tasks->get($id) // croak "No task $id";
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

