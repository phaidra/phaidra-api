package PhaidraAPI::Controller::Object;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Object;

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


sub related {
	
	my $self = shift;
	my $from = 1;
	my $limit = 10;
	my @fields;
	
	unless(defined($self->stash('pid'))){		 	
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;		
		return;
	}	
	
	unless(defined($self->stash('relation'))){		 	
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined relation' }]} , status => 400) ;		
		return;
	}	
		
	my $pid = $self->stash('pid');
	my $relation = $self->stash('relation');
	
	if(defined($self->param('from'))){	
		$from = $self->param('from');
	}
	
	if(defined($self->param('limit'))){	
		$limit = $self->param('limit');
	}
	
	if(defined($self->param('fields'))){
		@fields = $self->param('fields');
	}
	
	if(!defined($fields) || (scalar @$fields < 1)) {
		$fields = [ 'PID' ];	
	}
	
	$self->render_later;
	my $delay = Mojo::IOLoop->delay( 
	
		sub {
			my $delay = shift;			
			$object_model->related($self, $pid, $from, $limit, \@fields, $delay->begin);			
		},
		
		sub { 	
	  		my ($delay, $r) = @_;	
			#$self->app->log->debug($self->app->dumper($r));			
			$self->render(json => $r, status => $r->{status});	
  		}
	
	);
	$delay->wait unless $delay->ioloop->is_running;	
	
}


1;
