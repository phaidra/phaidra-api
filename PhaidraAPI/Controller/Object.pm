package PhaidraAPI::Controller::Object;

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
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Geo;
use PhaidraAPI::Model::Mods;
use Time::HiRes qw/tv_interval gettimeofday/;

sub info {
  my $self = shift;

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

	unless(defined($self->stash('pid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

	my $object_model = PhaidraAPI::Model::Object->new;
  my $r = $object_model->info($self, $self->stash('pid'), $username, $password);

  $self->render(json => $r, status => $r->{status}) ;
}

sub delete {
  my $self = shift;

	unless(defined($self->stash('pid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

	my $object_model = PhaidraAPI::Model::Object->new;
  my $r = $object_model->delete($self, $self->stash('pid'), $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  $self->render(json => $r, status => $r->{status}) ;
}

sub modify {
    my $self = shift;

	unless(defined($self->stash('pid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

	my $state = $self->param('state');
	my $label = $self->param('label');
	my $ownerid = $self->param('ownerid');
	my $logmessage = $self->param('logmessage');
	my $lastmodifieddate = $self->param('lastmodifieddate');

	my $object_model = PhaidraAPI::Model::Object->new;
    my $r = $object_model->modify($self, $self->stash('pid'), $state, $label, $ownerid, $logmessage, $lastmodifieddate, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

   	$self->render(json => $r, status => $r->{status}) ;
}

sub get_state {
  my $self = shift;

  unless(defined($self->stash('pid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

  my $search_model = PhaidraAPI::Model::Search->new;
  my $r = $search_model->get_state($self, $self->stash('pid'));

  $self->render(json => $r, status => $r->{status}) ;
}

sub get_cmodel {
  my $self = shift;

  unless(defined($self->stash('pid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

  my $search_model = PhaidraAPI::Model::Search->new;
  my $r = $search_model->get_cmodel($self, $self->stash('pid'));

  $self->render(json => $r, status => $r->{status}) ;
}

sub create {
    my $self = shift;

	my $object_model = PhaidraAPI::Model::Object->new;
    my $r = $object_model->create($self, $self->stash('cmodel'), $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

   	$self->render(json => $r, status => $r->{status}) ;
}

sub create_empty {
    my $self = shift;

	my $object_model = PhaidraAPI::Model::Object->new;
    my $r = $object_model->create_empty($self, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

   	$self->render(json => $r, status => $r->{status}) ;
}

sub create_simple {

	my $self = shift;

	my $res = { alerts => [], status => 200 };

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

	my $mimetype = $self->param('mimetype');
	my $upload = $self->req->upload('file');
  my $checksumtype = $self->param('checksumtype');
	my $checksum = $self->param('checksum');

	my $object_model = PhaidraAPI::Model::Object->new;
    my $r = $object_model->create_simple($self, $self->stash('cmodel'), $metadata, $mimetype, $upload, $checksumtype, $checksum, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
   	if($r->{status} ne 200){
   		$res->{status} = $r->{status};
      foreach my $a (@{$r->{alerts}}){
        unshift @{$res->{alerts}}, $a;
      }

		  unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error creating '.$self->stash('cmodel').' object'};
   		$self->render(json => $res, status => $res->{status});
   		return;
   	}

   	foreach my $a (@{$r->{alerts}}){
      unshift @{$res->{alerts}}, $a;
    }
	$res->{status} = $r->{status};
	$res->{pid} = $r->{pid};

	$self->render(json => $res, status => $res->{status});
}

sub create_container {

	my $self = shift;

	my $res = { alerts => [], status => 200 };

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

	my $object_model = PhaidraAPI::Model::Object->new;
  my $r = $object_model->create_container($self, $metadata, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if($r->{status} ne 200){
    $res->{status} = $r->{status};
    foreach my $a (@{$r->{alerts}}){
      unshift @{$res->{alerts}}, $a;
    }
    unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error creating '.$self->stash('cmodel').' object'};
    $self->render(json => $res, status => $res->{status});
    return;
  }

  foreach my $a (@{$r->{alerts}}){
    unshift @{$res->{alerts}}, $a;
  }
	$res->{status} = $r->{status};
	$res->{pid} = $r->{pid};

	$self->render(json => $res, status => $res->{status});
}

sub add_relationship {

	my $self = shift;

    unless(defined($self->stash('pid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

    my $predicate = $self->param('predicate');
	my $object = $self->param('object');

	my $object_model = PhaidraAPI::Model::Object->new;
    my $r = $object_model->add_relationship($self, $self->stash('pid'), $predicate, $object, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

   	$self->render(json => $r, status => $r->{status}) ;

}

sub purge_relationship {

	my $self = shift;
    unless(defined($self->stash('pid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

  my $predicate = $self->param('predicate');
	my $object = $self->param('object');

	my $object_model = PhaidraAPI::Model::Object->new;
  my $r = $object_model->purge_relationship($self, $self->stash('pid'), $predicate, $object, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  $self->render(json => $r, status => $r->{status}) ;

}

sub add_or_remove_identifier {

  my $self = shift;

  my $pid = $self->stash('pid');
  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400);
    return;
  }

  my $operation = $self->stash('operation');  
  unless($operation){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Unknown operation' }]} , status => 400);
    return;
  }

  my @ids;
  if($self->param('hdl')){
    push @ids, "hdl:".$self->param('hdl');
  }
  if($self->param('doi')){
    push @ids, "doi:".$self->param('doi');
  }
  if($self->param('urn')){
    push @ids, $self->param('urn');
  }

  unless(scalar @ids > 0){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No known identifier sent (param should be [hdl|doi|urn])' }]} , status => 400);
    return;
  }  

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r;
  for my $id (@ids){
    if($operation eq 'add'){
      $r = $object_model->add_relationship($self, $pid, 'http://purl.org/dc/terms/identifier', $id, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
    }elsif($operation eq 'remove'){
      $r = $object_model->purge_relationship($self, $pid, 'http://purl.org/dc/terms/identifier', $id, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
    }
  }

  $self->render(json => $r, status => $r->{status}) ;

}

sub add_octets {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $object_model = PhaidraAPI::Model::Object->new;

  my $upload = $self->req->upload('file');

  if($self->req->is_limit_exceeded){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'File is too big' }]}, status => 400);
    return;
  }

  unless(defined($self->stash('pid'))){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]}, status => 400);
    return;
  }

  my $mimetype;
  if(defined($self->param('mimetype'))){
    $mimetype = $self->param('mimetype');
  }else{
    $mimetype = $object_model->get_mimetype($self, $upload->asset);
    unshift @{$res->{alerts}}, { type => 'info', msg => "Undefined mimetype, using magic: $mimetype" };
  }

  my $file = $self->param('file');
  my $pid = $self->stash('pid');
  my $checksumtype = $self->param('checksumtype');
	my $checksum = $self->param('checksum');

  my $addres = $object_model->add_octets($self, $pid, $upload, $file, $mimetype, $checksumtype, $checksum);
  push @{$res->{alerts}}, @{$addres->{alerts}} if scalar @{$addres->{alerts}} > 0;
  $res->{status} = $addres->{status};

  $self->render(json => $res, status => $res->{status}) ;
}

sub add_or_modify_datastream {

	my $self = shift;

  unless(defined($self->stash('pid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

	unless(defined($self->stash('dsid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined dsid' }]} , status => 400) ;
		return;
	}

  unless(defined($self->param('mimetype'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined mimetype' }]} , status => 400) ;
		return;
	}

	my $mimetype = $self->param('mimetype');
	my $location = $self->param('location');
  my $checksumtype = $self->param('checksumtype');
	my $checksum = $self->param('checksum');
	my $label = undef;
	if($self->param('dslabel')){
		$label = $self->param('dslabel');
	}
	my $dscontent = undef;
	if($self->param('dscontent')){
		$dscontent = $self->param('dscontent');
    if(ref $dscontent eq 'Mojo::Upload'){
      # this is a file upload
      $self->app->log->debug("Parameter dscontent is a file parameter file=[".$dscontent->filename."] size=[".$dscontent->size."]");
      $dscontent = $dscontent->asset->slurp;
    }else{
      # $self->app->log->debug("Parameter dscontent is a text parameter");
    }
	}

	my $controlgroup = $self->param('controlgroup');

	my $object_model = PhaidraAPI::Model::Object->new;

	my $r = $object_model->add_or_modify_datastream($self, $self->stash('pid'), $self->stash('dsid'), $mimetype, $location, $label, $dscontent, $controlgroup, $checksumtype, $checksum, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

	$self->render(json => $r, status => $r->{status}) ;
}

sub get_metadata {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $pid = $self->stash('pid');

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};
  
  my $mode = $self->param('mode');

  unless(defined($mode)){
    $mode = 'basic';
  }

  my $search_model = PhaidraAPI::Model::Search->new;
  my $r = $search_model->datastreams_hash($self, $pid);
  if($r->{status} ne 200){
    return $r;
  }

  if($r->{dshash}->{'JSON-LD'}){   
    my $jsonld_model = PhaidraAPI::Model::Jsonld->new;  
    my $r_jsonld = $jsonld_model->get_object_jsonld_parsed($self, $pid, $username, $password);
    if($r_jsonld->{status} ne 200){
      push @{$res->{alerts}}, @{$r_jsonld->{alerts}} if scalar @{$r_jsonld->{alerts}} > 0;
      push @{$res->{alerts}}, { type => 'danger', msg => 'Error getting JSON-LD' };
    }else{
      $res->{metadata}->{'JSON-LD'} = $r_jsonld->{'JSON-LD'};
    }
  }

  if($r->{dshash}->{'JSON-LD-PRIVATE'}){
    my $jsonldprivate_model = PhaidraAPI::Model::Jsonldprivate->new;  
    my $r_jsonldprivate = $jsonldprivate_model->get_object_jsonldprivate_parsed($self, $pid, $username, $password);
    if($r_jsonldprivate->{status} ne 200){
      push @{$res->{alerts}}, @{$r_jsonldprivate->{alerts}} if scalar @{$r_jsonldprivate->{alerts}} > 0;
      push @{$res->{alerts}}, { type => 'danger', msg => 'Error getting JSON-LD-PRIVATE' };
    }else{
      $res->{metadata}->{'JSON-LD-PRIVATE'} = $r_jsonldprivate->{'JSON-LD-PRIVATE'};
    }
  }

  if($r->{dshash}->{'MODS'}){   
    my $mods_model = PhaidraAPI::Model::Mods->new;
    my $r = $mods_model->get_object_mods_json($self, $pid, $mode, $username, $password);
    if($r->{status} ne 200){
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      push @{$res->{alerts}}, { type => 'danger', msg => 'Error getting MODS' };
    }else{
      $res->{metadata}->{mods} = $r->{mods};
    }
  }

  if($r->{dshash}->{'UWMETADATA'}){   
    my $uwmetadata_model = PhaidraAPI::Model::Uwmetadata->new;
    my $r = $uwmetadata_model->get_object_metadata($self, $pid, $mode, $username, $password);
    if($r->{status} ne 200){
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      push @{$res->{alerts}}, { type => 'danger', msg => 'Error getting UWMETADATA' };
    }else{
      $res->{metadata}->{uwmetadata} = $r->{uwmetadata};
    }
  }

  if($r->{dshash}->{'GEO'}){
    my $geo_model = PhaidraAPI::Model::Geo->new;
    my $r = $geo_model->get_object_geo_json($self, $pid, $username, $password);
    if($r->{status} ne 200){
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      push @{$res->{alerts}}, { type => 'danger', msg => 'Error getting GEO' };
    }else{
      $res->{metadata}->{geo} = $r->{geo};
    }
  }

  if($r->{dshash}->{'RIGHTS'}){
    my $rights_model = PhaidraAPI::Model::Rights->new;
    my $r = $rights_model->get_object_rights_json($self, $pid, $username, $password);
    if($r->{status} ne 200){
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      push @{$res->{alerts}}, { type => 'danger', msg => 'Error getting RIGHTS' };
    }else{
      $res->{metadata}->{rights} = $r->{rights};
    }
  }
  
  $self->render(json => $res , status => $res->{status});
}

sub metadata {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

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

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r = $object_model->save_metadata($self, $pid, $metadata, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if($r->{status} ne 200){
      $res->{status} = $r->{status};
      foreach my $a (@{$r->{alerts}}){
        unshift @{$res->{alerts}}, $a;
      }
      unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving metadata'};

  }else{
    my $t1 = tv_interval($t0);
    unshift @{$res->{alerts}}, { type => 'success', msg => "Metadata for $pid saved successfully ($t1 s)"};

  }

  $self->render(json => $res, status => $res->{status});

}

# Diss method is for calling the disseminator which is api-a access, so it can also be called without credentials.
# However, if the credentials are necessary, we want to send 401 so that the browser creates login prompt. Fedora sends 403
# in such case which won't create login prompt, so user cannot access locked object even if he should be able to login.
sub diss {
  my $self = shift;

  my $pid = $self->stash('pid');
  my $bdef = $self->stash('bdef');
  my $method = $self->stash('method');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  # do we have access without credentials?
  unless($self->stash->{basic_auth_credentials}->{username}){
    my $res = $object_model->get_datastream($self, $pid, 'READONLY', undef, undef);
    $self->app->log->info("pid[$pid] read rights: ".$res->{status});
    unless($res->{status} eq '404'){
      $self->res->headers->www_authenticate('Basic');
      $self->render(json => { alerts => [{ type => 'danger', msg => 'authentication needed' }]} , status => 401) ;  
      return;
    }
  }

  my $url = Mojo::URL->new;
  $url->scheme('https');
  $url->host($self->app->config->{phaidra}->{fedorabaseurl});
  $url->userinfo($self->stash->{basic_auth_credentials}->{username}.":".$self->stash->{basic_auth_credentials}->{password}) if $self->stash->{basic_auth_credentials}->{username};
  $url->path("/fedora/get/$pid/bdef:$bdef/$method");

  $self->app->log->info("user[".$self->stash->{basic_auth_credentials}->{username}."] proxying $url");

  if (Mojo::IOLoop->is_running) {
    $self->render_later;
    $self->ua->get(
      $url,
      sub {
        my ($c, $tx) = @_;
        _proxy_tx($self, $tx);
      }
    );
  }else {
    my $tx = $self->ua->get($url);
    _proxy_tx($self, $tx);
  }
}

sub _proxy_tx {
  my ($c, $tx) = @_;
  if (my $res = $tx->success) {
    $c->tx->res($res);
    $c->rendered;
  }
  else {
    my $error = $tx->error;
    $c->tx->res->headers->add('X-Remote-Status', $error->{code} . ': ' . $error->{message});
    $c->render(status => 500, text => 'Failed to fetch data from Fedora: '.$c->app->dumper($tx->error));
  }
}

1;
