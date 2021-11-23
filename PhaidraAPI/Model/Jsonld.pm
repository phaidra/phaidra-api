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

our %cm2rt = (
  'Picture'       => {'@id' => 'https://pid.phaidra.org/vocabulary/44TN-P1S0', 'skos:prefLabel' => {'eng' => 'image'}},
  'PDFDocument'   => {'@id' => 'https://pid.phaidra.org/vocabulary/69ZZ-2KGX', 'skos:prefLabel' => {'eng' => 'text'}},
  'LaTeXDocument' => {'@id' => 'https://pid.phaidra.org/vocabulary/69ZZ-2KGX', 'skos:prefLabel' => {'eng' => 'text'}},
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
      { '@type'           => 'skos:Concept',
        'skos:prefLabel'  => [
          {
            '@language' => 'eng',
            '@value' => $rt->{'skos:prefLabel'}->{'eng'}
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
