use strict;

package FlowgencyTM::Shell::Command::task;
use base 'FlowgencyTM::Shell::Command';

sub run {
    my $self = shift;
    my $task = parser(shift);
    print "Task created: ", $task->name, "\n";
    return 1;
}

my $user = '';
my $parser;
sub parser  {
    my $current_user = FlowgencyTM::user();
    if ( $user ne $current_user ) {
        $user = $current_user;
        $parser = $user->tasks->get_tfls_parser;
    }
    goto &$parser;
}

1;
