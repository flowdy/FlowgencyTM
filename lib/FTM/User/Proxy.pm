package FTM::User::Proxy;
use strict;
use Moose::Role;
use POE qw(Session);
use POE::Component::IKC::ClientLite;
use Carp qw(croak);
use FTM::Error;

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
    my $t_sub = sub {
        my ($user, $data) = @_;
        my $wantarray = wantarray;
        my $ctx = $data->{_context} = {
            user_id => $user->user_id,
            wantarray => $wantarray
        };
        croak "Ctx: $ctx" if ref $ctx ne 'HASH';
        my $ret = init()->post_respond('FTM_User/'.$t, $data);

        # if we get an exception object, let's unpack and rethrow it
        if ( ref $ret eq 'HASH' and my $e = delete $ret->{_is_ftm_error} ) {
            $e->throw(%{ $ret });
        }
        return $wantarray ? @$ret : $ret;

    };
    no strict 'refs';
    *$t = $t_sub;
}

1;

