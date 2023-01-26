package PhaidraAPI::Model::Jsonld;

use strict;
use warnings;
use v5.10;
use utf8;
use Mojo::ByteStream qw(b);
use JSON;
use Mojo::Util qw(encode decode);
use base qw/Mojo::Base/;
use XML::LibXML;
use PhaidraAPI::Model::Object;

our $namespaces = {
  phaidra => { label => "Phaidra", IRI =>	"https://phaidra.org/ontology/" },
  bf => { label => "BIBFRAME (v.2)", IRI =>	"http://id.loc.gov/ontologies/bibframe/" },
  ids => { label => "LOC Standard Identifiers Scheme", IRI =>	"http://id.loc.gov/vocabulary/identifiers/" },
  bibo => { label => "The Bibliographic Ontology", IRI =>	"http://purl.org/ontology/bibo/" },
  bib => { label => "Bibliotek-o", IRI =>	"https://bibliotek-o.org/" },
  classSchemes => { label => "Classification Schemes", IRI =>	"http://id.loc.gov/vocabulary/classSchemes" },
  dbo => { label => "DBPedia Ontology", IRI =>	"http://dbpedia.org/ontology/" },
  dce => { label => "Dublin Core Metadata Element Set, Version 1.1", IRI =>	"http://purl.org/dc/elements/1.1/" },
  dcterms => { label => "DCMI Metadata Terms", IRI =>	"http://purl.org/dc/terms/" },
  dcmitype => { label => "DCMI Type Vocabulary", IRI =>	"http://dublincore.org/documents/2000/07/11/dcmi-type-vocabulary/#" },
  ebucore => { label => "EBUCore", IRI =>	"https://www.ebu.ch/metadata/ontologies/ebucore/ebucore#" },
  edm => { label => "Europeana Data Model", IRI =>	"http://www.europeana.eu/schemas/edm/" },
  foaf => { label => "FOAF (Friend of a Friend)", IRI =>	"http://xmlns.com/foaf/spec/#" },
  opaque => { label => "OpaqueNamespace", IRI =>	"http://opaquenamespace.org/ [might change]" },
  pcdm => { label => "Portland Common Data Model", IRI =>	"http://pcdm.org/models#" },
  rdau => { label => "RDA Unconstrained", IRI =>	"http://rdaregistry.info/Elements/u/" },
  rdf => { label => "The RDF Concepts Vocabulary (RDF)", IRI =>	"http://www.w3.org/1999/02/22-rdf-syntax-ns#" },
  rdfs => { label => "RDF Schema 1.1", IRI =>	"https://www.w3.org/TR/rdf-schema/" },
  relators => { label => "MARC Code List for Relators", IRI =>	"http://id.loc.gov/vocabulary/relators" },
  schema => { label => "Schema.org", IRI =>	"http://schema.org/" },
  skos => { label => "SKOS Simple Knowledge Organization System", IRI =>	"http://www.w3.org/2004/02/skos/core#" },
  skosxl => { label => "SKOS Simple Knowledge Organization System eXtension for Labels", IRI =>	"http://www.w3.org/2008/05/skos-xl" },
  identifiers => { label => "Standard Identifiers Scheme", IRI =>	"http://id.loc.gov/vocabulary/identifiers" },
  frap => { label => "The Funding, Research Administration and Projects Ontology", IRI =>	"http://purl.org/cerif/frapo" },
  ebucore => { label => "EBUCore - the Dublin Core for media", IRI =>	"http://www.ebu.ch/metadata/ontologies/ebucore/ebucore" },
  aiiso => { label => "Academic Institution Internal Structure Ontology", IRI =>	"http://purl.org/vocab/aiiso/schema#" },
  cito => { label => "CiTO, the Citation Typing Ontology", IRI =>	"http://purl.org/spar/cito/" },
  arm => { label => "Art and Rare Materials Core Ontology", IRI =>	"https://ld4p.github.io/arm/core/ontology/0.1/" }
};

our %cm2rt = (
  'Picture'       => {'@id' => 'https://pid.phaidra.org/vocabulary/44TN-P1S0', 'skos:prefLabel' => {'eng' => 'image'}},
  'Page'          => {'@id' => 'https://pid.phaidra.org/vocabulary/44TN-P1S0', 'skos:prefLabel' => {'eng' => 'image'}},
  'Book'          => {'@id' => 'https://pid.phaidra.org/vocabulary/47QB-8QF1', 'skos:prefLabel' => {'eng' => 'book'}},
  'PDFDocument'   => {'@id' => 'https://pid.phaidra.org/vocabulary/69ZZ-2KGX', 'skos:prefLabel' => {'eng' => 'text'}},
  'LaTeXDocument' => {'@id' => 'https://pid.phaidra.org/vocabulary/69ZZ-2KGX', 'skos:prefLabel' => {'eng' => 'text'}},
  'Paper'         => {'@id' => 'https://pid.phaidra.org/vocabulary/69ZZ-2KGX', 'skos:prefLabel' => {'eng' => 'text'}},
  'Collection'    => {'@id' => 'https://pid.phaidra.org/vocabulary/GXS7-ENXJ', 'skos:prefLabel' => {'eng' => 'collection'}},
  'Video'         => {'@id' => 'https://pid.phaidra.org/vocabulary/B0Y6-GYT8', 'skos:prefLabel' => {'eng' => 'video'}},
  'Asset'         => {'@id' => 'https://pid.phaidra.org/vocabulary/7AVS-Y482', 'skos:prefLabel' => {'eng' => 'data'}},
  'Audio'         => {'@id' => 'https://pid.phaidra.org/vocabulary/8YB5-1M0J', 'skos:prefLabel' => {'eng' => 'sound'}},
  'Container'     => {'@id' => 'https://pid.phaidra.org/vocabulary/8MY0-BQDQ', 'skos:prefLabel' => {'eng' => 'container'}},
  'Resource'      => {'@id' => 'https://pid.phaidra.org/vocabulary/T8GH-F4V8', 'skos:prefLabel' => {'eng' => 'resource'}}
);

