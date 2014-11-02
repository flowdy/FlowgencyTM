package FlowTiMeter::Server;
use FlowTiMeter;
use Mojo::Base 'Mojolicious';

# This method will run once at server start
sub startup {
  my $self = shift;

  # Documentation browser under "/perldoc"
  $self->plugin('PODRenderer');
  $self->defaults( layout => 'general' );
  unshift @{$self->static->paths}, $self->home->rel_dir('site');

  my $username = getpwuid($<);
  FlowTiMeter::user($username) or die "No user $username";

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/')->to('ranking#list')->name('home');
  $r->get('/newtask')->to('task_editor#form');
  $r->any([qw/GET POST/] => '/task/:id/:action')->to(controller => 'task_editor');
  
   
}

1;
