package PhaidraAPI::Controller::Resolve;

use strict;
use warnings;
use v5.10;
use Switch;
use base 'Mojolicious::Controller';

sub resolve {
  my $self = shift;

  my $res = {alerts => [], status => 200};

  my $uri     = $self->param('uri');
  my $nocache = $self->param('nocache');

  my $cachekey = $uri;
  my $cacheval = $self->app->chi->get($cachekey);

  my $miss = 1;
  if ($cacheval) {
    $miss = 0;
    $self->app->log->debug("[cache hit] $cachekey");
  }

  if ($miss || $nocache) {
    $self->app->log->debug("[cache miss] $cachekey");

    my $res = $self->_resolve($uri);
    if ($res->{status} ne 200) {
      $self->render(json => {alerts => $res->{alerts}}, status => $res->{status});
      return;
    }

    $cacheval = $res;

    $self->app->chi->set($cachekey, $cacheval, '1 day');
    $cacheval = $self->app->chi->get($cachekey);
  }

  $self->render(json => {$uri => $cacheval, alerts => $res->{alerts}}, status => $res->{status});
}

sub _resolve {

  my $self = shift;
  my $uri  = shift;

  my $res = {alerts => [], status => 200};

  if ($uri =~ /vocab.getty.edu/g) {
    return $self->_resolve_getty($uri);
  }
  elsif ($uri =~ /d-nb.info\/gnd/g) {
    return $self->_resolve_gnd($uri);
  }
  elsif ($uri =~ /www.geonames.org/g) {
    return $self->_resolve_geonames($uri);
  }
  else {
    unshift @{$res->{alerts}}, {type => 'danger', msg => 'Unknown resolver'};
    $res->{status} = 500;
    return $res;
  }

}

sub _resolve_gnd {

  my $self = shift;
  my $uri  = shift;

  my $res = {alerts => [], status => 200};

  my $url = Mojo::URL->new($uri);
  my $get = $self->ua->max_redirects(5)->get($url, => {'Accept' => 'application/ld+json'});
  if (my $getres = $get->success) {
    for my $h (@{$getres->json}) {
      if ($h->{'@id'} eq $uri) {
        for my $k (keys %{$h}) {
          if ($k eq 'http://d-nb.info/standards/elementset/gnd#preferredNameForTheSubjectHeading') {
            for my $vn (@{$h->{$k}}) {
              push @{$res->{'skos:prefLabel'}}, $vn;
            }
          }
          if ($k eq 'http://d-nb.info/standards/elementset/gnd#variantNameForTheSubjectHeading') {
            for my $vn (@{$h->{$k}}) {
              push @{$res->{'rdfs:label'}}, $vn;
            }
          }
        }
      }
    }
  }
  else {
    my ($err, $code) = $get->error;
    $self->app->log->error("[$uri] error resolving uri " . $self->app->dumper($err));
    unshift @{$res->{alerts}}, {type => 'danger', msg => $self->app->dumper($err)};
    $res->{status} = $code ? $code : 500;
    return $res;
  }

  return $res;
}

sub _resolve_getty {

  my $self = shift;
  my $uri  = shift;

  my $res = {alerts => [], status => 200};

  my $url = Mojo::URL->new($uri);
  my $get = $self->ua->max_redirects(5)->get($url, => {'Accept' => 'application/ld+json'});
  if (my $getres = $get->success) {
    for my $h (@{$getres->json}) {
      if ($h->{'@id'} eq $uri) {
        for my $k (keys %{$h}) {
          if ($k eq 'http://www.w3.org/2004/02/skos/core#prefLabel') {
            for my $vn (@{$h->{$k}}) {
              push @{$res->{'skos:prefLabel'}}, $vn;

              # second cycle to find the parentString
              for my $k1 (keys %{$h}) {
                if ($k1 eq 'http://vocab.getty.edu/ontology#parentString') {
                  for my $vn1 (@{$h->{$k1}}) {
                    my $path = $vn1->{'@value'};
                    $path =~ s/\s//g;
                    $path =~ s/,/--/g;
                    push @{$res->{'rdfs:label'}}, {'@value' => $vn->{'@value'} . "--" . $path};
                  }
                }
              }
            }
          }
        }
      }
      if ($h->{'@id'} eq $uri . '-geometry') {
        my $spatial;
        for my $k (keys %{$h}) {
          if ($k eq 'http://schema.org/latitude') {
            for my $vn (@{$h->{$k}}) {
              $spatial->{'schema:latitude'} = $vn->{'@value'};
            }
          }
          if ($k eq 'http://schema.org/longitude') {
            for my $vn (@{$h->{$k}}) {
              $spatial->{'schema:longitude'} = $vn->{'@value'};
            }
          }
        }
        $res->{'schema:GeoCoordinates'} = $spatial;
      }
    }
  }
  else {
    my ($err, $code) = $get->error;
    $self->app->log->error("[$uri] error resolving uri " . $self->app->dumper($err));
    unshift @{$res->{alerts}}, {type => 'danger', msg => $self->app->dumper($err)};
    $res->{status} = $code ? $code : 500;
    return $res;
  }

  return $res;
}

