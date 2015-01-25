package FlowgencyTM::Server;
use FlowgencyTM;
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
      revision => {
          version => $FlowgencyTM::VERSION,
          commit_id => qx{git rev-list -1 HEAD},
          changes => qx{git diff-index --shortstat HEAD}
                         || 'without uncommitted changes',
          server_started => scalar localtime(time),
     }
  );
  unshift @{$self->static->paths}, $self->home->rel_dir('site');

  # Router
  my $r = $self->routes;
  $r->get("/user/login")->to("login#form");
  my $auth = $r->under(sub {
      my $c = shift;

      my $ip = $c->tx->remote_address;
      # Prevent autologin unless server is requested from the same machine
      local $ENV{FLOWGENCYTM_USER} = undef
          if ( index( $ENV{MOJO_LISTEN}//q{}, $ip ) < 0 );
          
      my $user = FlowgencyTM::user( $c->session('user_id') || () );
      if ( $user && $user->can_login ) {
          $c->stash( user => $user );
          return 1;
      }
      else {
          $c->redirect_to("/user/login");
          return undef;
      }

  });

  my $admin = $auth->under(sub { shift->stash('user')->can_admin })
      ->get('/admin')->to("admin#dash");

  $r->post('/user/login')->to("login#token");
  $r->get('/user/:type/:token')->to("user_profile#confirm");
  $r->post('/user/join')->to("user_profile#create_user");

  # Normal route to controller
  $auth->get('/')->to('ranking#list')->name('home');
  
  $auth->post('/update')->to('task_editor#fast_bulk_update');
  $auth->get('/newtask')->to('task_editor#form', incr_prefix => 1);
  $auth->any([qw/GET POST/] => '/user/settings')
       ->to('user_profile#settings');
  $auth->get('/task/archive')->to("ranking#archived");
  $auth->any([qw/GET POST/] => '/task/:id/:action')
       ->to(controller => 'task_editor');

}

1;
