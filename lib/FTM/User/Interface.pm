use strict;

package FTM::User::Interface;
use Moose::Role;
use POE qw(Session);
use POE::Component::IKC::Server;
use POE::Component::IKC::Specifier;

my $server_properties;

sub import {
    my ($class, $args) = @_;
    $args = { port => $args } if $args && !ref $args;
    my $port = POE::Component::IKC::Server->spawn(
      ip => '127.0.0.1',
      port => 0,
      %$args,
      name => 'Backend',
    );
    
    $args->{port} ||= $port;

    POE::Session->create(
        package_states => { 'FTM::User' => FTM::User::TRIGGERS }
    );

    $server_properties = $args;
    
    undef &import;
}

with 'FTM::User::Common';

around [ TRIGGERS ] => sub {
    my $orig = shift;

    # Prepare for being invoked by the user object
    if ( ref $_[0] ) { goto $orig; } else { shift; }

    my ($kernel, $heap, $request) = @_[KERNEL, HEAP, ARG0];
    my ($data, $rsvp) = @$request;
    my ($user_id, $wantarray) = @{ delete $data->{_context} }{
     qw( user_id   wantarray) 
    }
    my $self = FlowgencyTM::user( $user_id );

    my $output = try {
        if ( !defined $wantarray ) {   $self->$orig( $data ); undef }
        elsif ( $wantarray       ) { [ $self->$orig( $data ) ] }
        else                       {   $self->$orig( $data ); }
    } catch {
        $output->{_error} = $_;
    };

    $kernel->call(IKC => post => $rsvp, $output);

};

sub _start {
    shift; my ($kernel, $heap) = @_[KERNEL, HEAP];
    my $service_name = "FTM_User";
    $kernel->alias_set($service_name);
    $kernel->call(IKC => publish => $service_name, FTM::User::TRIGGERS);
}

sub server_properties {
    return %$server_properties;
}

sub await_requests {
    POE::Kernel->run();
    exit;
}

1;
