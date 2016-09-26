package FlowgencyTM::Server;
use FlowgencyTM;
use FTM::FlowDB;
use Mojolicious 6.0;
use Mojolicious::Sessions;
use Mojo::Base 'Mojolicious';
use POSIX qw(strftime);

# use Tie::File;
# tie my @SLOGAN => 'Tie::File', 'slogans.txt';

# This method will run once at server start
sub startup {
  my $self = shift;

  $self->secrets([rand]);
  $self->sessions->cookie_name('FlowgencyTM');

  $self->config(
      hypnotoad => {
          listen => [ $ENV{MOJO_LISTEN} ],
          pid_file => $ENV{PIDFILE},
          workers => 2,
  });

  $self->defaults(
      layout => 'general',
      user => undef,
      hoster_info => do {
          my $file = $self->home->rel_dir('/templates/layouts') . '/hoster_info.html.ep';
          if ( -f $file ) {
              open my $fh, '<', $file;
              local $/;
              binmode $fh => ':utf8';
              <$fh>;
          }
          else { q{} }
      },
  );

  if ( my $l = $ENV{LOG} ) {
      use Mojo::Log;
      open my $fh, '>', $l or die "Could not open logfile $l to write: $!";
      $self->log( Mojo::Log->new( handle => $fh, level => 'warn' ) );
  }

  $self->log->format(sub {
      use POSIX qw(strftime);
      my ($time, $level, @lines) = @_;
      $time = strftime( "%Y-%m-%d %H:%M:%S", localtime $time );
      my $last_error = FTM::Error::last_error();
      my $usn = "FTM::U".( $last_error ? $last_error->user_seqno() : '?' );
      return sprintf "$usn [$time] [$level] %s\n",
          @lines > 1 ? ": ". join("", map { "\n\t".$_ } @lines )
                     : " ".$lines[0]
                     ;
  });

  unshift @{$self->static->paths}, $self->home->rel_dir('site');

  # Router
  my $r = $self->routes->under(sub {
      my $c = shift;

      my $is_remote
          = index( $ENV{MOJO_LISTEN}//q{}, $c->tx->remote_address ) < 0;

      $c->stash(
          is_remote => !defined($ENV{FLOWGENCYTM_USER}) || $is_remote,
          current_time => strftime('%Y-%m-%d %H:%M:%S', localtime time),
      );

      $c->stash(
          hoster_info => $is_remote ? '(private remote)' : '(local)'
      ) if !$c->stash('hoster_info');

      return 1;
  });

  my $auth = $r->under(sub {
      my $c = shift;

      # Prevent autologin unless server is requested from the same machine
      local $ENV{FLOWGENCYTM_USER} = undef if $c->stash('is_remote');
          
      # Rely on Mojolicious in that the session cookie be cryptographically
      # protected against manipulation (HMAC-SHA1 signature). Hence, if the
      # user id is defined, the user has certainly logged in properly.
      # Refer to `perldoc Mojolicious::Controller` if interested.
      my $user_id = $c->accepts('', 'json')
                  ? $self->authenticate_rest_user($c) || do {
                        $c->res->code(401);
                        $c->render( json => {
                                error => 'Not authorized to use REST API',
                                conditions_to_check => [
                                    'With a remote server, connect by HTTPS',
                                    'the user id must exist and be activated',
                                    'the right password is provided'
                                ]
                            }
                        );
                        return undef;
                    }   
                  : $c->session('user_id')
                  ;

      if ( !$user_id and $user_id = $ENV{FLOWGENCYTM_USER} ) {
          $c->session( user_id => $user_id );
      }

      my $user = defined($user_id) && FlowgencyTM::user( $user_id );
      if ( $user && $user->can_login ) {
          $c->stash( user => $user );
          return 1;
      }
      else {
          $c->redirect_to("/user/login");
          return undef;
      }

  });

  $r->any( [qw/GET POST/] => "/user/login" )->to("user#login", retry_msg => 0 );
  $auth->get( '/user/logout' )->to("user#logout");
  $auth->get( '/user/terms' )->to("user#terms");
  $auth->get( '/user/delete' )->to("user#delete");
  my $admin = $auth->under(sub { shift->stash('user')->can_admin })->any('/admin');
  $admin->any('/')->to('admin#dash');
  $admin->get('/:action')->to(controller => 'admin');

  $r->any( [qw/GET POST/] => '/user/join' )->to("user#join");

  # Normal route to controller
  $auth->get('/')->to('task_list#todos')->name('home');
  $auth->get( '/tasks')->to('task_list#tasks');
  $auth->post('/tasks')->to('task_editor#fast_bulk_update');
  
  $auth->get('/info')->to('info#basic');
  $auth->get('/newtask')->to('task_editor#form', incr_prefix => 1);
  $auth->any([qw/GET POST/] => '/user/settings')
       ->to('user#settings');
  $auth->get('/task/archive')->to("task_list#archived");
  $auth->any([qw/GET POST/] => '/task/:id/:action')
       ->to(controller => 'task_editor');

}

my $started_time;
BEGIN { $started_time = scalar localtime(); }
sub get_started_time { $started_time; }

sub authenticate_rest_user {
    my ($self, $c) = @_;

    return if !$c->req->is_secure && $c->stash('is_remote');

    my ($user, $password) = split /:/, $c->req->url->to_abs->userinfo, 2;

    return if !$user;

    for ( FlowgencyTM::user($user) // () ) {
        return $user if $_->can_login && $_->password_equals($password);
    } 

    return;

}

1;
