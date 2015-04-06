package PhaidraAPI::Model::Util;

use strict;
use warnings;
use v5.10;
use XML::LibXML;
use base qw/Mojo::Base/;

sub validate_xml(){

  my $self = shift;
  my $c = shift;
  my $xml = shift;
  my $xsdpath = shift;

  my $res = { alerts => [], status => 200 };

  unless(-f $xsdpath){
    unshift @{$res->{alerts}}, { type => 'danger', msg => "Cannot find XSD files: $xsdpath"};
    $res->{status} = 500;
  };

  my $schema = XML::LibXML::Schema->new(location => $xsdpath);
  my $parser = XML::LibXML->new;

  eval {
    my $document = $parser->parse_string($xml);

    $c->app->log->debug("Validating: ".$document->toString(1));

    $schema->validate($document)
  };

  if($@){
    $c->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
    $res->{status} = 400;
  }else{
    $c->app->log->info("Validation passed.");
  }

  return $res;
}

1;
__END__
