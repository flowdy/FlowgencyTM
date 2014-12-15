use strict;

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

  my $now;
  if ( delete $args{keep} ) {
      use POSIX qw(strftime);
      $now = delete($args{now}) || strftime("%Y-%m-%d %H:%M:%S", localtime time);
      FTM::Time::Point->now($now);
  }
  else { $now = $args{now} }

  my @tasks = FlowgencyTM::user->tasks->list(%args);
  $self->res->headers->cache_control('max-age=1, no-cache');

  $now //= FTM::Time::Point->now();
  $self->render(
    list => sub {
        my $task = shift @tasks // return;
        _dump_task($task);

    },
    timestamp => @tasks ? $tasks[0]->flowrank->_for_ts : $now
  );
}

use FTM::Util::LinearNum2ColourMapper;
use List::Util qw(min);

my @basecolor = (0,0xC0,0xff);

sub _dump_task {
    my ($task) = shift;
    my ($due,$next)
        = map { $task->flowrank->$_ }
          'due_in_hms', 'next_statechange_in_hms'
        ;
    my $is_active = $task->flowrank->active;
    my $dump = {
        name => $task->name,
        title => $task->title,
        score => $task->flowrank->score,
        priority => $task->priority,
        progressbar => _progress_bar(
            $task->progress, $task->flowrank->drift, $is_active
        ),
        progress_pc => {
            checked_exp => $task->progress,
            time => $task->flowrank->time_position,
        },
        duedate => $task->due_ts,
        due_in_hms => $due,
        active => $task->flowrank->active,
        $due ne $next ? (next_statechange_in_hms => $next) : (),
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

my $grey = [ hex(62), hex(53), hex(53) ]; 
my $paused_blender = FTM::Util::LinearNum2ColourMapper->new({
    '1' => $grey,
    '0' => [127,127,127],
    '-1' => $grey,
});

sub _progress_bar {
    my ($done, $rel_state, $active) = @_;
    my $orient = $rel_state > 0 ? "right" : "left";
    my $other_opacity = 1 - abs($rel_state);
    my $blender = $active ? $blender : $paused_blender;
    
    return {
        primary_color => scalar $blender->blend($rel_state),
        orientation => $orient,
        primary_width => sprintf("%1.0f%%", ($rel_state > 0 ? 1-$done : $done) * 100),
        secondary_color => sprintf 'rgba(%d,%d,%d,%f)', $active ? @basecolor : @$grey, $other_opacity,
    }

}
1;
