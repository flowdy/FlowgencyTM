use strict;

package FTM::User::Proxy;
use Moose::Role;
use POE qw(Session);
use POE::Component::IKC::ClientLite;
use Carp qw(croak);

sub init {
    my ($class, $args) = @_;
 
    my $remote;

    my %args = ref $args ? %$args : (
        port => $args // $ENV{FLOWGENCYTM_BACKEND_PORT}
                      // croak "No port passed"
    );
 
    my $ensure_connected = sub {
        return $remote if $remote && $remote->connect();
        croak POE::Component::IKC::ClientLite::error();
    };
 
    no warnings 'redefine';
    *init = sub {
        $remote = POE::Component::IKC::ClientLite->spawn(
            timeout => 10, %args, name => "Client$$",
        );
 
        $ensure_connected->();
 
        no warnings 'redefine';
        *init = $ensure_connected;

        $remote;
    };
}

for my $t (@{ FTM::User::TRIGGERS() }) {
    no strict 'refs';
    *$t = sub {
        my ($user, $data) = @_;
        $data->{_context} = {
            user_id => $user->user_id,
            wantarray => wantarray
        };
        my @ret = init()->post_respond('FTM_User/'.$t, $data);

        # if we get an exception object, let's rethrow it
        if ( ref $ret[0] eq 'HASH' and my $e = $ret[0]->{_error} ) {
            $e->throw;
        }
        return wantarray ? @{ $ret[0] } : $ret[0];

    }
}

1;

