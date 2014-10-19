use strict;

package FlowTiMeter::Shell::Command::task;
use base 'FlowTiMeter::Shell::Command';

sub run {
    my $self = shift;
    my $task = parser(shift);
    print "Task created: ", $task->name, "\n";
    return 1;
}

my $user = '';
my $parser;
sub parser  {
    my $current_user = FlowTiMeter::user();
    if ( $user ne $current_user ) {
        $user = $current_user;
        $parser = $user->tasks->get_tfls_parser;
    }
    goto &$parser;
}

1;
