package FTM::User::Interface;
use strict;
use Moose::Role;
use POE qw(Session);
use POE::Component::IKC::Server;
use POE::Component::IKC::Specifier;
use Try::Tiny;

my $server_properties;

sub init {
    my ($class, $args) = @_;
    if ( $args && !ref $args ) {
        my ($port, $ip) = reverse split /:/, $args;
        $args = {
            $ip ? (ip => $ip) : (),
            $port ? (port => $port) : (),
        };
    }    

    my $port = POE::Component::IKC::Server->spawn(
        ip => '127.0.0.1',
        port => 0,
        %$args,
        name => 'Backend',
    );
    
    my $_start = sub {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        my $service_name = "FTM_User";
        $kernel->alias_set($service_name);
        $kernel->call(IKC => publish => $service_name, FTM::User::TRIGGERS() );

    };

    POE::Session->create(
        package_states => [ 'FTM::User' => FTM::User::TRIGGERS() ],
        inline_states  => {
            _start => $_start,
        },
    );

    $args->{port} ||= $port;

    $server_properties = $args;
    
} INIT { undef &import; }

with 'FTM::User::Common';

sub dequeue_from_server {
    my $self = shift;
    FlowgencyTM::user( $self->user_id => 0 );
    return;
}

for my $func ( @{ FTM::User::TRIGGERS() } ) {
    around $func => sub {
        my $orig = shift;

        # Prepare for being invoked by nothing
        if ( !defined $_[0] ) { shift; }
        # ... or by the user object
        elsif ( ref $_[0] ) { goto $orig; }
        

        my ($kernel, $heap, $request) = @_[KERNEL, HEAP, ARG0];
        my ($data, $rsvp) = @$request;
        my $ctx = eval { delete $data->{_context} }
            // die "No context object in call of $func";
        my ($user_id, $wantarray) = @{$ctx}{
         qw( user_id   wantarray) 
        };


        my $self;
        my $output = try {
            $self = FlowgencyTM::user( $user_id );
            # TODO: $self->incr_command_number();
            if ( !defined $wantarray ) {   $self->$orig( $data ); undef }
            elsif ( $wantarray       ) { [ $self->$orig( $data ) ] }
            else                       {   $self->$orig( $data ); }
        } catch {
            if ( !(ref $_ && $_->isa("FTM::Error") ) ) {
                $_ = FTM::Error->new("$_");
            }
            $_->user_seqno($self->seqno) if $self; 
            $_->dump();
        };

        $kernel->call(IKC => post => $rsvp, $output);

    };
}

sub server_properties {
    return %$server_properties;
}

sub await_requests_till_shutdown {
    POE::Kernel->run();
    exit;
}

1;
