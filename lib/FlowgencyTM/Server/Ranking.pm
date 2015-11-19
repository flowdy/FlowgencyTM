use strict;

package FlowgencyTM::Server::Ranking;
use FlowgencyTM;
use Mojo::Base 'Mojolicious::Controller';

sub list {
  my $self = shift;

  my %args;
  for my $p_name (@{ $self->req->params->names }) {
      $args{$p_name} = $self->param($p_name);
  }

  my $now;
  if ( delete $args{keep} ) {
      use POSIX qw(strftime);
      $now = delete($args{now}) || strftime("%Y-%m-%d %H:%M:%S", localtime time);
      if ( $c->stash('is_remote') {
          croak 'Cannot set time in remote mode – Would affect other users, too.';
      }
      else { FTM::Time::Spec->now($now); }
  }
  else { $now = $args{now} }

  my @force_include = split q{,}, $args{force_include};
  $args{force_include} = \@force_include;

  my $tasks = $c->stash('user')->get_ranking( \%args );
  $self->res->headers->cache_control('max-age=1, no-cache');

  $now //= FTM::Time::Spec->now();
  $self->render(
    list => $tasks,
    timestamp => ref($tasks[0]) ? $tasks[0]->flowrank->_for_ts : $now,
    force_include => \@force_include,
  );
}

1;
