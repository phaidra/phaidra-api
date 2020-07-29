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

our %resourcetypes = (
  "https://pid.phaidra.org/vocabulary/44TN-P1S0" => [ 'Picture' ],
  "https://pid.phaidra.org/vocabulary/69ZZ-2KGX" => [ 'PDFDocument', 'LaTeXDocument' ],
  "https://pid.phaidra.org/vocabulary/GXS7-ENXJ" => [ 'Collection' ],
  "https://pid.phaidra.org/vocabulary/B0Y6-GYT8" => [ 'Video' ],
  "https://pid.phaidra.org/vocabulary/7AVS-Y482" => [ 'Asset' ],
  "https://pid.phaidra.org/vocabulary/8YB5-1M0J" => [ 'Audio' ],
  "https://pid.phaidra.org/vocabulary/8MY0-BQDQ" => [ 'Container' ],
  "https://pid.phaidra.org/vocabulary/T8GH-F4V8" => [ 'Resource' ]
);

sub get_object_jsonld_parsed {

  my ($self, $c, $pid, $username, $password) = @_;

  my $res = { alerts => [], status => 200 };

  my $object_model = PhaidraAPI::Model::Object->new;
  
  my $r =  $object_model->get_datastream($c, $pid, 'JSON-LD', $username, $password, 1);

  if($r->{status} ne 200){
    return $r;
  }
  #my $content = encode 'UTF-8', $r->{'JSON-LD'};
#$c->app->log->debug("XXXXXXXXXXXXXXX :".$c->app->dumper($r->{'JSON-LD'}));
  $res->{'JSON-LD'} = decode_json($r->{'JSON-LD'});
  return $res;  
}

sub save_to_object(){

  my $self = shift;
  my $c = shift;
  my $pid = shift;
  my $cmodel = shift;
  my $metadata = shift;
  my $username = shift;
  my $password = shift;

  my $res = { alerts => [], status => 200 };

  # validate
  my $valres = $self->validate($c, $pid, $cmodel, $metadata);
  if($valres->{status} != 200){
    $res->{status} = $valres->{status};
    foreach my $a ( @{$valres->{alerts}} ){
      unshift @{$res->{alerts}}, $a;
    }
    return $res;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $coder = JSON->new->utf8->pretty;
  my $json = $coder->encode($metadata);
  return $object_model->add_or_modify_datastream($c, $pid, "JSON-LD", "application/json", undef, $c->app->config->{phaidra}->{defaultlabel}, $json, "M", undef, undef, $username, $password);
}

sub validate() {
  my $self = shift;
  my $c = shift;
  my $pid = shift;
  my $cmodel = shift;
  my $metadata = shift;

  my $res = { alerts => [], status => 200 };

  $cmodel =~ s/cmodel://g;
  $c->app->log->debug("pid[$pid] cmodel[$cmodel] validating metadata:\n".$c->app->dumper($metadata));
  unless (($cmodel eq 'Container') || ($cmodel eq 'Collection') || ($cmodel eq 'Resource')) {
    unless (exists($metadata->{'edm:rights'})) {
      $res->{status} = 400;
      push @{$res->{alerts}}, { type => 'danger', msg => "Missing edm:rights" };
      return $res;
    }
  }
  unless (exists($metadata->{'dcterms:type'})) {
    $res->{status} = 400;
    push @{$res->{alerts}}, { type => 'danger', msg => "Missing dcterms:type" };
    return $res;
  }
  for my $type (@{$metadata->{'dcterms:type'}}) {
    unless (exists($type->{'skos:exactMatch'})) {
      $res->{status} = 400;
      push @{$res->{alerts}}, { type => 'danger', msg => "Missing dcterms:type -> skos:exactMatch" };
      return $res;
    }
    for my $typeId (@{$type->{'skos:exactMatch'}}) {
      unless (exists($resourcetypes{$typeId})) {
        $res->{status} = 400;
        push @{$res->{alerts}}, { type => 'danger', msg => "Unknown dcterms:type[$typeId]" };
        return $res;
      }
      my $cmMatch = 0;
      for my $cm (@{$resourcetypes{$typeId}}) {
        if ($cm eq $cmodel) {
          $cmMatch = 1;
        }
      }
      unless ($cmMatch) {
        $res->{status} = 400;
        push @{$res->{alerts}}, { type => 'danger', msg => "dcterms:type[$typeId] cmodel[$cmodel] mismatch" };
        return $res;
      }
    }
  }

  return $res;
}

1;
__END__
