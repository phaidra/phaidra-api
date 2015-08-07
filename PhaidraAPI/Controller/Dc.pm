package PhaidraAPI::Controller::Dc;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Object;

sub get_oai_dc {
  my $self = shift;

  my $pid = $self->stash('pid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;  
  # return XML directly
  $object_model->proxy_datastream($self, $pid, 'DC_OAI', undef, undef, 1);
}

sub get_dc {
  my $self = shift;

  my $pid = $self->stash('pid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;  
  # return XML directly
  $self->app->log->debug($self->stash->{basic_auth_credentials}->{username}.":".$self->stash->{basic_auth_credentials}->{password});
  $object_model->proxy_datastream($self, $pid, 'DC_P', undef, undef, 1);
}

1;
