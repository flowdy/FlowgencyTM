use strict;

package FlowgencyTM::Shell::Command;
use FlowgencyTM;
use Carp qw(croak carp);

# sub import {} # else Module::Find fail

sub new {
    my $class = shift;
    my ($command) = $class =~ m{ (\w+) \z }xms;
    return bless \$command => $class;
}

my %context_info = ( # shared by all commands
    map { $_ => undef } qw(context path task timetrack)
);

sub context { $context_info{context} }
sub path { $context_info{path} }

sub context_info {
    if ( @_ ) {
        if ( @_ == 1 ) { return $context_info{ $_[0] }; }
        my %args = @_;
        while ( my ($key, $value) = each %args ) {
            croak "context_info: key $key does not exist"
                if !exists $context_info{$key};
            $context_info{$key} = $value;
        }
        return;
    }
    else {
        my ($path) = @context_info{'path'};
        if ( length $path and my $context = $context_info{'context'} ) {
            $path = join q{=}, $context, $path;
        }
        return join '@', FlowgencyTM::user->user_id, $path;
    }
}
1;
