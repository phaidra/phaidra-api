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
  my $valres = $self->validate($c, $cmodel, $metadata);
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
  my $cmodel = shift;
  my $metadata = shift;

  my $res = { alerts => [], status => 200 };

  $c->app->log->debug("XXXXXXXXXXXXXX jsonld->validate cmodel [".$cmodel."]");
  $cmodel =~ s/cmodel://g;
  $c->app->log->debug("XXXXXXXXXXXXXX jsonld->validate cmodel cleaned [".$cmodel."]");
  $c->app->log->debug("XXXXXXXXXXXXXX jsonld->validate metadata: ".$c->app->dumper($metadata));
  unless (($cmodel eq 'Container') || ($cmodel eq 'Collection') || ($cmodel eq 'Resource')) {
    unless (exists($metadata->{'edm:rights'})) {
      $res->{status} = 400;
      push @{$res->{alerts}}, { type => 'danger', msg => "Missing edm:rights" };
      return $res;
    }
  }

  return $res;
}

1;
__END__