sub _resolve_geonames {

  my $self = shift;
  my $uri  = shift;

  my $res = {alerts => [], status => 200};

  unless ($self->config->{apis}) {
    my $err = "resolve apis are not configured";
    $self->app->log->error($err);
    return {alerts => [{type => 'danger', msg => $err}], status => 500};
  }

  unless ($self->config->{apis}->{geonames}) {
    my $err = "geonames api is not configured";
    $self->app->log->error($err);
    return {alerts => [{type => 'danger', msg => $err}], status => 500};
  }

  my $id = $uri =~ s/http:\/\/www\.geonames\.org\///r;

  my $url = Mojo::URL->new($self->config->{apis}->{geonames}->{url} . "?username=" . $self->config->{apis}->{geonames}->{username} . "&geonameId=" . $id);
  my $get = $self->ua->max_redirects(5)->get($url);
  if (my $getres = $get->success) {
    my $json = $getres->json;
    push @{$res->{'skos:prefLabel'}}, {'@value' => $json->{name}};
    my $path = "";
    if ($json->{adminName5}) {
      $path .= "--" . $json->{adminName5} unless $json->{adminName5} eq $json->{toponymName};
    }
    if ($json->{adminName4}) {
      $path .= "--" . $json->{adminName4} unless $json->{adminName4} eq $json->{toponymName};
    }
    if ($json->{adminName3}) {
      $path .= "--" . $json->{adminName3} unless $json->{adminName3} eq $json->{toponymName};
    }
    if ($json->{adminName2}) {
      $path .= "--" . $json->{adminName2} unless $json->{adminName2} eq $json->{toponymName};
    }
    if ($json->{adminName1}) {
      $path .= "--" . $json->{adminName1} unless $json->{adminName1} eq $json->{toponymName};
    }
    if ($json->{countryName}) {
      $path .= "--" . $json->{countryName} unless $json->{countryName} eq $json->{toponymName};
    }
    if ($json->{continentCode}) {
      my $continentName = "";
      switch ($json->{continentCode}) {
        case "AF" {
          $continentName = "Africa";
        }
        case "AS" {
          $continentName = "Asia";
        }
        case "EU" {
          $continentName = "Europe";
        }
        case "NA" {
          $continentName = "North america";
        }
        case "OC" {
          $continentName = "Oceania";
        }
        case "SA" {
          $continentName = "South america";
        }
        case "AN" {
          $continentName = "Antarctica";
        }
      }
      $path .= "--" . $continentName;
    }
    push @{$res->{'rdfs:label'}}, {'@value' => $json->{toponymName} . $path};

    my $spatial;
    $spatial->{'schema:latitude'}   = $json->{'lat'} if $json->{'lat'};
    $spatial->{'schema:longitude'}  = $json->{'lng'} if $json->{'lng'};
    $res->{'schema:GeoCoordinates'} = $spatial;

  }
  else {
    my ($err, $code) = $get->error;
    $self->app->log->error("[$uri] error resolving uri " . $self->app->dumper($err));
    unshift @{$res->{alerts}}, {type => 'danger', msg => $self->app->dumper($err)};
    $res->{status} = $code ? $code : 500;
    return $res;
  }

  return $res;
}

1;
