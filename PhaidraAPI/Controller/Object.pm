package PhaidraAPI::Controller::Object;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Object;

sub delete {
    my $self = shift;

	unless(defined($self->stash('pid'))){		
		$self->stash( msg => 'Undefined pid.');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
		return;
	}	

	my $object_model = PhaidraAPI::Model::Object->new;		
    my $r = $object_model->delete($self, $self->stash('pid'), $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
   	
   	$self->render(json => $r, status => $r->{status}) ;
}

sub modify {
    my $self = shift;

	unless(defined($self->stash('pid'))){		
		$self->stash( msg => 'Undefined pid.');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
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

1;
