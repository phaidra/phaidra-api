package PhaidraAPI::Controller::Annotations;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::ByteStream qw(b);
use Mojo::JSON qw(encode_json decode_json);
use PhaidraAPI::Model::Annotations;
use PhaidraAPI::Model::Util;
use Time::HiRes qw/tv_interval gettimeofday/;

sub json2xml {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $metadata = $self->param('metadata');
  unless(defined($metadata)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent' }]} , status => 400) ;
    return;
  }

  eval {
    if(ref $metadata eq 'Mojo::Upload'){
      $self->app->log->debug("Metadata sent as file param");
      $metadata = $metadata->asset->slurp;
      $self->app->log->debug("parsing json");
      $metadata = decode_json($metadata);
    }else{
      # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
      $self->app->log->debug("parsing json");
      $metadata = decode_json(b($metadata)->encode('UTF-8'));
    }
  };

  if($@){
    $self->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
    $res->{status} = 400;
    $self->render(json => $res , status => $res->{status});
    return;
  }

  unless(defined($metadata->{metadata})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata found' }]} , status => 400) ;
    return;
  }
  $metadata = $metadata->{metadata};

  my $metadata_model = PhaidraAPI::Model::Annotations->new;
  my $annotationsxml = $metadata_model->json_2_xml($self, $metadata->{annotations});

  $self->render(json => { alerts => $res->{alerts}, metadata => { annotations => $annotationsxml } } , status => $res->{status});
}

sub xml2json {
  my $self = shift;

  my $mode = $self->param('mode');
  my $xml = $self->req->body;

  my $annotations_model = PhaidraAPI::Model::Annotations->new;
  my $res = $annotations_model->xml_2_json($self, $xml, $mode);

  $self->render(json => { metadata => { annotations => $res->{annotations} }, alerts => $res->{alerts}}  , status => $res->{status});

}

sub validate {
  my $self = shift;

  my $annotationsxml = $self->req->body;

  my $util_model = PhaidraAPI::Model::Util->new;
  my $res = $util_model->validate_xml($self, $annotationsxml, $self->app->config->{validate_annotations});

  $self->render(json => $res , status => $res->{status});
}

sub json2xml_validate {
  my $self = shift;

  my $metadata = $self->param('metadata');
  unless(defined($metadata)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent' }]} , status => 400) ;
    return;
  }

  eval {
    if(ref $metadata eq 'Mojo::Upload'){
      $self->app->log->debug("Metadata sent as file param");
      $metadata = $metadata->asset->slurp;
      $self->app->log->debug("parsing json");
      $metadata = decode_json($metadata);
    }else{
      # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
      $self->app->log->debug("parsing json");
      $metadata = decode_json(b($metadata)->encode('UTF-8'));
    }
  };

  if($@){
    $self->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
    $res->{status} = 400;
    $self->render(json => $res , status => $res->{status});
    return;
  }

  unless(defined($metadata->{metadata})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata found' }]} , status => 400) ;
    return;
  }
  $metadata = $metadata->{metadata};

  my $annotations_model = PhaidraAPI::Model::Annotations->new;
  my $annotationsxml = $annotations_model->json_2_xml($self, $metadata->{annotations});
  my $util_model = PhaidraAPI::Model::Util->new;
  my $res = $util_model->validate_xml($self, $annotationsxml, $self->app->config->{validate_annotations});

  $self->render(json => $res, status => $res->{status});
}


sub get {
  my $self = shift;

  my $pid = $self->stash('pid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $annotations_model = PhaidraAPI::Model::Annotations->new;
  my $res = $annotations_model->get_object_annotations_json($self, $pid, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if($res->{status} ne 200){
    if($res->{status} eq 404){
      # no ANNOTATIONS
      $self->render(json => { alerts => $res->{alerts}, annotations => {} }, status => $res->{status});
    }
    $self->render(json => { alerts => $res->{alerts} }, status => $res->{status});
    return;
  }

  $self->render(json => { metadata => $res }, status => $res->{status});
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

  eval {
    if(ref $metadata eq 'Mojo::Upload'){
      $self->app->log->debug("Metadata sent as file param");
      $metadata = $metadata->asset->slurp;
      $self->app->log->debug("parsing json");
      $metadata = decode_json($metadata);
    }else{
      # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
      $self->app->log->debug("parsing json");
      $metadata = decode_json(b($metadata)->encode('UTF-8'));
    }
  };

  if($@){
    $self->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
    $res->{status} = 400;
    $self->render(json => $res , status => $res->{status});
    return;
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

  unless(defined($metadata->{annotations})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No ANNOTATIONS sent' }]} , status => 400) ;
    return;
  }

  my $annotations_model = PhaidraAPI::Model::Annotations->new;
  my $res = $annotations_model->save_to_object($self, $pid, $metadata->{annotations}, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  my $t1 = tv_interval($t0);
  if($res->{status} eq 200){
    unshift @{$res->{alerts}}, { type => 'success', msg => "ANNOTATIONS for $pid saved successfully ($t1 s)"};
  }

  $self->render(json => { alerts => $res->{alerts} } , status => $res->{status});
}


1;
