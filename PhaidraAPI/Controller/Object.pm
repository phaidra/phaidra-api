package PhaidraAPI::Controller::Object;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(encode decode);
use Mojo::ByteStream qw(b);
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Search;
use Time::HiRes qw/tv_interval gettimeofday/;

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
        if(ref $metadata eq 'Mojo::Upload'){
	  $self->app->log->debug("Metadata sent as file param");
	  $metadata = $metadata->asset->slurp;
          $metadata = decode_json($metadata);
	}else{  
	  # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
	  $metadata = decode_json(b($metadata)->encode('UTF-8'));
	}
	my $mimetype = $self->param('mimetype');
	my $upload = $self->req->upload('file');

  	#$self->app->log->debug($self->app->dumper($upload->asset));

	my $object_model = PhaidraAPI::Model::Object->new;
    my $r = $object_model->create_simple($self, $self->stash('cmodel'), $metadata, $mimetype, $upload, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
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

sub add_octets {
	my $self = shift;

    my $res = { alerts => [], status => 200 };

    my $upload = $self->req->upload('file');

    if($self->req->is_limit_exceeded){
    	$self->render(json => { alerts => [{ type => 'danger', msg => 'File is too big' }]}, status => 400);
		return;
    }

    unless(defined($self->stash('pid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]}, status => 400);
		return;
	}

	unless(defined($self->param('mimetype'))){
      my $object_model = PhaidraAPI::Model::Object->new;
      my $mimetype = $object_model->get_mimetype($self, $upload->asset);
      unshift @{$res->{alerts}}, { type => 'info', msg => "Undefined mimetype, using magic: $mimetype" };
  }

	my $file = $self->param('file');
  	my $size = $file->size;
  	my $name = $file->filename;

  	$self->app->log->debug("Got file: $name [$size]");

	my %params;
    $params{controlGroup} = 'M';
    $params{dsLabel} = $self->app->config->{phaidra}->{defaultlabel};
    $params{mimeType} = $self->param('mimetype');

	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo($self->stash->{basic_auth_credentials}->{username}.":".$self->stash->{basic_auth_credentials}->{password});
	$url->host($self->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/".$self->stash('pid')."/datastreams/OCTETS");
	$url->query(\%params);

	my $ua = Mojo::UserAgent->new;

    my $post = $ua->post($url => { 'Content-Type' => $self->param('mimetype') } => form => { file => { file => $upload->asset }} );

  	unless(my $r = $post->success) {
	  my ($err, $code) = $post->error;
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	  $res->{status} =  $code ? $code : 500;
	}

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

	my $mimetype = $self->param('mimetype');
	my $location = $self->param('location');
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

	my $r = $object_model->add_or_modify_datastream($self, $self->stash('pid'), $self->stash('dsid'), $mimetype, $location, $label, $dscontent, $controlgroup, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

	$self->render(json => $r, status => $r->{status}) ;
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
    unshift @{$res->{alerts}}, { type => 'success', msg => "Metadata for $pid saved successfuly ($t1 s)"};

  }

  $self->render(json => { alerts => $res->{alerts} } , status => $res->{status});

}
1;
