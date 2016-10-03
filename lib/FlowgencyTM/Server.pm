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

  $self->hook( before_render => sub {
      my ($c, $args) = @_;
      my $tmpl = $args->{template};
      $tmpl && $tmpl eq 'exception' or return;
      $c->accepts('json') || $self->mode eq 'production' or return;
      error_handler( $c => delete $args->{exception} );
  });

  my $auth = $r->under(sub {
      my $c = shift;

      # Prevent autologin unless server is requested from the same machine
      local $ENV{FLOWGENCYTM_USER} = undef if $c->stash('is_remote');
          
      # Rely on Mojolicious in that the session cookie be cryptographically
      # protected against manipulation (HMAC-SHA1 signature). Hence, if the
      # user id is defined, the user has certainly logged in properly.
      # Refer to `perldoc Mojolicious::Controller` if interested.
      # If the REST application programing interface is used, there is no
      # cookie. To stay "RESTful", we choose a different approach by relying
      # on Authentication header.
      my $user_id = $c->accepts('', 'json')
                  ? $self->authenticate_rest_user($c)
                    || FTM::Error::User::NotAuthorized->throw(
                           http_status => 401, 
                           message => 'User may not use REST API. '
                              . 'Conditions to check: '
                              . 'a) With a remote server, connect by HTTPS. '
                              . 'b) The user must be registered and activated. '
                              . 'c) The right password is provided.'
                       )
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
  $auth->get('/')->to(sub { shift->redirect_to('home'); });
  $auth->get('/todo')->to('task_list#todos')->name('home');
  $auth->get('/todo/:name')->to('task_list#single');
  $auth->get('/newtask')->to('task_editor#form', incr_prefix => 1);
  $auth->post('/newtask')->to('task_editor#form', new => 'task' );

  my $tasks = $auth->get( '/tasks')->to('task_list#all');
  $tasks->any( [qw|PATCH POST|] => '/')->to('task_editor#fast_bulk_update');  
  $tasks->get('/:name')->to('task_editor#form');
  $tasks->patch('/:name')->to('task_editor#form', new => 0 );
  $tasks->put('/:name')->to('task_editor#form', reset => 1);
  $tasks->delete('/:name')->to('task_editor#purge');
  $tasks->get('/:name/form')->to('task_editor#form');
  $tasks->post('/:name/form')->to('task_editor#form', new => 0 );
  $tasks->get('/:name/:action')->to('task_editor#$action');
  $tasks->post('/:name/open')->to("task_editor#open", ensure => 1);
  $tasks->post('/:name/close')->to("task_editor#open", ensure => 0);
  $tasks->get('/:name/steps/:step')->to('task_editor#form');
  $tasks->post('/:name/steps')->to('task_editor#form', new => 'step');
  $tasks->put('/:name/steps/:step')->to('task_editor#form', reset => 1);
  $tasks->patch('/:name/steps/:step')->to('task_editor#form', new => 0);
  $tasks->delete('/:name/steps/:step')->to('task_editor#purge');

  $auth->any([qw/GET POST/] => '/user/settings')
       ->to('user#settings');

  $auth->get('/info')->to('info#basic');
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

sub error_handler {
    my ($c, $x) = @_;
    my $stash = $c->stash;
    my ($user) = delete @{$stash}{'user', 'is_remote', 'hoster_info'};
    if ( index( ref $x, 'FTM::Error' ) == 0 ) {
        $c->res->code( $x->http_status // 500 );
        my ($type) = ref($x) =~ /^FTM::Error::(.+)$/;
        $type //= 'General error';
        $c->stash(
            message => $type || $user->can_admin ? $x->message
                : "Something went wrong in backend (details in server log)",
            error => $type,
            user_seqno => $x->user_seqno
        );
    }
    else {
        $c->stash(
            error => 'Internal Server Error',
            message => $user->can_admin ? $x
                : "Something went wrong (details in server log)",
        );
    }
 
    if ( $c->accepts('', 'json') ) {
        my $stash = $c->stash;
        $args->{json} = $stash;
    }

}
1;
