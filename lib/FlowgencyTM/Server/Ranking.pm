package FlowgencyTM::Server::Ranking;
use FlowgencyTM;
use Mojo::Base 'Mojolicious::Controller';

# This action will render a template
sub list {
  my $self = shift;

  my %args;
  for my $p_name ( $self->param ) {
      $args{$p_name} = $self->param($p_name);
  }

  if ( delete $args{keep} ) {
      use POSIX qw(strftime);
      my $now = delete($args{now}) // strftime("Y-m-d H:M:S", localtime time);
      FTM::Time::Point->now($now);
  }

  my @tasks = FlowgencyTM::user->tasks->list(%args);
  $self->res->headers->cache_control('max-age=1, no-cache');

  $self->render(
    list => sub {
        my $task = shift @tasks // return;
        _dump_task($task);

    },
    timestamp => $tasks[0]->flowrank->_for_ts
  );
}

use FTM::Util::LinearNum2ColourMapper;
use List::Util qw(min);

my @basecolor = (0,0xC0,0xff);

sub _dump_task {
    my ($task) = shift;
    my $dump = {
        name => $task->name,
        title => $task->title,
        score => $task->flowrank->score,
        priority => $task->priority,
        progressbar => _progress_bar( $task->progress, $task->flowrank->drift ),
        progress_pc => {
            checked_exp => $task->progress,
            time => $task->flowrank->time_position,
        },
        duedate => $task->due_ts,
        due_in_hms => $task->flowrank->due_in_hms,
        active => $task->flowrank->active,
        next_statechange_in_hms => $task->flowrank->next_statechange_in_hms,
        open_since => $task->open_since,
        extended_info => $task->is_open && {
           focus => [$task->current_focus],
        },
    };

    return $dump;
}

my $blender = FTM::Util::LinearNum2ColourMapper->new({
    '1' => [255,38,76],
    '0' => \@basecolor,
    '-1' => [51,255,64],
});

sub _progress_bar {
    my ($done, $rel_state) = @_;
    my $orient = $rel_state > 0 ? "right" : "left";
    my $other_opacity = 1 - abs($rel_state);
    
    return {
        primary_color => scalar $blender->blend($rel_state),
        orientation => $orient,
        primary_width => sprintf("%1.0f%%", ($rel_state > 0 ? 1-$done : $done) * 100),
        secondary_color => sprintf 'rgba(%d,%d,%d,%f)', @basecolor, $other_opacity,
    }

}
1;
