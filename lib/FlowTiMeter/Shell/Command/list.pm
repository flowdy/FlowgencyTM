use strict;

package FlowTiMeter::Shell::Command::list;
use base 'FlowTiMeter::Shell::Command';
use Getopt::Long qw(GetOptionsFromArray);

sub run {
    $DB::single = 1;
    my $self = shift;
    my $remain = GetOptionsFromArray(
      \@_ => \my(%opts), 'desk|d!', 'drawer=i', 'archive|a=s@', 'now|t|n=s'  
    );
    my $num = ${ ref $remain ? $remain : [] }[0] // -1;
    my @tasks = FlowTiMeter::user->tasks->list(%opts);
    print "Urgency ranking for timestamp ", $tasks[0]->flowrank->_for_ts, "\n";
    open my $pager, "|-", "/bin/more" or die "Could not start pager: $!";
    while ( $num-- and my $task = shift @tasks ) {
        print $pager format_task($task), "\n"
            or die "Could not print to pager: $!";
    }
    close $pager;
    return 1;
}

sub format_task {
    my ($task) = @_;
    my $flowrank = $task->flowrank;
    return $task->name, ": ", $task->title,
           sprintf( "\n  %1.2f", $flowrank->score ),
           sprintf( " %2.1f%%", $task->progress * 100 ), " | ",
           $flowrank->active     ? "A"
             : $flowrank->paused ? "P"
             : "?", " ",
           $flowrank->next_statechange_in_hms, " | ", $flowrank->due_in_hms, " | ",
           $task->due_ts, "\n",
           $task->is_open
               ? ($task->description, "\n", scalar $task->current_focus)
               : ()
        ;
}

1;
