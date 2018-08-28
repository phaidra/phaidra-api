package PhaidraAPI::Controller::JsonLd;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::ByteStream qw(b);
use Mojo::JSON qw(encode_json decode_json);
use PhaidraAPI::Model::JsonLd;
use PhaidraAPI::Model::Util;
use Time::HiRes qw/tv_interval gettimeofday/;

sub get {
  my $self = shift;

  my $pid = $self->stash('pid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  $object_model->proxy_datastream($self, $pid, 'JSON-LD', undef, undef, 1);
  return;
}

sub post {
  my $self = shift;

  my $t0 = [gettimeofday];

  my $pid = $self->stash('pid');

  my $metadata = $self->param('metadata');
  unless(defined($metadata)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent' }]} , status => 400) ;
    return;
  }

  if(ref $metadata eq 'Mojo::Upload'){
    $self->app->log->debug("Metadata sent as file param");
    $metadata = $metadata->asset->slurp;
    $metadata = decode_json($metadata);
  }else{
    # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
    $metadata = decode_json(b($metadata)->encode('UTF-8'));
  }

  unless(defined($metadata->{metadata})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata found' }]} , status => 400) ;
    return;
  }
  $metadata = $metadata->{metadata};

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  unless(defined($metadata->{jsonld})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No JSON-LD sent' }]} , status => 400) ;
    return;
  }

  my $jsonld_model = PhaidraAPI::Model::JsonLd->new;
  my $res = $jsonld_model->save_to_object($self, $pid, $metadata->{jsonld}, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  my $t1 = tv_interval($t0);
  if($res->{status} eq 200){
    unshift @{$res->{alerts}}, { type => 'success', msg => "JSON-LD for $pid saved successfully ($t1 s)"};
  }

  $self->render(json => { alerts => $res->{alerts} } , status => $res->{status});
}


1;
