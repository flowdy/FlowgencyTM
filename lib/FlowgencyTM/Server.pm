package FlowgencyTM::Server;
use FlowgencyTM;
use Mojolicious 6.0;
use Mojo::Base 'Mojolicious';

# use Tie::File;
# tie my @SLOGAN => 'Tie::File', 'slogans.txt';

# This method will run once at server start
sub startup {
  my $self = shift;

  # Documentation browser under "/perldoc"
  $self->plugin('PODRenderer');
  $self->secrets([rand]);

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
  unshift @{$self->static->paths}, $self->home->rel_dir('site');

  # Router
  my $r = $self->routes;
  my $auth = $r->under(sub {
      my $c = shift;

      my $is_remote = index( $ENV{MOJO_LISTEN}//q{}, $c->tx->remote_address ) < 0;
      # Prevent autologin unless server is requested from the same machine
      local $ENV{FLOWGENCYTM_USER} = undef if $is_remote;

      if ( !$c->stash('hoster_info') ) {
          $c->stash( hoster_info => $is_remote ? '(private remote)' : '(local)' );
      }

      $c->stash( is_remote => $is_remote );
          
      my $user_id = $c->session('user_id');
      if ( !$user_id and my $default_user = $ENV{FLOWGENCYTM_USER} ) {
          $c->session( user_id => $default_user );
          $user_id = $default_user;
      }

      my $user = FlowgencyTM::user( $user_id || () );
      if ( $user && $user->can_login ) {
          $c->stash( user => $user );
          return 1;
      }
      else {
          $c->redirect_to("/user/login");
          return undef;
      }

  });

  $r->any( [qw/GET POST/] => "/user/login" )->to("user#login" );
  $r->get( '/user/logout' )->to("user#logout");
  my $admin = $auth->under(sub { shift->stash('user')->can_admin })
      ->get('/admin');
  $admin->get('/')->to('admin#dash');
  $admin->get('/:action')->to(controller => 'admin');

  $r->post('/user/join')->to("user#join");

  # Normal route to controller
  $auth->get('/')->to('ranking#list')->name('home');
  
  $auth->get('/info')->to('info#basic');
  $auth->post('/update')->to('task_editor#fast_bulk_update');
  $auth->get('/newtask')->to('task_editor#form', incr_prefix => 1);
  $auth->any([qw/GET POST/] => '/user/settings')
       ->to('user#settings');
  $auth->get('/task/archive')->to("ranking#archived");
  $auth->any([qw/GET POST/] => '/task/:id/:action')
       ->to(controller => 'task_editor');

}

my $started_time;
BEGIN { $started_time = scalar localtime(); }
sub get_started_time { $started_time; }

1;
