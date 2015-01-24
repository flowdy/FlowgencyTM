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
  my $auth = $r->under(sub {
      my $c = shift;
      my $u = $c->session('user_id');
      if ( $u = FlowgencyTM::user( $u || () ) ) {
          $c->stash( user => $u );
          return 1;
      }
      else {
          $c->redirect_to("/login");
          return undef;
      }
  });

  $r->get("/login")->to("login#form");
  $r->post("/login")->to("login#token");

  # Normal route to controller
  $auth->get('/')->to('ranking#list')->name('home');
  $auth->post('/update')->to('task_editor#fast_bulk_update');
  $auth->get('/newtask')->to('task_editor#form', incr_prefix => 1);
  $auth->any([qw/GET POST/] => '/settings')
       ->to('user_profile#settings');
  $auth->get('/task/archive')->to("ranking#archived");
  $auth->any([qw/GET POST/] => '/task/:id/:action')
       ->to(controller => 'task_editor');
   
}

1;
