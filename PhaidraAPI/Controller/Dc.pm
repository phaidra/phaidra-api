package PhaidraAPI::Controller::Dc;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Dc;

sub get {

  my $self = shift;
  my $dsid = $self->stash('dsid');

  my $pid = $self->stash('pid');
  my $format = $self->param('format');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  if($format eq 'xml'){
    my $object_model = PhaidraAPI::Model::Object->new;
    $object_model->proxy_datastream($self, $pid, $dsid, undef, undef, 1);
    return;
  }

  my $dc_model = PhaidraAPI::Model::Dc->new;

  my $res= $dc_model->get_object_dc_json($self, $pid, $dsid, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if($res->{status} ne 200){
    if($res->{status} eq 404){
      my $dclab = $dsid eq 'DC_P' ? 'dc' : 'oai_dc';
      $self->render(json => { alerts => $res->{alerts}, $dclab => {} }, status => $res->{status});
    }
    $self->render(json => { alerts => $res->{alerts} }, status => $res->{status});
    return;
  }

  $self->render(json => { metadata => $res }, status => $res->{status});
}


sub xml2json {
  my $self = shift;

  my $xml = $self->req->body;

  my $dc_model = PhaidraAPI::Model::Dc->new;
  my $res = $dc_model->xml_2_json($self, $xml, 'dc');

  $self->render(json => { metadata => { dc => $res->{dc} }, alerts => $res->{alerts}}, status => $res->{status});
}

1;
