use strict;

package FlowgencyTM::Server::TaskEditor;
use FlowgencyTM;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use Mojo::JSON qw(from_json encode_json);
use Carp qw(croak);

sub _parser { FlowgencyTM::user->tasks->get_tfls_parser; }
sub form {
    my $self = shift;
    my $task; 

    if ( defined( my $lazystr = $self->param('lazystr') ) ) {
        $task = _parser->($lazystr)->{task_obj};
        $self->stash( incr_prefix => 0, id => $task->name );
    }
    else { $task = $self->_get_task; }

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

sub post {
    my $self = shift;
    my $task = $self->_get_task;
    my $sub = $task ? sub { $_->{oldname} = $task->name } : sub {};

    my $tfls = $self->param('tfls');
    try { _parser->( $tfls, $sub ); }
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
    $self->render( details => FlowgencyTM::Server::Ranking::extend_open_task($task) );
}

sub fast_bulk_update {
    my $self = shift;

    my $log = Mojo::Log->new();

    my (%errors, $status);
    for my $task (@{ $self->req->params->names }) {

        my $data = $self->param($task);
        $log->info("For task $task update: $data");

        my $is_new = $task =~ s/^_NEW_TASK_\d+$//;
        $_ = from_json $_ for $data;

        my $method = $is_new ? 'add'
                   : $data->{copy} || $data->{incr_name_prefix} ? 'copy'
                   : ($data->{archived_because}//q{}) eq '!PURGE!' ? 'delete'
                   : 'update';

        $data->{step} //= '';

        try {
            $task = FlowgencyTM::user->tasks->$method($task || (), $data);
        }
        catch {
            ($status, $errors{$task}) = index(ref($_), "FTM::Error::") == 0
                                      ? ($status || 400, $_->message)
                                      : ($status || 500, $_);
            return 0;
        } and ref($task)
          and $errors{ $task->name } = q{}; # empty

    }

    $self->render(status => $status // 200, json => \%errors )
        
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

1;
