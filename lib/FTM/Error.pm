use 5.014;

package FTM::Error {
use Moose;
extends 'Throwable::Error';

use overload eq => sub { ref($_[0]) eq $_[1] };

has user_seqno => (
    is => 'rw',
);

has http_status => (
    is => 'rw',
    isa => 'Num',
);

has _remote_stack_trace => (
    is => 'ro', isa => 'Str'
);

sub dump {
    my ($self) = @_;
    my $stack_trace = $self->stack_trace;
    my (@frames);
    while ( my $next = $stack_trace->next_frame ) {
        last if $next->package eq 'FTM::User::Interface'
             && $next->subroutine eq 'Try::Tiny::try';
        push @frames, $next;
    }
    return {
        (map { $_ => $self->$_ } qw(message user_seqno http_status)),
        _is_ftm_error => ref $self,
        _remote_stack_trace => join(
            "", map { $_->as_string . "\n" } @frames
        ),
        inner(),
    };
}

override as_string => sub {
    my $self = shift;
    if ( defined(my $rst = $self->_remote_stack_trace) ) {
        $rst =~ s{^}{[BACKEND] }mg;
        return $self->message.$rst;
    }    
    else { super(); }
};

my $last_error;
sub last_error { $last_error; }
sub BUILD { $last_error = shift; }
sub DEMOLISH { $last_error = undef; }

}

package FTM::Error::ObjectNotFound;
use Moose;
extends 'FTM::Error';

has '+http_status' => (
    default => 404,
);

has '+message' => (
    required => 0,
);

has type => (
    is => 'ro', isa => 'Str', required => 1
);

has name => (
    is => 'ro', isa => 'Maybe[Str]', required => 1
);

around message => sub {
    my ($orig, $self) = @_;
    my $name = $self->name;
    return $self->$orig()
        // "No ".$self->type." "
        .( $name ? "'$name'" : '(undefined)' )." found",
        ;
};

package FTM::Error::IrresolubleDependency;
use Moose;
extends 'FTM::Error';

package FTM::Error::User::DataInvalid;
use Moose;
extends 'FTM::Error';

package FTM::Error::User::NotAuthorized;
use Moose;
extends 'FTM::Error';

has '+http_status' => (
    default => 401
);

package FTM::Error::Task::FailsToLoad;
use Moose;
extends 'FTM::Error';

package FTM::Error::Task::InvalidDataToStore;
use Moose;
extends 'FTM::Error';

package FTM::Error::Task::MultiException;
use Moose;
extends 'FTM::Error';

has '+message' => (
    required => 0,
    default => "Errors relating to various tasks processed, s. 'all' attribute",
);

has 'all' => (
    is => 'rw',
    isa => 'HashRef[Str|Object]',
);

augment dump => sub {
    my $self = shift;
    my $errors = $self->all;
    my $status = 400;
    for my $e ( values %$errors ) {
        if ( $_ = eval { $e->can('message') } ) {
            $e = $e->$_;
        }
        else { $status = 500; }
    }
    return all => $errors, http_status => 400;
};

package FTM::Error::Time::InvalidSpec;
use Moose;
extends 'FTM::Error';

package FTM::Error::Time::Gap;
use Moose;
extends 'FTM::Error';

package FTM::Error::Time::InvalidTrackData;
use Moose;
extends 'FTM::Error';

package FTM::Error::Time::HasPast;
use Moose;
extends 'FTM::Error';

package FTM::Error::Time::InterlacedVariations;
use Moose;
extends 'FTM::Error';

has left => ( is => 'ro', isa => 'FTM::Time::Variation' );
has right => ( is => 'ro', isa => 'FTM::Time::Variation' );

has '+message' => ( required => 0 );

around 'message' => sub {
    my ($orig, $self) = (shift, @_);

    if ( @_ > 2 ) { return $orig->(@_); }

    return $orig->(shift) //
        sprintf "Variations in %s may not be interlaced due to explicit dates: %s <-> %s",
            $self->left->track->name,
            $self->left->name // "left", $self->right->name // "right"
        ;
};

__PACKAGE__->meta->make_immutable;

1;
