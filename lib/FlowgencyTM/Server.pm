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
  $self->defaults( layout => 'general', get_version => sub { $FlowgencyTM::VERSION } );
  unshift @{$self->static->paths}, $self->home->rel_dir('site');

  my $username = $ENV{FLOWTIME_USER} // getpwuid($<);
  FlowgencyTM::user($username) or die "No user $username";

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/')->to('ranking#list')->name('home');
  $r->post('/update')->to('task_editor#fast_bulk_update');
  $r->get('/newtask')->to('task_editor#form');
  $r->any([qw/GET POST/] => '/task/:id/:action')->to(controller => 'task_editor');
   
}

1;
