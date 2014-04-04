package PhaidraAPI::Controller::Collection;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Collection;

sub add_collection_member {
	my $token = shift;
	
}

sub remove_collection_member {
	my $token = shift;
}

sub collection_order {
	my $token = shift;
	my $members_pos;
	
}

sub create {
	
	my $self = shift;

	my $label = $self->param('label');
	my $v = $self->param('mfv');
	
	my $payload = $self->req->json;
	my $uwmetadata = $payload->{uwmetadata};
	my $rights = $payload->{rights};
	my $members = $payload->{members};

	unless(defined($v)){		
		$self->stash( msg => 'Unknown metadata format version specified');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;
		return;
	}
	unless($v eq '1'){		
		$self->stash( msg => 'Unsupported metadata format version specified');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
		return;
	}		
	unless(defined($uwmetadata)){		
		$self->stash( msg => 'No metadata provided');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
		return;
	}

	my $coll_model = PhaidraAPI::Model::Collection->new;
	
	$self->render_later;
	my $delay = Mojo::IOLoop->delay( 
	
		sub {
			my $delay = shift;
			my $r = $coll_model->create($self, $label, $uwmetadata, $rights, $members, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password}, $delay->begin);		
			$self->render(json => $r, status => $r->{status});					
		},
		
		sub { 	
	  		my ($delay, $r) = @_;	
			$self->app->log->debug($self->app->dumper($r));			
			$self->render(json => $r, status => $r->{status});	
  		}
	
	);
	#$delay->wait unless $delay->ioloop->is_running;
		
	
}





1;
