package PhaidraAPI::Controller::Octets;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Octets;
use PhaidraAPI::Model::Authorization;
use PhaidraAPI::Model::Index;

sub proxy {
  my $self = shift;

  my $pid = $self->stash('pid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400);
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  $object_model->proxy_datastream($self, $pid, 'OCTETS', $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
}

sub get {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $pid = $self->stash('pid');
  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400);
    return;
  }
  my $operation = $self->stash('operation');
  unless(defined($operation)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined operation' }]} , status => 400);
    return;
  }

  my $authz_model = PhaidraAPI::Model::Authorization->new;
  my $authzres = $authz_model->check_rights($self, $pid, 'ro');
  if ($authzres->{status} != 200) {
    $res->{status} = $authzres->{status};
    push @{$res->{alerts}}, @{$authzres->{alerts}} if scalar @{$authzres->{alerts}} > 0;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my $octets_model = PhaidraAPI::Model::Octets->new;
  my $parthres = $octets_model->_get_octets_path($self, $pid);
  if ($parthres->{status} != 200) {
    $res->{status} = $parthres->{status};
    push @{$res->{alerts}}, @{$parthres->{alerts}} if scalar @{$parthres->{alerts}} > 0;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my ($filename, $mimetype) = $self->get_filename_mimetype($pid);

  $self->app->log->debug("operation[$operation] pid[$pid] path[".$parthres->{path}."] mimetype[$mimetype] filename[$filename]");

  if ($operation eq 'download') {
    $self->res->headers->content_disposition("attachment;filename=$filename");
  } else {
    $self->res->headers->content_disposition("filename=$filename");
  }
  $self->res->headers->content_type($mimetype);
  $self->res->content->asset(Mojo::Asset::File->new(path => $parthres->{path}));
  $self->rendered(200);
}

sub get_filename_mimetype {
  my $self = shift;
  my $pid = shift;

  my $res = { alerts => [], status => 200 };

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r_oxml = $object_model->get_foxml($self, $pid);
  if($r_oxml->{status} ne 200){
    $self->app->log->error("pid[$pid] could not determine filename and mimetype from OCTETS->LABEL, failed reading foxml: ".$self->app->dumper($r_oxml));
    return ($pid, 'application/octet-stream');
  }
  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($r_oxml->{foxml});
  for my $e ($dom->find('foxml\:datastream[ID="OCTETS"]')->each){
    my $latestVersion = $e->find('foxml\:datastreamVersion')->first;
    for my $e1 ($e->find('foxml\:datastreamVersion')->each){
      if($e1->attr('CREATED') gt $latestVersion->attr('CREATED')){
        $latestVersion = $e1;
      }
    }
    return ($latestVersion->attr('LABEL'), $latestVersion->attr('MIMETYPE'));
  }

  $self->app->log->error("pid[$pid] could not determine filename and mimetype from OCTETS->LABEL");
  return ($pid, 'application/octet-stream');
}

1;
