use strict;

package FTM::User::Proxy;
use Moose::Role;
use POE qw(Session);
use POE::Component::IKC::ClientLite;
use Carp qw(croak);

my $remote;

sub init {
   my ($class, $args) = @_;

   $remote = POE::Component::IKC::ClientLite->spawn(
       timeout => 10,
       ref $args ? %$args
               : ( port => $args // $ENV{FLOWGENCYTM_BACKEND_PORT}
                                 // croak "No port passed"
                 ),
       name    => "Client$$",
   );

   die POE::Component::IKC::ClientLite::error() if !$remote;
}

for my $t (@{ FTM::User::TRIGGERS() }) {
    no strict 'refs';
    *$t = sub {
        my ($user, $data) = @_;
        $data->{_context} = {
            user_id => $user->user_id,
            wantarray => wantarray
        };
        my @ret = $remote->post_respond('FTM_User/'.$t, $data);

        # if we get an exception object, let's rethrow it
        if ( ref $ret[0] eq 'HASH' and my $e = $ret[0]->{_error} ) {
            $e->throw;
        }
        return wantarray ? @{ $ret[0] } : $ret[0];

    }
}

1;

