use strict;

package FlowgencyTM::Server::User;
use FlowgencyTM;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(from_json encode_json);
use FTM::Error;
#use Carp qw(croak);

sub settings {
    my ($self) = @_;
    my $user = $self->stash('user');
    my %errors;

    my $email = $self->param('email');
    if ( length $email ) {
         my $error;
         my $part = 'account';
         for ( my ($account, $provider) = split /@/, $email, 2 ) {
             if ( !length ) {
                 $error = $part.' part is missing';
             }
             elsif ( /[^\w.-]/ ) {
                 $error = $part.' part is malformed or too esoteric';
               # If needed someday, we could well use Regex::Common, but I mind
               # the number of the dependencies FlowgencyTM already has got.
             }
             last if $error;
         } continue { $part = '@provider' }

         if ( $error ) {
             $errors{email} = 'Invalid address: '.ucfirst($error);
         }
         else {
             if ( $user->email ne $email ) {
                 $user->needs_to_confirm(change_email => $email)
             }
             else { 
                 $email = undef;
             }
             $user->username($self->param('username'));
         } 
    }
    elsif ( $self->param('update') ) { $user->email($email = undef); }
    else { $email = undef; }

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

    my $prio = $self->param('priorities');
    my $change_model = $self->param('time_model_changes');
    my %weights;
    for my $w ( qw(priority due drift open timeneed) ) {
        if ( defined(my $num = $self->param("weight[$w]")) ) {
            $weights{$w} = $num;
        }
    }
    my %settings;
    $settings{weights} = \%weights if %weights;
    $settings{priorities} = $prio if $prio;
    $settings{change_time_model} = from_json($change_model) if $change_model;

    if ( defined(my $appendix = $self->param("appendix")) ) {
        $user->appendix($appendix);
    }

    $user->realize_settings(\%settings) if %settings;

    $user->update() if $self->param('update');

    if ( $self->param('update') && !%errors ) {
        $email ? $self->render(
                     'user/confirmation_notice',
                     msg => 'You have changed your email'
                 )
               : $self->redirect_to('home')
               ;
    }
    else {
        $self->stash( errors => \%errors, $user->dump_complex_settings );
    }
    
}

sub join {
    my ($self) = @_;

    if ( !$self->param('join') ) {
        return $self->render('user/signup');
    }

    my $email = $self->param("email");
    my $password = $self->param("password");

    if ( !$email or $email !~ m{ \A [\w.-]+ @ [\w.-]+ . \w+ \z }xms ) {
        FTM::Error::User::DataInvalid->throw("Email address passed is invalid");
    }
    if ( length($password) < 5 or $password !~ m{ \W }xms ) {
        FTM::Error::User::DataInvalid->throw(
             "Password is empty or too easy: "
            ."It must be at least five characters long "
            ."and contain one or more non-alphanumerics"
        );
    }

    my $will_accept = join "", map { $self->param($_) ? 1 : 0 } qw(
        checkwhatisftm privacywarning voluntaryuse promisefeedback
        deletion ignoreterms dontcheck
    );

    my $orig_accept = $will_accept;

    if ( $will_accept =~ /1([01])11100/ ) {
        my $user = FlowgencyTM::new_user( $self->param("user") => {
            username => $self->param("username"), email => $email,
            -invite => 1, extprivacy => !$1
        });
        $user->salted_password($password);
        $user->update;
    }
    else {
        FTM::Error::User::DataInvalid->throw(
            "New user not accepted. The right terms of use must be selected",
            http_status => 400
        );
    }

    $self->render(
        'user/confirmation_notice', msg => 'Your user account is created'
    );

}

sub login {
    my $self = shift;

    my $user_id         = $self->param('user') // return;
    my $password        = $self->param('password');
    my $resetpw_confirm = $self->param('confirmpw');
    my $token           = $self->param('token');
    my $user = FlowgencyTM::database->resultset("User")->find(
        $user_id =~ m{@} ? { email => $user_id } : $user_id
    );
    
    if ( !$user ) {
        $self->render( retry_msg => 'authfailure' );
        return;
    }

    my $trigger = sub {};
    my $confirm;

    if ( $resetpw_confirm ) {
        FTM::Error::User::DataInvalid->throw(
            "Password and confirm password differ."
        ) if $resetpw_confirm ne $password;
        $password = $user->salted_password($resetpw_confirm);
        $user->needs_to_confirm(
            reset_password => $password, $token
        );
        $self->render(
            'user/confirmation_notice',
            msg => "You have reset your password"
        );
        return;
    }
    elsif ( $token ) {
        $confirm = $user->needs_to_confirm( undef, $token )
            // FTM::Error::User::ConfirmationFailure->throw(
                  "There is nothing to be confirmed by the token",
               );
        if ( $confirm->type eq 'invite' ) {}
        elsif ( $confirm->type eq 'reset_password' ) {
            $user->password($confirm->value);
            $trigger = sub { shift() ? $user->update : $confirm->insert };
        }
        elsif ( $confirm->type eq 'change_email' ) {
            $user->update({ email => $confirm->value });
        }
        else {
            die "Unknown confirm type: ", $confirm->type;
        }
    }

    if ( !( $password || defined $user->extprivacy ) ) {
        $self->session( showcase_mode => 1 );
        $self->redirect_to("home");          
    }
    elsif ( $password && $user->password_equals($password) ) {
        $trigger->(1);
        $self->session("user_id" => $user_id);
        $self->redirect_to("home");
    }
    else {
        $trigger->(0);
        $self->render( retry_msg => 'authfailure' );
    }

}

sub logout {
    my $self = shift;

    FlowgencyTM::user( $self->session('user_id') => 0 );
    $self->session(expires => 1);

    $self->render(template => "user/login", retry_msg => 'loggedOut' );

}

sub delete {
    my $self = shift;
    my $user = $self->stash('user');

    if ( $self->param("delete") ) {
        my $info = { created => $user->created, now => $self->stash('current_time') };
        my @fields = qw(
            onproductiveuse employer commercialservice willnotuseftm comment
        );
        for my $p ( @fields ) {
            my $array = $self->every_param($p) // next;
            $info->{$p} = @$array < 2
                ? ($array->[0] // next)
                : CORE::join( ", ", @$array )
                ;
        }

        my $file = "gone_users.txt";
        if ( -e $file ) {
            open my $fh, '>>', $file or throw FTM::Error "Can't write to $file: $!";
            print $fh encode_json($info), "\n";
        }
        else {
            throw FTM::Error "Can't write to $file: does not exist";
        }

        $user->delete;
        $self->session(expires => 1);
        $self->redirect_to("home");
    }

}
    
sub terms {
    my $self = shift;
    my $xp = $self->stash('user')->extprivacy;
    $self->render('user/signup', ext_privacy_defined => $xp || -1 );
}

1;

