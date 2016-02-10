package FlowgencyTM::Server::Admin;
use Mojo::Base 'Mojolicious::Controller';
use Carp qw(croak);
use POSIX qw(strftime);

sub dash {
    my $self = shift;
    my $users = FlowgencyTM::database->resultset("User")
        ->search(
              { 'mailoop.type' => { '!=' => undef } },
              { join => 'mailoop' }
          );

    # Delete mailoop records that have been waiting for confirmation for more
    # than one week, thus rendering the confirmation link invalid.
    my $to_drop = $users->search({ 'mailoop.request_date' => {
        '<' => strftime( '%Y-%m-%d %H:%M:%S', localtime( time - 7 * 86400 ) )
    } });
    while ( my $user = $to_drop->next ) {
        my $ml = $user->mailoop;
        if ( $ml->type eq 'invite' ) {
            $user->delete;
        }
        else {
            $ml->delete;
        }
    }

    for my $p_name (@{ $self->req->params->names }) {

        my $u = $p_name =~ m{ \A action \[ (\w+) \] \z }xms
            ? $users->find($1) // next 
            : next
            ;

        my $action = $self->param($p_name);

        if ( $action eq 'sendmail' ) {
            # mailed him
            $u->mailoop->update({
                request_date => $self->stash('current_time') // die
            });
        }
        elsif ( $action eq 'allow' ) {
            my $type = $u->mailoop->type;
            my $accessor = $type eq 'change_email'   ? 'email'
                         : $type eq 'reset_password' ? 'password'
                         : undef
                         ;
            $u->$accessor($u->mailoop->value) if $accessor;
            $u->mailoop->delete();
            $u->update();
        }
        elsif ( $action eq 'delete' ) {
            if ( $u->mailoop->type eq 'invite' ) {
                $u->delete;
            }
            else { 
                $u->mailoop->delete();
            }
        }
        else {
            croak "unsupported user action for user ", $u->user_id, ": ",
                  $action;
        }

    }

    my @mailoop_users = $users->search({ 'mailoop.request_date' => undef });
    for my $user ( @mailoop_users ) {
        if ( $user->mailoop->type eq 'change_email' ) {
            $user->email($user->mailoop->value);
        }
    }

    $self->stash(
        mailoop => \@mailoop_users,
        other_users => FlowgencyTM::database->resultset("User")
            ->search_rs(
                [ { 'mailoop.type' => undef },
                  { 'mailoop.request_date' => { '!=' => undef } }
                ],
                { join => 'mailoop',
                  select => [ 'user_id', 'username', 'extprivacy' ],
                  order_by => { -desc => [ 'created '] },
                }
            )
    );

}

sub view_user {
    my $self = shift;
    my $user = FlowgencyTM::database->resultset("User")->find(
        $self->param("id") // croak "No param 'id' defined"
    );
    $self->stash( admined_user => $user );
}

sub invite {
    my $self = shift;
    my $user = FlowgencyTM::database->resultset("User")->find(
        $self->param("id") // croak "No param 'id' defined"
    );
    $user->mailoop->delete;
}

sub reset_password {
    my $self = shift;
    my $user = FlowgencyTM::database->resultset("User")->find(
        $self->param("id") // croak "No param 'id' defined"
    );
    for my $ml ( $user->mailoop ) {
        $user->password($ml->value);
        $ml->delete;
    }
}

sub change_email {
    my $self = shift;
    my $user = FlowgencyTM::database->resultset("User")->find(
        $self->param("id") // croak "No param 'email' defined"
    );
    for my $ml ( $user->mailoop ) {
        $user->email($ml->value);
        $ml->delete;
    }
}

1;
