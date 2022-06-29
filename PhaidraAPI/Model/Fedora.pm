package PhaidraAPI::Model::Fedora;

use strict;
use warnings;
use v5.10;
use utf8;
use base qw/Mojo::Base/;

sub getJsonldValue {
  my ($self, $c, $jsonld, $p) = @_;

  for my $ob (@{$jsonld}) {
    if (exists($ob->{$p})) {
      for my $ob1 (@{$ob->{$p}}) {
        if (exists($ob1->{'@value'})) {
          return $ob1->{'@value'};
        }
      }
    }
  }
}

sub getObjectProperties {
  my ($self, $c, $pid) = @_;

  my $res = {alerts => [], status => 200};

  my $url = Mojo::URL->new;
  $url->scheme('https');
  $url->host($c->app->config->{fedora}->{baseurl});
  $url->path("/rest/$pid");
  my $getres = $c->ua->get($url => {'Accept' => 'application/ld+json'})->result;

  if ($getres->is_success) {
    my $props = $getres->json;

    # cmodel
    my $cmodel = $self->getJsonldValue($c, $props, 'info:fedora/fedora-system:def/model#hasModel');
    $cmodel =~ m/(info:fedora\/)(\w+):(\w+)/g;
    if ($2 eq 'cmodel' && defined($3) && ($3 ne '')) {
      $res->{cmodel} = $3;
    }

    $res->{state}                  = $self->getJsonldValue($c, $props, 'info:fedora/fedora-system:def/model#state');
    $res->{label}                  = $self->getJsonldValue($c, $props, 'info:fedora/fedora-system:def/model#label');
    $res->{created}                = $self->getJsonldValue($c, $props, 'http://fedora.info/definitions/v4/repository#created');
    $res->{modified}               = $self->getJsonldValue($c, $props, 'http://fedora.info/definitions/v4/repository#lastModified');
    $res->{owner}                  = $self->getJsonldValue($c, $props, 'http://fedora.info/definitions/v4/repository#createdBy');
    $res->{identifier}             = $self->getJsonldValue($c, $props, 'http://purl.org/dc/terms/identifier');
    $res->{references}             = $self->getJsonldValue($c, $props, 'http://purl.org/dc/terms/references');
    $res->{isbacksideof}           = $self->getJsonldValue($c, $props, 'http://phaidra.org/XML/V1.0/relations#isBackSideOf');
    $res->{isthumbnailfor}         = $self->getJsonldValue($c, $props, 'http://phaidra.org/XML/V1.0/relations#isThumbnailFor');
    $res->{hassuccessor}           = $self->getJsonldValue($c, $props, 'http://phaidra.univie.ac.at/XML/V1.0/relations#hasSuccessor');
    $res->{isalternativeformatof}  = $self->getJsonldValue($c, $props, 'http://phaidra.org/XML/V1.0/relations#isAlternativeFormatOf');
    $res->{isalternativeversionof} = $self->getJsonldValue($c, $props, 'http://phaidra.org/XML/V1.0/relations#isAlternativeVersionOf');
    $res->{isinadminset}           = $self->getJsonldValue($c, $props, 'http://phaidra.org/ontology/isInAdminSet');
    $res->{haspart}                = $self->getJsonldValue($c, $props, 'info:fedora/fedora-system:def/relations-external#hasCollectionMember');
    $res->{hasmember}              = $self->getJsonldValue($c, $props, 'http://pcdm.org/models#hasMember');
    $res->{hastrack}               = $self->getJsonldValue($c, $props, 'http://www.ebu.ch/metadata/ontologies/ebucore/ebucore#hasTrack');
    $res->{sameas}                 = $self->getJsonldValue($c, $props, 'http://www.w3.org/2002/07/owl#sameAs');

    $res->{contains} = [];
    for my $ob (@{$props}) {
      if (exists($ob->{'http://www.w3.org/ns/ldp#contains'})) {
        for my $ob1 (@{$ob->{'http://www.w3.org/ns/ldp#contains'}}) {
          if (exists($ob1->{'@id'})) {
            $ob1->{'@id'} =~ m/.+\/(\w+)$/g;
            push @{$res->{contains}}, $1;
          }
        }
      }
    }
  }
  else {
    unshift @{$res->{alerts}}, {type => 'danger', msg => $getres->message};
    $res->{status} = $getres->{code};
    return $res;
  }

  return $res;
}

1;
__END__
