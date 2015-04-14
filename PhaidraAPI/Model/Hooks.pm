package PhaidraAPI::Model::Hooks;

use strict;
use warnings;
use v5.10;
use utf8;
use Switch;
use base qw/Mojo::Base/;
use Mojo::Util qw/xml_escape/;
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Util;

my %cmodelMapping=
(
  'cmodel:Picture'       => 'Image',
  'cmodel:Audio'         => 'Sound',
  'cmodel:Collection'    => 'Collection',
  'cmodel:Container'     => 'Dataset',
  'cmodel:Video'         => 'MovingImage',
  'cmodel:PDFDocument'   => 'Text',
  'cmodel:LaTeXDocument' => 'Text',
  'cmodel:Resource'      => 'InteractiveResource',
  'cmodel:Asset'         => 'Unknown',
  'cmodel:Book'          => 'Book',
  'cmodel:Page'          => 'Page',
  'cmodel:Paper'         => 'Text',
);

sub add_or_modify_datastream_hooks {

  my $self = shift;
  my $c = shift;
  my $pid = shift;
  my $dsid = shift;
  my $dscontent = shift;
  my $username = shift;
  my $password = shift;

  switch ($dsid) {

    case "UWMETADATA"	{
      $self->generate_dc_from_uwmetadata($c, $pid, $dscontent);
    }
  }
}

sub generate_dc_from_uwmetadata {

  my $self = shift;
  my $c = shift;
  my $pid = shift;
  my $dscontent = shift;

  my $res = { alerts => [], status => 200 };

  my ($dc_p, $dc_oai) = $self->map_uwmetadata_2_dc($c, $pid, $dscontent);

  # FIXME:
  # HACK: using admin account
  my $object_model = PhaidraAPI::Model::Object->new;

  # Phaidra DC
  my $r1 = $object_model->add_or_modify_datastream($c, $pid, "DC_P", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_p, "X", $username, $password, 1);
  foreach my $a (@{$r1->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r1->{status} ne 200)
    $res->status = $r1->{status};
  }

  # OAI DC - unqualified
  my $r2 = $object_model->add_or_modify_datastream($c, $pid, "DC_OAI", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_oai, "X", $username, $password, 1);
  foreach my $a (@{$r2->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r2->{status} ne 200)
    $res->status = $r2->{status};
  }

  return $res;
}

sub map_uwmetadata_2_dc {

  my $self = shift;
  my $c = shift;
  my $pid = shift;
  my $dscontent = shift;

  my %dc_p;
  my %dc_oai;

  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($xml);


  my $dc_p_xml = '<oai_dc:dc xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/">'."\n";
  foreach my $k (keys %dc_p)
  {
    foreach my $n (@{$dc_p{$k}}){

      next unless (defined ($n->{value}));

      $dc_p_xml .= '   <dc:' . $k;
      $dc_p_xml .= ' xml:lang="' . PhaidraAPI::Model::Util::iso639map{$n->{lang}} . '"' if (exists($n->{lang}));
      $dc_p_xml .= '>' . xml_escape($n->{value}) . '</dc:' . $k . ">\n";
    }
  }
  $dc_p_xml .= "</oai_dc:dc>\n";
  $c->app->log->debug("Generated dc_p: $dc_p_xml");


  return ($dc_p_xml, $dc_oai_xml);
}

1;
__END__
