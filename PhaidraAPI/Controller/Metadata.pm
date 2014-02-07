package PhaidraAPI::Controller::Metadata;

use strict;
use warnings;
use v5.10;
use Mojo::UserAgent;
use Mojo::Util 'squish';
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Metadata;
use Time::HiRes qw/tv_interval gettimeofday/;

sub get {
    my $self = shift;  	
	
	my $t0 = [gettimeofday];

	my $v = $self->param('mfv');
	my $pid = $self->param('pid');
	
	#$self->app->log->info("$pid, $v");		
	unless(defined($v)){		
		$self->stash( msg => 'Unknown metadata format version requested.');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;
		return;
	}
	unless($v eq '1'){		
		$self->stash( msg => 'Unsupported metadata format version.');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
		return;
	}		
	unless(defined($pid)){		
		$self->stash( msg => 'Undefined pid.');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
		return;
	}	
		
	# get metadata datastructure
	my $metadata_model = PhaidraAPI::Model::Metadata->new;	
	my $metadata = $metadata_model->get_object_metadata($self, $v, $pid);
	my $languages = $metadata_model->get_languages($self);
	
	my $t1 = tv_interval($t0);	
	$self->stash( msg => "backend load took $t1 s");
	
    $self->render(json => { metadata => $metadata, languages => $languages, alerts => [{ type => 'success', msg => $self->stash->{msg}}]});
}

sub post {
	my $self = shift;  	
	
	my $t0 = [gettimeofday];

	my $payload = $self->req->json;
	my $v = $payload->{mfv};
	my $pid = $payload->{pid};
	my $metadata = $payload->{metadata};		
	
	unless(defined($v)){		
		$self->stash( msg => 'Unknown metadata format version specified.');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;
		return;
	}
	unless($v eq '1'){		
		$self->stash( msg => 'Unsupported metadata format version specified.');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
		return;
	}		
	unless(defined($pid)){		
		$self->stash( msg => 'Undefined pid.');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
		return;
	}	
	unless(defined($metadata)){		
		$self->stash( msg => 'No data sent.');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
		return;
	}
	
	my $metadata_model = PhaidraAPI::Model::Metadata->new;
	my $res = $metadata_model->save_to_object($self, $pid, $metadata);
	
	my $t1 = tv_interval($t0);	
	unshift @{$res->{alerts}}, { type => 'success', msg => "Object $pid saved successfuly in $t1 s"};
	
	foreach my $alert (@{$res->{alerts}}){
		$self->stash( msg => $alert->{msg} );
	}
	
	$self->render(json => { alerts => $res->{alerts} } , status => $res->{status});
}

sub tree {
    my $self = shift;  	
	
	my $t0 = [gettimeofday];
	
	my $v = $self->param('mfv');
	
	unless(defined($v)){		
		$self->stash( msg => 'Unknown metadata format version requested.');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { msg => $self->stash->{msg}} , status => 500) ;		
		return;
	}	
	
	my $metadata_model = PhaidraAPI::Model::Metadata->new;
	
	my $metadata_tree = $metadata_model->metadata_tree($self, $v);

	if($metadata_tree == -1){
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }] } , status => 500) ;		
		return;
	}
	
	my $languages = $metadata_model->get_languages($self);
	
	my $t1 = tv_interval($t0);	
	$self->stash( msg => "backend load took $t1 s");
	
    $self->render(json => { tree => $metadata_tree, languages => $languages });	
}

sub languages {
	my $self = shift;
	
	# get metadata datastructure
	my $metadata_model = PhaidraAPI::Model::Metadata->new;	
	my $languages = $metadata_model->get_languages($self);
			
    $self->render(json => { languages => $languages});	
}

1;
