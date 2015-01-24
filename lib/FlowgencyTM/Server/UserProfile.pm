use strict;

package FlowgencyTM::Server::UserProfile;
use FlowgencyTM;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(from_json encode_json);
use Carp qw(croak);
sub settings {
    my ($self) = @_;
    my $user = $self->stash('user');
    my %errors;

    if ( defined(my $email = $self->param('email')) ) {
         my $error;
         my $part = 'account';
         for ( my ($account, $provider) = split /@/, $email ) {
             if ( !length ) {
                 $error = $part.' part is missing';
             }
             elsif ( /[^\w.-]/ ) {
                 $error = $part.' part is malformed or too esoteric';
               # If needed someday, we could well use Regex::Common, but mind
               # the number of the dependencies FlowgencyTM already has got.
             }
             last if $error;
         } continue { $part = '@provider' }

         if ( $error ) {
             $errors{email} = 'Invalid address: '.ucfirst($error);
         }
         else {
             $user->email($email);
             $user->username($self->param('username'));
         } 
    }
    elsif ( $self->param('update') ) { $user->email(undef); }

    if ( my $password = $self->param('password') ) {
        if ( $password eq $self->param('passw_confirm') ) {
            $user->salted_password($password);
        }
        else { $errors{password} = 'Passwords do not match' }
    }

    my %change_model;
    my %tracks = map { $_->[0] => 1 } $user->get_available_time_tracks;
    for my $tt ( keys %tracks ) {
        my $data = $self->param("timetrack[$tt]");
        next if !length $data;
        $change_model{$tt} = from_json('{'.$data.'}');
    }
    for my $newtt ( @{ $self->every_param('timetrack[]') // [] } ) {
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

    if ( defined(my $appendix = $self->param("appendix")) ) {
        $user->appendix($appendix);
    }

    $user->update() if $self->param('update');

    if ( $self->param('update') && !%errors ) {
        $self->redirect_to('home');
    }
    else {
        $self->stash( errors => \%errors );
    }
    
}

1;

