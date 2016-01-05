use 5.014;

package FTM::Error {
use Moose;
extends 'Throwable::Error';

use overload eq => sub { ref($_[0]) eq $_[1] };

my $user_seqno;

has user_seqno;

sub last_user_seqno { $user_seqno; }

before throw => sub {
    my ($self) = @_;
    $user_seqno = $self->seqno;
};

sub DEMOLISH {
    $user_seqno = undef;
}

package FTM::Error::Task::FailsToLoad;
use Moose;
extends 'FTM::Error';

package FTM::Error::Task::InvalidDataToStore;
use Moose;
extends 'FTM::Error';

package FTM::Error::TimeSpec::Invalid;
use Moose;
extends 'FTM::Error';

1;
