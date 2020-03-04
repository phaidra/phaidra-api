package PhaidraAPI::Controller::Relationships;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Relationships;

sub get_rels_ext {
  my $self = shift;

  my $pid = $self->stash('pid');
  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $model = PhaidraAPI::Model::Relationships->new;
  my $res = $model->get_rels_ext($self, $pid);
  $self->render(json => $res, status => $res->{status});	
}

1;
