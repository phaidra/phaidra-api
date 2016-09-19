package PhaidraAPI::Controller::Octets;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Object;

sub get {
  my $self = shift;

  my $pid = $self->stash('pid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  $object_model->proxy_datastream($self, $pid, 'OCTETS', $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password}); 	  
  
}


1;
