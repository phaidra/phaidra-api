package PhaidraAPI::Controller::Search;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Search::GSearchSAXHandler;
use Mojo::IOLoop::Delay;

sub triples {
	my $self = shift;
	
	my $query = $self->param('query');
	my $limit = $self->param('limit');
	
	my $search_model = PhaidraAPI::Model::Search->new;
	my $sr = $search_model->triples($self, $query, $limit);
	
	$self->render(json => $sr, status => $sr->{status});
}

sub owner {
	my $self = shift;	
	my $from = 1;
	my $limit = 10;
	
	unless(defined($self->stash('username'))){		
		$self->stash( msg => 'Undefined username');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 400) ;		
		return;
	}
	
	if(defined($self->stash('from'))){	
		$from = $self->stash('from');
	}
	
	unless(defined($self->stash('limit'))){	
		$limit = $self->stash('limit');
	}		
	
	my $search_model = PhaidraAPI::Model::Search->new;			
	
	my $query = "fgs.ownerId:".$self->stash('username').' AND NOT fgs.contentModel:"cmodel:Page"';
	
	$self->render_later;
	my $delay = Mojo::IOLoop->delay( 
	
		sub {
			my $delay = shift;
			$search_model->search($self, $query, $from, $limit, $delay->begin);			
		},
		
		sub { 	
	  		my ($delay, $r) = @_;	
			#$self->app->log->debug($self->app->dumper($r));			
			$self->render(json => $r, status => $r->{status});	
  		}
	
	);
	$delay->wait unless $delay->ioloop->is_running;	
		
}

sub collections_owner {
	my $self = shift;	
	my $from = 1;
	my $limit = 10;
	
	unless(defined($self->stash('username'))){		
		$self->stash( msg => 'Undefined username');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 400) ;		
		return;
	}
	
	if(defined($self->stash('from'))){	
		$from = $self->stash('from');
	}
	
	unless(defined($self->stash('limit'))){	
		$limit = $self->stash('limit');
	}		
	
	my $search_model = PhaidraAPI::Model::Search->new;			
	
	my $query = "fgs.ownerId:".$self->stash('username').' AND fgs.contentModel:"cmodel:Collection" AND NOT fgs.contentModel:"cmodel:Page"';
	
	$self->render_later;
	my $delay = Mojo::IOLoop->delay( 
	
		sub {
			my $delay = shift;
			$search_model->search($self, $query, $from, $limit, $delay->begin);			
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
