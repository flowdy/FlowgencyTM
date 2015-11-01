package FTM::Error;
use Moose;
extends 'Throwable::Error';

use overload eq => sub { ref($_[0]) eq $_[1] };

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
