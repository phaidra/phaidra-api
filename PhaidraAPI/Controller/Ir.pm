package PhaidraAPI::Controller::Ir;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(encode decode);
use Mojo::ByteStream qw(b);
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Collection;
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Rights;
use Time::HiRes qw/tv_interval gettimeofday/;
use Storable qw(dclone);

sub submit {

  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  $self->app->log->debug("=== params ===");
  for my $pn (@{$self->req->params->names}){
    $self->app->log->debug($pn);
  }
  for my $up (@{$self->req->uploads}){
    $self->app->log->debug($up->{name}.": ".$up->{filename});
  }
  $self->app->log->debug("==============");

  if($self->req->is_limit_exceeded){
    $self->app->log->debug("Size limit exceeded. Current max_message_size:".$self->req->max_message_size);
    $self->render(json => { alerts => [{ type => 'danger', msg => 'File is too big' }]}, status => 400);
    return;
  }

  my $metadata = $self->param('metadata');
  unless($metadata){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent.' }]}, status => 400);
    return;
  }

  eval {
    if(ref $metadata eq 'Mojo::Upload'){
      $self->app->log->debug("Metadata sent as file param");
      $metadata = $metadata->asset->slurp;
      $self->app->log->debug("parsing json");
      $metadata = decode_json($metadata);
    }else{
      $self->app->log->debug("parsing json");
      $metadata = decode_json(b($metadata)->encode('UTF-8'));
    }
  };

  if($@){
    $self->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
    $res->{status} = 400;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  unless(exists($metadata->{metadata}->{'json-ld'}->{'ebucore:filename'})){
    unshift @{$res->{alerts}}, { type => 'danger', msg => "Missing ebucore:filename"};
    $res->{status} = 400;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  unless(exists($metadata->{metadata}->{'json-ld'}->{'ebucore:hasMimeType'})){
    unshift @{$res->{alerts}}, { type => 'danger', msg => "Missing ebucore:hasMimeType"};
    $res->{status} = 400;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my %rights;
  if(exists($metadata->{metadata}->{'json-ld'}->{'dcterms:accessRights'})){
    for my $ar (@{$metadata->{metadata}->{'json-ld'}->{'dcterms:accessRights'}}){
      if(exists($ar->{'skos:exactMatch'})){
        for my $arId (@{$ar->{'skos:exactMatch'}}) {
          # embargo
          if ($arId eq 'https://vocab.phaidra.org/vocabulary/AVFC-ZZSZ') {
            if(exists($metadata->{metadata}->{'json-ld'}->{'dcterms:available'})){
              for my $embargoDate (@{$metadata->{metadata}->{'json-ld'}->{'dcterms:available'}}) {
                $rights{'username'} = (
                  {
                    value => $username,
                    expires => $embargoDate
                  }
                );
                last;
              }
            }
          }
          # closed
          if ($arId eq 'https://vocab.phaidra.org/vocabulary/QNGE-V02H') {
            $rights{'username'} = $username;
          }
        }
      }
    }
    
  }

  my @filenames = @{$metadata->{metadata}->{'json-ld'}->{'ebucore:filename'}};
  my @mimetypes = @{$metadata->{metadata}->{'json-ld'}->{'ebucore:hasMimeType'}};

  my $object_model = PhaidraAPI::Model::Object->new;

  my $cnt = scalar @filenames;
  my $mainObjectPid;
  my @alternativeFormatPids;
  for (my $i = 0; $i < $cnt; $i++) {
    my $filename = $filenames[$i];
    my $mimetype = $mimetypes[$i];

    my $fileupload;
    for my $up (@{$self->req->uploads}){
      if ($filename eq $up->{filename}) {
        $fileupload = $up;
      }
    }
    unless(defined($fileupload)){
      unshift @{$res->{alerts}}, { type => 'danger', msg => "Missing file [$filename]"};
      $res->{status} = 400;
      $self->render(json => $res, status => $res->{status});
      return;
    }

    my $size = $fileupload->size;
    my $name = $fileupload->filename;
    $self->app->log->debug("Found file: $name [$size B]");

    my $jsonld = dclone($metadata->{metadata}->{'json-ld'});

    my @filenameArr = ($filename);
    $jsonld->{'ebucore:filename'} = \@filenameArr;
    my @mimetypeArr = ($mimetype);
    $jsonld->{'ebucore:hasMimeType'} = \@mimetypeArr;

    my $isAlternativeFormat = 0;
    my $cmodel;
    if ($mimetype eq 'application/pdf' || $mimetype eq 'application/x-pdf') {
      $cmodel = 'cmodel:PDFDocument';
    } else {
      $cmodel = 'cmodel:Asset';
      $isAlternativeFormat = 1;
    }

    my $md = {
      metadata => {
        'json-ld' => $jsonld
      }
    };

    if(exists($rights{'username'})){
      $md->{metadata}->{rights} => \%rights;
    }

    my $r = $object_model->create_simple($self, $cmodel, $md, $mimetype, $fileupload, $username, $password);
    if($r->{status} ne 200){
      $res->{status} = 500;
      unshift @{$res->{alerts}}, @{$r->{alerts}};
      unshift @{$res->{alerts}}, { type => 'danger', msg => "Error creating object [filename=$filename]"};
      $self->render(json => $res, status => $res->{status});
      return;
    }

    if ($isAlternativeFormat) {
      push @alternativeFormatPids, $r->{pid};
    } else {
      $mainObjectPid = $r->{pid};
    }
  }

  for my $alternativeFromatPid (@alternativeFormatPids) {

    my @relationships = (
      {
        predicate => "http://phaidra.org/XML/V1.0/relations#isAlternativeFormatOf", 
        object => "info:fedora/".$mainObjectPid
      }
    );

    $self->app->log->debug("Adding relationships[".$self->app->dumper(\@relationships)."] to pid[$alternativeFromatPid]");

    my $r = $object_model->add_relationships($self, $alternativeFromatPid, \@relationships, $username, $password);
    push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
    if($r->{status} ne 200){
      $self->app->log->error("Error adding relationships[".$self->app->dumper(\@relationships)."] pid[$alternativeFromatPid] res[".$self->app->dumper($res)."]");
      # continue, this isn't fatal
    }
  }

  $res->{pid} = $mainObjectPid;
  $res->{alternatives} = \@alternativeFormatPids;

  $self->render(json => $res, status => $res->{status});
}

1;
