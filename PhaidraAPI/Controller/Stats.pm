package PhaidraAPI::Controller::Stats;

use strict;
use warnings;
use v5.10;
use PhaidraAPI::Model::Stats;
use base 'Mojolicious::Controller';

sub stats {
  my $self = shift; 

  my $pid = $self->stash('pid');
  my $siteid = $self->param('siteid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'info', msg => 'Undefined pid' }]}, status => 400);
    return;
  }

  my $key = $self->stash('stats_param_key');

  my $stats_model = PhaidraAPI::Model::Stats->new;
  my $res = $stats_model->stats($self, $pid, $siteid, 'stats');

  if(defined($key)){
    $self->render(text => $res->{$key}, status => $res->{status});
  }else{
    $self->render(json => { stats => { detail_page => $res->{detail_page}, downloads => $res->{downloads} }, alerts => $res->{alerts}, status => $res->{status} }, status => $res->{status});
  }
}

sub chart {
  my $self = shift; 

  my $pid = $self->stash('pid');
  my $siteid = $self->param('siteid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'info', msg => 'Undefined pid' }]}, status => 400);
    return;
  }

  my $key = $self->stash('stats_param_key');

  my $stats_model = PhaidraAPI::Model::Stats->new;
  my $res = $stats_model->stats($self, $pid, $siteid, 'chart');

  if(defined($key)){
    $self->render(text => $res->{$key}, status => $res->{status});
  }else{
    $self->render(json => { stats => { detail_page => $res->{detail_page}, downloads => $res->{downloads} }, alerts => $res->{alerts}, status => $res->{status} }, status => $res->{status});
  }
}

1;
