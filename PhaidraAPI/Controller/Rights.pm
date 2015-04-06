package PhaidraAPI::Controller::Rights;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Rights;
use Time::HiRes qw/tv_interval gettimeofday/;

sub json2xml {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $payload = $self->req->json;
  my $metadata = $payload->{metadata};

  my $metadata_model = PhaidraAPI::Model::Rights->new;
  my $rightsxml = $metadata_model->json_2_xml($self, $metadata->{rights});

  $self->render(json => { alerts => $res->{alerts}, rights => $rightsxml } , status => $res->{status});
}

sub xml2json {
  my $self = shift;

  my $mode = $self->param('mode');
  my $xml = $self->req->body;

  my $rights_model = PhaidraAPI::Model::Rights->new;
  my $res = $rights_model->xml_2_json($self, $xml, $mode);

  $self->render(json => { rights => $res->{rights}, alerts => $res->{alerts}}  , status => $res->{status});

}

sub validate {
  my $self = shift;

  my $rightsxml = $self->req->body;

  my $util_model = PhaidraAPI::Model::Util->new;
  my $res = $util_model->validate_xml($self, $rightsxml, $self->app->config->{validate_rights});

  $self->render(json => $res , status => $res->{status});
}

sub json2xml_validate {
  my $self = shift;

  my $payload = $self->req->json;
  my $metadata = $payload->{metadata};

  my $rights_model = PhaidraAPI::Model::Rights->new;
  my $rightsxml = $rights_model->json_2_xml($self, $metadata->{rights});
  my $util_model = PhaidraAPI::Model::Util->new;
  my $res = $util_model->validate_xml($self, $rightsxml, $self->app->config->{validate_rights});

  $self->render(json => $res , status => $res->{status});
}


sub get {
  my $self = shift;

  my $pid = $self->stash('pid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $rights_model = PhaidraAPI::Model::Rights->new;
  my $res= $rights_model->get_object_rights_json($self, $pid, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if($res->{status} ne 200){
    if($res->{status} eq 404){
      # no RIGHTS
      $self->render(json => { alerts => $res->{alerts}, rights => {} }, status => $res->{status});
    }
    $self->render(json => { alerts => $res->{alerts} }, status => $res->{status});
    return;
  }

  $self->render(json => $res, status => $res->{status});
}

sub post {
  my $self = shift;

  my $t0 = [gettimeofday];

  my $pid = $self->stash('pid');

  my $payload = $self->req->json;
  my $metadata = $payload->{metadata};

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  unless(defined($metadata->{rights})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No RIGHTS sent' }]} , status => 400) ;
    return;
  }

  my $rights_model = PhaidraAPI::Model::Rights->new;
  my $res = $rights_model->save_to_object($self, $pid, $metadata->{rights}, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  my $t1 = tv_interval($t0);
  if($res->{status} eq 200){
    unshift @{$res->{alerts}}, { type => 'success', msg => "RIGHTS for $pid saved successfuly ($t1 s)"};
  }

  $self->render(json => { alerts => $res->{alerts} } , status => $res->{status});
}


1;
