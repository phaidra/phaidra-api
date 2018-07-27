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

	if($miss || $nocache){
		$self->app->log->debug("[cache miss] $cachekey");
		
		my $res = $self->_resolve($uri);
		if($res->{status} ne 200){
			$self->render(json => { alerts => $res->{alerts} }, status => $res->{status});
			return;
		}

		$cacheval = $res;

	  $self->app->chi->set($cachekey, $cacheval, '1 day');
	  $cacheval = $self->app->chi->get($cachekey);
	}

  $self->render(json => { $uri => $cacheval, alerts => $res->{alerts} }, status => $res->{status});
}

sub _resolve {

	my $self = shift;
	my $uri = shift;

	my $res = { alerts => [], status => 200 };

	if($uri =~ /vocab.getty.edu/g){
		return $self->_resolve_getty($uri);
	}else{
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Unknown resolver' };
		$res->{status} = 500;
		return $res;
	}

}

sub _resolve_getty {

	my $self = shift;
	my $uri = shift;

	my $res = { alerts => [], status => 200 };

	my $url = Mojo::URL->new($uri);
	my $get = $self->ua->max_redirects(5)->get($url, => {'Accept' => 'application/ld+json'});
	if (my $getres = $get->success) {
		for my $h (@{$getres->json}) {
      if($h->{'@id'} eq $uri){
        for my $k (keys %{$h}){
          if($k eq 'http://www.w3.org/2004/02/skos/core#prefLabel'){
            for my $vn (@{$h->{$k}}){
              push @{$res->{'skos:prefLabel'}}, $vn;
              # second cycle to find the parentString
              for my $k1 (keys %{$h}){
                if($k1 eq 'http://vocab.getty.edu/ontology#parentString'){
                  for my $vn1 (@{$h->{$k1}}){
                    my $path = $vn1->{'@value'};
                    $path =~ s/\s//g;
                    $path =~ s/,/--/g;
                    push @{$res->{'rdfs:label'}}, { '@value' => $vn->{'@value'}."--".$path };
                  }
                }
              }
            }
          }
        }
      }
      if($h->{'@id'} eq $uri.'-geometry'){
        my $spatial;
        for my $k (keys %{$h}){
          if($k eq 'http://schema.org/latitude'){
            for my $vn (@{$h->{$k}}){
              $spatial->{'schema:latitude'} = $vn->{'@value'};
            }
          }
          if($k eq 'http://schema.org/longitude'){
            for my $vn (@{$h->{$k}}){
              $spatial->{'schema:longitude'} = $vn->{'@value'};
            }
          }
        }
        $res->{'schema:GeoCoordinates'} = $spatial;
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
