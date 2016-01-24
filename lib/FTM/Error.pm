use 5.014;

package FTM::Error {
use Moose;
extends 'Throwable::Error';

use overload eq => sub { ref($_[0]) eq $_[1] };

my $user_seqno;

has user_seqno => (
    is => 'rw',
    trigger => sub {
        my ($self, $new) = @_;
        $user_seqno = $new;
    },
);

has _remote_stack_trace => (
    is => 'ro', isa => 'Str'
);

sub last_user_seqno { $user_seqno; }

before throw => sub {
    my ($self) = @_;
    $user_seqno = $self->seqno if ref ($self);
};

sub DEMOLISH {
    $user_seqno = undef;
}

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
        message => $self->message,
        user_seqno => $self->user_seqno,
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

}

package FTM::Error::IrresolubleDependency;
use Moose;
extends 'FTM::Error';

package FTM::Error::Task::FailsToLoad;
use Moose;
extends 'FTM::Error';

package FTM::Error::Task::InvalidDataToStore;
use Moose;
extends 'FTM::Error';

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
