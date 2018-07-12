package PhaidraAPI::Controller::Resolve;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';

sub resolve {
  my $self = shift;

	my $res = { alerts => [], status => 200 };

	my $uri = $self->param('uri');
	my $nocache = $self->param('nocache');

	my $cachekey = $uri;
	my $cacheval = $self->app->chi->get($cachekey);

	my $miss = 1;
	if($cacheval){
		$miss = 0;
		$self->app->log->debug("[cache hit] $cachekey");
	}

	if($miss){
		$self->app->log->debug("[cache miss] $cachekey");
		
		my $res = $self->get_preflabel($uri);
		if($res->{status} ne 200){
			$self->render(json => { alerts => $res->{alerts} }, status => $res->{status});
			return;
		}

		$cacheval = $res->{preflabel};

	  $self->app->chi->set($cachekey, $cacheval, '1 day');
	  $cacheval = $self->app->chi->get($cachekey);
	}

  $self->render(json => { term => $cacheval, alerts => $res->{alerts} }, status => $res->{status});
}

sub get_preflabel {

	my $self = shift;
	my $uri = shift;

	my $res = { alerts => [], status => 200 };

	if($uri =~ /vocab.getty.edu/g){
		return $self->resolve_getty($uri);
	}else{
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Unknown resolver' };
		$res->{status} = 500;
		return $res;
	}

}

sub resolve_getty {

	my $self = shift;
	my $uri = shift;

	my $res = { alerts => [], status => 200 };

	my $url = Mojo::URL->new($uri);
	my $get = $self->ua->max_redirects(5)->get($url, => {'Accept' => 'application/ld+json'});
	if (my $getres = $get->success) {
		for my $h (@{$getres->json}) {			
			for my $k (keys %{$h}){
				if($k eq 'http://www.w3.org/2004/02/skos/core#prefLabel'){
					for my $vn (@{$h->{$k}}){
						$res->{preflabel} = $vn->{'@value'};
						return $res;
					}
				}
			}
		}
	}else{
		my ($err, $code) = $get->error;
		$self->app->log->error("[$uri] error resolving uri ".$self->app->dumper($err));
		unshift @{$res->{alerts}}, { type => 'danger', msg => $self->app->dumper($err) };
		$res->{status} =  $code ? $code : 500;
		return $res;
	}

	return $res;
}

1;
