use strict;

package FlowgencyTM::Shell::Command::user;
use base 'FlowgencyTM::Shell::Command';
use Getopt::Long qw(GetOptionsFromArray);
use Term::ReadLine;

my $TERM = Term::ReadLine->new("FlowgencyTM, Username input");

sub run {
    my ($self, $user) = @_;
    USER_ENTRY: {
        $user = FlowgencyTM::user($user,1);
        if ( !$user->in_storage ) {
            my $olduser = $user->user_id;
            my $newuser = $TERM->readline(
                "Press Enter to confirm new user $olduser OR change the name: ",
                $olduser
            );
            chomp $newuser;
            if ($newuser eq $olduser) {
                $user->insert;
                print "User created. Don't forget to set up a "
                    . "time_model before you enter any tasks.\n"
            }
            else {
                $user = $newuser;
                redo USER_ENTRY;
            }
        }
    }
    return 1;
}

1;
