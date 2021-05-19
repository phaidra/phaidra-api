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

  unless (defined($pid)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  $object_model->proxy_datastream($self, $pid, 'OCTETS', $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
}

sub get {
  my $self = shift;

  my $res = {alerts => [], status => 200};

  my $pid = $self->stash('pid');
  unless (defined($pid)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }
  my $operation = $self->stash('operation');
  unless (defined($operation)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined operation'}]}, status => 400);
    return;
  }

  my $authz_model = PhaidraAPI::Model::Authorization->new;
  my $authzres    = $authz_model->check_rights($self, $pid, 'ro');
  if ($authzres->{status} != 200) {
    $res->{status} = $authzres->{status};
    push @{$res->{alerts}}, @{$authzres->{alerts}} if scalar @{$authzres->{alerts}} > 0;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r_oxml       = $object_model->get_foxml($self, $pid);
  if ($r_oxml->{status} ne 200) {
    $self->render(json => $r_oxml, status => $r_oxml->{status});
    return;
  }
  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($r_oxml->{foxml});

  my ($filename, $mimetype, $size, $path);
  my $octets_model = PhaidraAPI::Model::Octets->new;

  my $trywebversion = $self->param('trywebversion');
  if ($trywebversion) {
    my $parthres = $octets_model->_get_ds_path($self, $pid, 'WEBVERSION');
    if ($parthres->{status} == 200) {
      $path = $parthres->{path};
      ($filename, $mimetype, $size) = $octets_model->_get_ds_attributes($self, $pid, 'WEBVERSION', $dom);
    }
  }

  unless ($path) {
    my $parthres = $octets_model->_get_ds_path($self, $pid, 'OCTETS');
    if ($parthres->{status} != 200) {
      $res->{status} = $parthres->{status};
      push @{$res->{alerts}}, @{$parthres->{alerts}} if scalar @{$parthres->{alerts}} > 0;
      $self->render(json => $res, status => $res->{status});
      return;
    }
    else {
      $path = $parthres->{path};
    }
    ($filename, $mimetype, $size) = $octets_model->_get_ds_attributes($self, $pid, 'OCTETS', $dom);
  }

  $self->app->log->debug("operation[$operation] trywebversion[$trywebversion] pid[$pid] path[$path] mimetype[$mimetype] filename[$filename] size[$size]");

  if ($operation eq 'download') {
    $self->res->headers->content_disposition("attachment;filename=$filename");
  }
  else {
    $self->res->headers->content_disposition("filename=$filename");
  }
  $self->res->headers->content_type($mimetype);

  my $asset = Mojo::Asset::File->new(path => $path);

  # Range
  # based on Mojolicious::Plugin::RenderFile
  if (my $range = $self->req->headers->range) {
    my $start = 0;
    my $size  = $asset->size;
    my $end   = $size - 1 >= 0 ? $size - 1 : 0;

    # Check range
    if ($range =~ m/^bytes=(\d+)-(\d+)?/ && $1 <= $end) {
      $start = $1;
      $end   = $2 if defined $2 && $2 <= $end;

      $res->{status} = 206;
      $self->res->headers->add('Content-Length' => $end - $start + 1);
      $self->res->headers->add('Content-Range'  => "bytes $start-$end/$size");
    }
    else {
      # Not satisfiable
      return $self->rendered(416);
    }

    # Set range for asset
    $asset->start_range($start)->end_range($end);
  }
  else {
    $self->res->headers->add('Content-Length' => $asset->size);
  }

  $self->res->content->asset($asset);
  $self->rendered($res->{status});
}

1;
