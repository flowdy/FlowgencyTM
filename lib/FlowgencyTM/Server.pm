package FlowgencyTM::Server;
use FlowgencyTM;
use FTM::FlowDB;
use Mojolicious 6.0;
use Mojolicious::Sessions;
use Mojo::Base 'Mojolicious';
use POSIX qw(strftime);

# use Tie::File;
# tie my @SLOGAN => 'Tie::File', 'slogans.txt';

my @INIT_STASH_SLOTS = qw(user is_restapi_req layout is_remote hoster_info);

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
      my $usn = "FTM::U".( $last_error ? $last_error->user_seqno // '-' : '?' );
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

      my $ct = $c->req->headers->content_type;

      $c->stash(
          is_remote => !defined($ENV{FLOWGENCYTM_USER}) || $is_remote,
          is_restapi_req => $ct ? $ct ne 'application/x-www-form-urlencoded'
                          :       $c->accepts('', 'json'),
          current_time => strftime('%Y-%m-%d %H:%M:%S', localtime time),
          showcase_mode => 0,
      );

      $c->stash(
          hoster_info => $is_remote ? '(private remote)' : '(local)'
      ) if !$c->stash('hoster_info');

      return 1;

  });

  $self->hook( before_render => sub {
      my ($c, $args) = @_;

      my $tmpl = $args->{template};
      my $is_restapi_req = $c->stash('is_restapi_req');
      prepare_error( $c => delete $args->{exception} )
          if $tmpl && $tmpl eq 'exception' && (
              $is_restapi_req || $self->mode eq 'production'
          );

      $args->{json} //= do {
          my %stash = %{ $c->stash };
          delete @stash{
              @INIT_STASH_SLOTS,
              grep /^mojo\./, %stash
          };
          \%stash;
      } if $is_restapi_req;

  });

  my $auth = $r->under(sub {
      my $c = shift;

      if ( authenticate_user($c) ) { return 1; }
      elsif ( !$c->stash('is_restapi_req') && $c->req->method eq "GET" ) {
          $c->redirect_to("/user/login");
          return undef;
      }
      else {
          FTM::Error::User::NotAuthorized->throw(
              'Unauthorized Access. '
            . 'The user must be registered and activated. '
            . 'If it is a regular user, provide the right password. '
            . 'If it is a showcase user, only GET requests are allowed.'
          );
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
  $auth->get('/todo')->to('task_list#todos')->name('home');
  $auth->get('/todo/:name')->to('task_list#single');
  $auth->get('/' => sub { shift->redirect_to('home'); });
  $auth->any( [qw|GET POST|] => '/task-form')->to('task_editor#form');
  $auth->get("/tasks")->to("tasks_list#all");
  $auth->any( [qw|PATCH POST|] => '/tasks')->to('task_editor#handle_multi');  
  $auth->get('/tasks/:name')->to('task_editor#handle_single');
  $auth->patch('/tasks/:name')->to('task_editor#handle_single');
  $auth->post('/tasks/:name')->to('task_editor#handle_single', new => 'task' );
  $auth->put('/tasks/:name')->to('task_editor#handle_single', reset => 1 );
  $auth->delete('/tasks/:name')->to('task_editor#purge');
  $auth->get('/tasks/:name/form')->to('task_editor#form');
  $auth->post('/tasks/:name/form')->to('task_editor#handle_single' );
  $auth->get('/tasks/:name/:action')->to(controller => 'task_editor');
  $auth->post('/tasks/:name/open')->to("task_editor#open", ensure => 1);
  $auth->post('/tasks/:name/close')->to(
      controller => "task_editor", action => "open", ensure => 0
  );
  $auth->get('/tasks/:name/steps/:step')->to('task_editor#handle_single');
  $auth->post('/tasks/:name/steps')->to('task_editor#handle_single', new => 'step' );
  $auth->put('/tasks/:name/steps/:step')->to('task_editor#handle_single', reset => 1);
  $auth->patch('/tasks/:name/steps/:step')->to('task_editor#handle_single');
  $auth->delete('/tasks/:name/steps/:step')->to('task_editor#purge');

  $auth->any([qw/GET POST/] => '/user/settings')
       ->to('user#settings');

  $auth->get('/info')->to('info#basic');

  $r->any('/*whatever' => {whatever => ''} => sub {
     my $c        = shift;
     my $whatever = $c->param('whatever');
     $c->render(text => "<h1>Sorry, requested resource not found</h1><p>URL <code>/$whatever</code> did not match a route provided by the server.", status => 404);
   });
}

my $started_time;
BEGIN { $started_time = scalar localtime(); }
sub get_started_time { $started_time; }

# Rely on Mojolicious in that the session cookie be cryptographically
# protected against manipulation (HMAC-SHA1 signature). Hence, if the
# user id is defined, the user has certainly logged in properly.
# Refer to `perldoc Mojolicious::Controller` if interested.
# If the REST application programing interface is used, there is no
# cookie. To stay "RESTful", we rely on HTTP header "Authentification".
      
sub authenticate_user {
    my $c = shift;

    my ($user, my $password)
        = split /:/, $c->req->url->to_abs->userinfo, 2;

    my $further_check;

    if ( $user ) { $further_check = 1 }
    elsif ( $user = $c->session('user_id') ) {
        $further_check = $c->session('showcase_mode');
        $c->stash( showcase_mode => $further_check );
    }
    elsif ( !$c->stash('is_remote') and $user = $ENV{FLOWGENCYTM_USER} ) {
        $c->session( user_id => $user );
    }
    
    $user &&= FlowgencyTM::user($user) or return; 

    if ( $further_check ) {
        if ( $password && $password =~ /\S/ ) {
            $user->password_equals($password) or return;
        }
        elsif ( !defined $user->extprivacy ) {
            if ( $c->req->method eq 'GET' ) {
                $c->stash( showcase_mode => 1 );
            }
            else {
                $password = $c->param("_showcase_password");
                $user->password_equals($password//'') or return;
                $c->session( showcase_mode => 0 );
            }
        }
        else { return; }
    }

    $user->can_login or return;

    $c->stash( user => $user );
    return $user;

}

sub prepare_error {
    my ($c, $x) = @_;
    my $user = $c->stash("user");
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
}
1;
