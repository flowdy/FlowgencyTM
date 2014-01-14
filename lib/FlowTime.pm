use strict;

package FlowTime; {
use Carp qw(croak);
my $db;
use FlowDB \$db => $ENV{FLOWDB_SQLITE_FILE} || "flow.db";
use User; # No, it is rather the user who use FlowTime

my %users;

sub user ($;$) {
    my ($username,$new) = @_;
    my $retr = "find";
    $retr .= "_or_new" if $new;
    return $users{$username} //= User->new(
        dbixrow => $db->resultset("User")->$retr($username)
                // croak
    );
}

sub new_user ($) {
    my ($username) = @_;
    return $users{$username} = User->new(
        dbixrow => $db->resultset("User")->create($username)
    );
}

sub database () { $db }

} 1;
