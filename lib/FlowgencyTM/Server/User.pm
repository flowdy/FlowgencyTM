use strict;

package FlowgencyTM::Server::User;
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
        if ( !$user->password_equals($self->param('old_password')) ) {
            $errors{password} = 'Old password is wrong';
        }
        elsif ( $password ne $self->param('passw_confirm') ) {
            $errors{password} = 'Passwords do not match' 
        }
        else {
            $user->salted_password($password);
        }
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

sub join {
    my ($self) = @_;

    my ($email, $password) = $self->param([ "email", "password" ]);

    if ( !$email or $email !~ m{ \A [\w.-]+ @ [\w.-]+ . \w+ \z }xms ) {
        croak "Email address passed is invalid";
    }
    if ( length($password) < 5 or $password !~ m{ \W }xms ) {
        croak "Password is empty or too easy: ",
              "It must be at least five characters long ",
              "and contain one or more non-alphanumerics"
        ;
    }

    my $user = FlowgencyTM::new_user( $self->param("user") => {
        username => $self->param("username"), email => $email,
        -invite => 1,
    });
    $user->salted_password($password);
    $user->update;

}

sub login {
    my $self = shift;

    my $user_id = $self->param('user') // return;
    my $password = $self->param('password');
    my $user = FlowgencyTM::database->resultset("User")->find($user_id);

    my $on_success = sub {};

    if ( my $confirm = $self->param('token') ) {
        $confirm = $user->find_related(
            mailoop => { token => $confirm }
        );
        if ( !$confirm ) { $self->res->code(400); }
        elsif ( $confirm->type eq 'invite' ) {
            $on_success = sub { $confirm->delete };
        }
        elsif ( $confirm->type eq 'reset_password' ) {
            $user->password($confirm->value);
            $on_success = sub { $user->update; $confirm->delete; };
        }
        elsif ( $confirm->type eq 'change_email' ) {
            $user->update({ email => $confirm->value });
            $on_success = sub { $confirm->delete; };
        }
        else {
            croak "Unknown confirm type: ", $confirm->type;
        }
    }
           
    if ( $user && $user->password_equals($password) ) {
        $on_success->();
        $self->session("user_id" => $user_id);
        $self->redirect_to("home");
    }
    else {
        $self->render( retry => 1 );
        return;
    }


}

1;
