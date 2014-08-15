package PhaidraAPI::Controller::Object;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Search;

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
    
    if($self->req->is_limit_exceeded){	
    	$self->render(json => { alerts => [{ type => 'danger', msg => 'File is too big' }]}, status => 400);		
		return;
    }    
    
    unless(defined($self->stash('pid'))){		 	
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]}, status => 400);		
		return;
	}
	
	unless(defined($self->param('mimetype'))){	
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined mimetype' }]}, status => 400);		
		return;
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
	my $post = $ua->post($url => { 'Content-Type' => $self->param('mimetype') } => form => { file => $name } );
		
  	unless(my $r = $post->success) {    	
	  my ($err, $code) = $post->error;
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	  $res->{status} =  $code ? $code : 500;
	}
  		
	$self->render(json => $res, status => $res->{status}) ;
	
}

sub add_datastream {
	
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
	}
	my $controlgroup = $self->param('controlgroup');
	
	my $object_model = PhaidraAPI::Model::Object->new;
	my $r = $object_model->add_datastream($self, $self->stash('pid'), $self->stash('dsid'), $mimetype, $location, $label, $dscontent, $controlgroup, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
	
	$self->render(json => $r, status => $r->{status}) ;
}

1;
