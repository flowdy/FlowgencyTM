use strict;

package FlowgencyTM::Server::UserProfile;
use FlowgencyTM;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(from_json encode_json);
use Carp qw(croak);
sub settings {
    my ($self) = @_;
    my $user = FlowgencyTM::user();

    my %change_model;
    my %tracks = map { $_->[0] => 1 } $user->get_available_time_tracks;
    for my $tt ( keys %tracks ) {
        my $data = $self->param("timetrack[$tt]");
        next if !length $data;
        $change_model{$tt} = from_json('{'.$data.'}');
    }
    for my $newtt ( @{ $self->param('timetrack[]') // [] } ) {
        next if !length $newtt;
        my $data = from_json('{'.$newtt.'}');
        my $name = $data->{name};
        if ( $tracks{$name} ) {
            croak "track $name exists";
        }
        $change_model{$name} = $data;
    }
    $user->update_time_model(\%change_model) if %change_model;

    if ( my $prio = $self->param('priorities') ) {
        my (%prio,$i);
        for my $p ( split q{,}, $prio ) {
            $i++;
            next if !length $p;
            $prio{$p} = $i;
        }
        $user->remap_priorities(%prio) if %prio;
    }

    my %weights;
    for my $w ( qw(priority due drift open timeneed) ) {
        if ( defined(my $num = $self->param("weight[$w]")) ) {
            $weights{$w} = $num;
        }
    }
    $user->modify_weights(%weights) if %weights;

}

1;