sub get_object_jsonld_parsed {

  my ($self, $c, $pid, $username, $password) = @_;

  my $res = {alerts => [], status => 200};

  my $object_model = PhaidraAPI::Model::Object->new;

  my $r = $object_model->get_datastream($c, $pid, 'JSON-LD', $username, $password, 1);

  if ($r->{status} ne 200) {
    return $r;
  }

  #my $content = encode 'UTF-8', $r->{'JSON-LD'};
  #$c->app->log->debug("XXXXXXXXXXXXXXX :".$c->app->dumper($r->{'JSON-LD'}));
  $res->{'JSON-LD'} = decode_json($r->{'JSON-LD'});
  return $res;
}

sub save_to_object() {

  my $self     = shift;
  my $c        = shift;
  my $pid      = shift;
  my $cmodel   = shift;
  my $metadata = shift;
  my $username = shift;
  my $password = shift;

  my $res = {alerts => [], status => 200};

  $cmodel =~ s/cmodel://g;

  $self->fix($c, $pid, $cmodel, $metadata);

  # validate
  my $valres = $self->validate($c, $pid, $cmodel, $metadata);
  if ($valres->{status} != 200) {
    $res->{status} = $valres->{status};
    foreach my $a (@{$valres->{alerts}}) {
      unshift @{$res->{alerts}}, $a;
    }
    return $res;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $coder        = JSON->new->utf8->pretty;
  my $json         = $coder->encode($metadata);
  return $object_model->add_or_modify_datastream($c, $pid, "JSON-LD", "application/json", undef, $c->app->config->{phaidra}->{defaultlabel}, $json, "M", undef, undef, $username, $password);
}

sub fix() {
  my $self     = shift;
  my $c        = shift;
  my $pid      = shift;
  my $cmodel   = shift;
  my $metadata = shift;

  unless (exists($metadata->{'dcterms:type'})) {
    my $rt = $cm2rt{$cmodel};
    $c->app->log->debug("pid[$pid] cmodel[$cmodel] json-ld fix: adding dcterms:type");
    $metadata->{'dcterms:type'} = [
      { '@type'          => 'skos:Concept',
        'skos:prefLabel' => [
          { '@language' => 'eng',
            '@value'    => $rt->{'skos:prefLabel'}->{'eng'}
          }
        ],
        'skos:exactMatch' => [$rt->{'@id'}]
      }
    ];
  }
}

sub validate() {
  my $self     = shift;
  my $c        = shift;
  my $pid      = shift;
  my $cmodel   = shift;
  my $metadata = shift;

  my $res = {alerts => [], status => 200};

  $c->app->log->debug("pid[$pid] cmodel[$cmodel] validating metadata\n" . $c->app->dumper($metadata));
  unless (($cmodel eq 'Container') || ($cmodel eq 'Collection') || ($cmodel eq 'Resource')) {
    unless (exists($metadata->{'edm:rights'})) {
      $res->{status} = 400;
      push @{$res->{alerts}}, {type => 'danger', msg => "Missing edm:rights"};
      return $res;
    }
  }
  unless (exists($metadata->{'dcterms:type'})) {
    $res->{status} = 400;
    push @{$res->{alerts}}, {type => 'danger', msg => "Missing dcterms:type"};
    return $res;
  }
  for my $type (@{$metadata->{'dcterms:type'}}) {
    unless (exists($type->{'skos:exactMatch'})) {
      $res->{status} = 400;
      push @{$res->{alerts}}, {type => 'danger', msg => "Missing dcterms:type -> skos:exactMatch"};
      return $res;
    }
    for my $typeId (@{$type->{'skos:exactMatch'}}) {
      my $rt = $cm2rt{$cmodel};
      unless ($rt) {
        $res->{status} = 400;
        push @{$res->{alerts}}, {type => 'danger', msg => "Internal error: no resource type defined for cmodel[$cmodel]"};
        return $res;
      }
      if ($typeId ne $rt->{'@id'}) {
        $res->{status} = 400;
        push @{$res->{alerts}}, {type => 'danger', msg => "dcterms:type[$typeId] cmodel[$cmodel] mismatch"};
        return $res;
      }
    }
  }

  return $res;
}

1;
__END__
