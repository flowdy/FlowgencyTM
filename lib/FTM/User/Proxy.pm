use strict;

package FTM::User::Proxy;
use Moose::Role;
use POE qw(Session);
use POE::Component::IKC::ClientLite;
use Carp qw(croak);

my $remote;

sub import {
   my ($class, $args) = @_;

   $remote = POE::Component::IKC::ClientLite->spawn(
       port    => ref $args ? $args->{port}
                : $args // $ENV{FLOWGENCYTM_PACKEND_PORT}
                        // croak "No port passed",
       name    => "Client$$",
       timeout => 10,
   );

}

for my $t ( FTM::User::TRIGGERS ) {
    no strict 'refs';
    *$t = sub {
        my ($user, $data) = @_;
        $data->{_context} = {
            user_id => $user->name,
            wantarray => wantarray
        };
        my @ret = $remote->post_respond('FTM_User/'.$t, $data);
        if ( ref $ret[0] eq 'ARRAY' and my $e = $ret[0]->{_error} ) {
            croak $e;
        }
        @ret = @{ $ret[0] } if wantarray;
        return @ret;
    }
}

__PACKAGE__->meta->make_immutable();
1;

