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
      my $usn = "FTM::U".( $last_error ? $last_error->user_seqno // '-' : '?' );
      return sprintf "$usn [$time] [$level] %s\n",
          @lines > 1 ? ": ". join("", map { "\n\t".$_ } @lines )
                     : " ".$lines[0]
                     ;
  });

  unshift @{$self->static->paths}, $self->home->rel_dir('site');

  # Router
  my $r = $self->routes->under(\&initialize_stash);

  $self->helper( 'reply.client_error' => \&prepare_client_error );

  $self->hook( before_render => \&restapi_reply_jsonifier );

  my $auth = $r->under(\&require_user_otherwise_login_or_fail);

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
  $auth->get("/tasks")->to("task_list#all");
  $auth->any( [qw|PATCH POST|] => '/tasks')->to('task_editor#handle_multi');  
  $auth->get('/tasks/:name')->to('task_editor#form');
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
  $r->get('/help/*file' => \&render_online_help);

}

my $started_time;
BEGIN { $started_time = scalar localtime(); }
sub get_started_time { $started_time; }

sub initialize_stash {
    my $c = shift;

    my $is_remote
        = index( $ENV{MOJO_LISTEN}//q{}, $c->tx->remote_address ) < 0;

    my $ct = $c->req->headers->content_type;

    $c->stash(
        is_remote => !defined($ENV{FLOWGENCYTM_USER}) || $is_remote,
        is_restapi_req => $c->accepts('', 'json' )
                       || $ct && $ct ne 'application/x-www-form-urlencoded',
        current_time => strftime('%Y-%m-%d %H:%M:%S', localtime time),
        showcase_mode => 0,
    );

    $c->stash(
        hoster_info => $is_remote ? '(private remote)' : '(local)'
    ) if !$c->stash('hoster_info');

    return 1;

}

sub require_user_otherwise_login_or_fail {
    my $c = shift;

    my $is_restapi_req = $c->stash('is_restapi_req');

    if ( my $u = authenticate_user($c) ) {
        $c->stash( user => $u );
        return 1;
    }

    elsif ( !$is_restapi_req && $c->req->method eq "GET" ) {
        $c->redirect_to("/user/login");
    }

    else {
        $c->reply->client_error(
            message => 'To fulfil your request requires user identification: '
              . 'The user must be registered and their account activated. '
              . 'If it is a regular user, authenticate with right password. '
              . 'When seeing a showcase user, only GET requests are allowed.',
            error => "Access Denied",
            http_status => 401,
        );
    }

    return undef;

}
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

    return $user;

}

sub prepare_client_error {
    my $c = shift;
    my $x = @_ > 1 ? { @_ } : shift;
    my %args;

    # Case 1: We have got a genuine application error object of
    #         which we know the interface.
    if ( (my $xclass = ref $x) =~ s{^FTM::Error\b}{} ) {
        # consider rather Scalar::Util::blessed ... Yes, I did
        $xclass =~ s{^::}{};
        %args = (
            %{ $x->dump(0) },
            error => $xclass || "General error",
        );
    }

    # Case 2: We have got a plain hash of arguments to use directly
    elsif ( ref $x eq 'HASH' ) { %args = %$x; }

    # Otherwise, we have got an exception thrown from other, third-party 
    # code. You should design your production-mode exception template so
    # that it displays only $error and $message, not $exception, because
    # this might allow potential attackers to examine your server's
    # vulnerabilities.
    else {
        my $u = $c->stash("user");
        $c->stash(
            error => "Internal server error",
            message => $u && $u->can_admin ? (ref $x ? "$x" : $x)
                     : "Oops, something went wrong. (A more detailed "
                     . "error message logged server-side. Ask the admin.)"
                     ,
        );
        return;
    }

    $c->res->code( delete $args{http_status} // 500 );
    return $c->render( template => 'exception.production', %args );

}

sub restapi_reply_jsonifier {
    my ($c, $args) = @_;

    return if !$c->stash('is_restapi_req')
           || $args->{json};

    my %stash = ( %{ $c->stash }, %$args );
    delete @stash{ # general slots of internal interest ...
        qw(snapshot user template is_restapi_req layout
           is_remote hoster_info cb action controller
        ),
        grep { /^mojo\./ } keys %stash
    };

    $args->{json} = \%stash;

}

sub render_online_help {
    require Text::Markdown;
    my $c = shift;

    my $file = $c->stash("file");

    if ( $file =~ m{(^|\/)\.} ) {
        return $c->reply->not_found;
    }
    elsif ( $file =~ m{\.(\w{3,4})$} ) {
        return $c->reply->static( "../doc/online-help/" . $file );
    }

    $file = $c->app->home->rel_file(
        "doc/online-help/" . ( $file || "faq" ) . ".md"
    );

    open my $fh, '<', $file or return $c->reply->not_found;
    binmode $fh, ':utf8';

    $c->stash( layout => undef ) if $c->param('bare');
    $c->render( text => Text::Markdown::markdown(do { local $/; <$fh> }) );

}

1;
