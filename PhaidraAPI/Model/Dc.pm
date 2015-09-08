package PhaidraAPI::Model::Dc;

use strict;
use warnings;
use v5.10;
use utf8;
use Mojo::ByteStream qw(b);
use Mojo::Util qw(xml_escape encode decode);
use base qw/Mojo::Base/;
use XML::LibXML;
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Util;
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Licenses;

our %cmodelMapping =
(
  'Picture'       => 'Image',
  'Audio'         => 'Sound',
  'Collection'    => 'Collection',
  'Container'     => 'Dataset',
  'Video'         => 'MovingImage',
  'PDFDocument'   => 'Text',
  'LaTeXDocument' => 'Text',
  'Resource'      => 'InteractiveResource',
  'Asset'         => 'Unknown',
  'Book'          => 'Book',
  'Page'          => 'Page',
  'Paper'         => 'Text',
);

our %uwns =
(
  'http://phaidra.univie.ac.at/XML/metadata/V1.0' => 'metadata',
  'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0' => 'lom',
  'http://phaidra.univie.ac.at/XML/metadata/extended/V1.0' => 'extended',
  'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/entity' => 'entity',
  'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/requirement' => 'requirement',
  'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational' => 'educational',
  'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/annotation' => 'annotation',
  'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/classification' => 'classification',
  'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/organization' => 'organization',
  'http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0' => 'histkult',
  'http://phaidra.univie.ac.at/XML/metadata/provenience/V1.0' => 'provenience',
  'http://phaidra.univie.ac.at/XML/metadata/provenience/V1.0/entity' => 'provenience_entity',
  'http://phaidra.univie.ac.at/XML/metadata/digitalbook/V1.0' => 'digitalbook',
  'http://phaidra.univie.ac.at/XML/metadata/etheses/V1.0' => 'etheses'
);

our %uwns_rev = reverse %uwns;

our %uw_vocs = (
  'hoschtyp' => '17',
  'infoeurepoversion' => '38',
  'resource' => '31',
  'infoeurepoaccess' => '36'
);

our %non_contributor_role_ids =
(
  'author_analog' => '1552095',
  'author_digital' => '46',
  'editor' => '52',
  'publisher' => '47',
  'uploader' => '1557146',
);

our %non_contributor_role_ids_rev = reverse %non_contributor_role_ids;

our %mods_contributor_roles =
(
  'ctb' => 1
);

our %mods_creator_roles =
(
  'aut' => 1,
  'prt' => 1,
  'edt' => 1,
  'ill' => 1,
  'dte' => 1,
  'drm' => 1,
  'ctg' => 1,
  'ltg' => 1,
  'egr' => 1
);

my %doc_uwns = ();


sub xml_2_json {
    my ($self, $c, $xml, $output_label) = @_;

    my @nodes;
    my $res = { alerts => [], status => 200, $output_label => \@nodes };
    
    my $dom = Mojo::DOM->new();
    $dom->xml(1);
    $dom->parse($xml);
    my %json;
    $self->xml_2_json_rec($c, \%json, $dom->children);

    my $mods;
    foreach my $ch (@{$json{children}}){
      if($ch->{xmlname} eq 'dc'){
        $res->{$output_label} = $ch->{children};
      }
    }

    return $res;
}

sub xml_2_json_rec {

    my ($self, $c, $parent, $xml_children) = @_;

    for my $e ($xml_children->each) {

        my $type = $e->tag;

        $type =~ m/(\w+):(\w+)/;
        my $ns = $1;
        my $id = $2;
        my $node;
        #$c->app->log->debug("XXXXX type [$type] ns [$ns] id [$id]");
        $node->{xmlname} = $id;
        if(defined($e->text) && $e->text ne ''){
          $node->{ui_value} = b($e->text)->decode('UTF-8');
        }

        if(defined($e->attr)){
          foreach my $ak (keys %{$e->attr}){
              my $a = {
                xmlname => $ak,
                ui_value => b($e->attr->{$ak})->decode('UTF-8')
              };
              push @{$node->{attributes}}, $a;
          }
        }

        if($e->children->size > 0){
          $self->xml_2_json_rec($c, $node, $e->children);
        }

        push @{$parent->{children}}, $node;
    }

}

sub get_object_dc_json {

  my ($self, $c, $pid, $dsid, $username, $password) = @_;

  my $object_model = PhaidraAPI::Model::Object->new;
  my $res = $object_model->get_datastream($c, $pid, $dsid, $username, $password, 1);
  if($res->{status} ne 200){
    return $res;
  }

  my $output_label = $dsid eq 'DC_P' ? 'dc' : 'oai_dc';
  return $self->xml_2_json($c, $res->{$dsid}, $output_label);

}


sub generate_dc_from_mods {

  my ($self, $c, $pid, $dscontent, $username, $password) = @_;

  my $res = { alerts => [], status => 200 };

  my $object_model = PhaidraAPI::Model::Object->new;
  my $cmodel = $object_model->get_cmodel($c, $pid);

  my $mods_model = PhaidraAPI::Model::Uwmetadata->new;

  my ($dc_p, $dc_oai) = $self->map_mods_2_dc($c, $pid, $cmodel, $dscontent, $mods_model);

  # Phaidra DC
  my $r1 = $object_model->add_or_modify_datastream($c, $pid, "DC_P", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_p, "X", $username, $password);
  foreach my $a (@{$r1->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r1->{status} ne 200){
    $res->status = $r1->{status};
  }

  # OAI DC - unqualified
  my $r2 = $object_model->add_or_modify_datastream($c, $pid, "DC_OAI", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_oai, "X", $username, $password);
  foreach my $a (@{$r2->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r2->{status} ne 200){
    $res->status = $r2->{status};
  }

  return $res;
}


sub map_mods_2_dc {

  my ($self, $c, $pid, $cmodel, $xml, $tree, $metadata_model) = @_;

  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($xml);

  #$c->app->log->debug("XXXXXXXXXXX mods xml:".$xml);

  # keep using 'mods' as the first node in selectors to avoid running into relatedItem
  my %dc_p;
  $dc_p{title} = $self->_get_mods_titles($c, $dom);
  $dc_p{subject} = $self->_get_mods_element_values($c, $dom, 'mods > subject > topic');
  my $classifications = $self->_get_mods_classifications($c, $dom);
  push @{$dc_p{subject}}, @$classifications;
  $dc_p{identifier} = $self->_get_mods_element_values($c, $dom, 'mods > identifier');
  $dc_p{relation} = $self->_get_mods_relations($c, $dom);
  my $editions = $self->_get_mods_element_values($c, $dom, 'mods > originInfo > edition');
  push @{$dc_p{relation}}, @$editions;
  $dc_p{language} = $self->_get_mods_element_values($c, $dom, 'mods >language > languageTerm');
  $dc_p{creator} = $self->_get_mods_creators($c, $dom, 'p');
  $dc_p{contributor} = $self->_get_mods_contributors($c, $dom, 'p');
  $dc_p{date} = $self->_get_mods_element_values($c, $dom, 'mods > originInfo > dateIssued[keyDate="yes"]');
  $dc_p{description} = $self->_get_mods_element_values($c, $dom, 'mods > note');
  # maps specific
  my $scales = $self->_get_mods_element_values($c, $dom, 'mods > subject > cartographics > scale');
  my @scales_en = map { { value => "Scale 1:".$_->{value}, lang => 'en' } } @$scales;
  push @{$dc_p{description}}, @scales_en;
  my @scales_de = map { { value => "Maßstab 1:".$_->{value}, lang => 'de' } } @$scales;
  push @{$dc_p{description}}, @scales_de;

  my $extents = $self->_get_mods_element_values($c, $dom, 'mods > physicalDescription > extent');
  push @{$dc_p{description}}, @$extents;

  $dc_p{publisher} = $self->_get_mods_element_values($c, $dom, 'mods > originInfo > publisher');
  my $publisher_places = $self->_get_mods_element_values($c, $dom, 'mods > originInfo > place > placeTerm');
  push @{$dc_p{publisher}}, @$publisher_places;

  $dc_p{rights} = $self->_get_mods_element_values($c, $dom, 'mods > accessCondition[type="use and reproduction"]');


  # FIXME GEO datastream to DCMI BOX

  #$c->app->log->debug("XXXXXXXXXXX dc_p hash:".$c->app->dumper(\%dc_p));
  my $dc_p_xml = $self->_create_dc_from_hash($c, \%dc_p);
  #$c->app->log->debug("XXXXXXXXXXX dc_p xml:".$dc_p_xml);

  # see https://guidelines.openaire.eu/wiki/OpenAIRE_Guidelines:_For_Literature_repositories
  my %dc_oai = %dc_p;
  $dc_oai{creator} = $self->_get_mods_creators($c, $dom, 'oai');
  $dc_oai{contributor} = $self->_get_mods_contributors($c, $dom, 'oai');

  #$c->app->log->debug("XXXXXXXXXXX dc_oai hash:".$c->app->dumper(\%dc_oai));
  my $dc_oai_xml = $self->_create_dc_from_hash($c, \%dc_oai);
  #$c->app->log->debug("XXXXXXXXXXX dc_oai xml:".$dc_oai_xml);

  return ($dc_p_xml, $dc_oai_xml);
}

sub _get_mods_classifications {

  my ($self, $c, $dom, ) = @_;

  my @cls;
  for my $e ($dom->find('mods > classification')->each){
    my $uri = $e->text;
    my $label;
    push @cls, { value => $label };
  }

  return \@cls;
}

sub _get_mods_creators {
  my ($self, $c, $dom, $mode) = @_;

  my @creators;

  for my $name ($dom->find('mods name[type="personal"]')->each){
    my $role = $name->find('role roleTerm[type="code"][authority="marcrelator"]')->first;
    if(defined($role)){
      $role = $role->text;
      if($mods_creator_roles{$role}){
        my $firstname = $name->find('namePart[type="given"]')->map('text')->join(" ");
        my $lastname = $name->find('namePart[type="family"]')->map('text')->join(" ");

        if(defined($firstname) && $firstname ne '' && defined($lastname) && $lastname ne ''){
          if($mode eq 'oai'){
            # APA bibliographic style
            my $initials = ucfirst(substr($firstname, 0, 1));
            push @creators, { value => "$lastname, $initials ($firstname)" };
          }else{
            push @creators, { value => "$lastname, $firstname" };
          }
        }else{
          my $name = $name->find('namePart')->map('text')->join(" ");
          push @creators, { value => $name };
        }
      }
    }

  }

  return \@creators;
}

sub _get_mods_contributors {
  my ($self, $c, $dom, $mode) = @_;

  my @contributors;

  for my $name ($dom->find('mods name[type="personal"]')->each){
    my $role = $name->find('role roleTerm[type="code"][authority="marcrelator"]')->first;
    if(defined($role)){
      $role = $role->text;
      if($mods_contributor_roles{$role}){
        my $firstname = $name->find('namePart[type="given"]')->map('text')->join(" ");
        my $lastname = $name->find('namePart[type="family"]')->map('text')->join(" ");

        if(defined($firstname) && $firstname ne '' && defined($lastname) && $lastname ne ''){
          if($mode eq 'oai'){
            # APA bibliographic style
            my $initials = ucfirst(substr($firstname, 0, 1));
            push @contributors, { value => "$lastname, $initials ($firstname)" };
          }else{
            push @contributors, { value => "$lastname, $firstname" };
          }
        }else{
          my $namepart = $name->find('namePart')->map('text')->join(" ");
          push @contributors, { value => $namepart };
        }
      }
    }

  }

  for my $name ($dom->find('mods name[type="corporate"]')->each){
    my $namepart = $name->find('namePart')->map('text')->join(" ");
    push @contributors, { value => $namepart };
  }

  return \@contributors;
}

sub _get_mods_relations {
  my ($self, $c, $dom) = @_;

  my @relations;

  # find relateditem
  for my $e ($dom->find('mods relatedItem')->each){

    # identifier
    for my $id ($e->find('identifier')->each){
      push @relations, { value => $id->text };
    }

    #title
    for my $titleInfo ($e->find('titleInfo')->each){
      my $tit = $e->find('title')->map('text')->join(" ");
      my $subtit = $e->find('subTitle')->map('text')->join(" ");

      if($subtit && $subtit ne ''){
        $tit .= ": $subtit";
      }
      push @relations, { value => $tit };
    }
  }

  return \@relations;
}

sub _get_mods_titles {
  my ($self, $c, $dom) = @_;

  my @tits; # yes, tits
  # each titleInfo will be a separate title
  for my $e ($dom->find('titleInfo')->each){
    # there should be one title element, whatewer attribute is has
    # like tranlsated, parallel and what not
    # it will be simply added as a title in dc
    # if there is a subtitle, it will be added with ':' after the title
    my $tit = $e->find('title')->map('text')->join(" ");
    my $subtit = $e->find('subTitle')->map('text')->join(" ");
    if($subtit && $subtit ne ''){
      $tit .= ": $subtit";
    }

    push @tits, { value => $tit };
  }

  return \@tits;
}

sub _get_mods_element_values {

  my ($self, $c, $dom, $elm) = @_;

  my @vals;
  for my $e ($dom->find($elm)->each){
    my %v = ( value => $e->text );
    if($e->attr('lang')){
        $v{lang} = $e->attr('lang');
    }
    push @vals, \%v;
  }

  return \@vals;
}

sub generate_dc_from_uwmetadata {

  my ($self, $c, $pid, $dscontent, $username, $password) = @_;

  my $res = { alerts => [], status => 200 };

  my $object_model = PhaidraAPI::Model::Object->new;
  my $cmodel = $object_model->get_cmodel($c, $pid);

  my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
  my $res = $metadata_model->metadata_tree($c);
  if($res->{status} ne 200){
    return $res;
  }
      
  my ($dc_p, $dc_oai) = $self->map_uwmetadata_2_dc($c, $pid, $cmodel, $dscontent, $res->{metadata_tree}, $metadata_model);

  # Phaidra DC
  my $r1 = $object_model->add_or_modify_datastream($c, $pid, "DC_P", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_p, "X", $username, $password);
  foreach my $a (@{$r1->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r1->{status} ne 200){
    $res->{status} = $r1->{status};
  }

  # OAI DC - unqualified
  my $r2 = $object_model->add_or_modify_datastream($c, $pid, "DC_OAI", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_oai, "X", $username, $password);
  foreach my $a (@{$r2->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r2->{status} ne 200){
    $res->{status} = $r2->{status};
  }

  return $res;
}

sub map_uwmetadata_2_dc {

  my ($self, $c, $pid, $cmodel, $xml, $tree, $metadata_model) = @_;

  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($xml);

  # fill $doc_ns, namespace mapping for this document
  my $nss = $dom->find('uwmetadata')->first->attr;
  for my $nsa_key (keys %{$nss}){
    $nsa_key =~ /(\w+):(\w+)/;
    $doc_uwns{$uwns{$nss->{$nsa_key}}} = $2;
  }

  my $titles = $self->_get_titles($c, $dom);
  my $creators_p = $self->_get_creators($c, $dom, 'p');
  my $creators_oai = $self->_get_creators($c, $dom, 'oai');
  my $dates = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'digitalbook'}.'\:releaseyear');
  unless(defined($dates)){
    $dates = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:upload_date');
  }
  my $embargodates = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'extended'}.'\:infoeurepoembargo');
  for my $em (@{$embargodates}){
    push $dates, $em;
  }
  my $types_p = $self->_get_types($c, $cmodel, $dom, $tree, $metadata_model, 'p');
  my $types_oai = $self->_get_types($c, $cmodel, $dom, $tree, $metadata_model, 'oai');

  my $versions_p = $self->_get_versions($c, $dom, $tree, $metadata_model, 'p');
  my $versions_oai = $self->_get_versions($c, $dom, $tree, $metadata_model, 'oai');

  my $formats = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:format');
  my $ids = $self->_get_identifiers($c, $dom, $tree, $metadata_model);
  my $srcs = $self->_get_sources($c, $dom, $tree, $metadata_model);

  my $publishers_p = $self->_get_publishers($c, $dom, 'p');
  my $publishers_oai = $self->_get_publishers($c, $dom, 'oai');

  my $contributors_p = $self->_get_contributors($c, $dom, 'p');
  my $contributors_oai = $self->_get_contributors($c, $dom, 'oai');

  my $relations = $self->_get_uwm_relations($c, $dom);

  my $coverages = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:coverage');

  my $infoeurepoaccess_p = $self->_get_infoeurepoaccess($c, $dom, $tree, $metadata_model, 'p');
  my $infoeurepoaccess_oai = $self->_get_infoeurepoaccess($c, $dom, $tree, $metadata_model, 'oai');

  # FIXME 'description or additional data' have to go to dc:rights too
  my $licenses = $self->_get_licenses($c, $dom, $tree, $metadata_model);

  # FIXME GEO datastream to DCMI BOX

  my %dc_p;
  $dc_p{title} = $titles if(defined($titles));
  $dc_p{creator} = $creators_p if(defined($creators_p));
  $dc_p{date} = $dates if(defined($dates));
  $dc_p{type} = $types_p;
  $dc_p{source} = $srcs;
  for my $v (@$versions_p){
    push @{$dc_p{type}}, $v;
  }
  $dc_p{format} = $formats;
  $dc_p{identifier} = $ids;
  $dc_p{publisher} = $publishers_p if(defined($publishers_p));
  $dc_p{contributor} = $contributors_p if(defined($contributors_p));
  $dc_p{relation} = $relations;
  $dc_p{coverage} = $coverages;
  $dc_p{rights} = $licenses;
  for my $v (@{$infoeurepoaccess_p}){
    push @{$dc_p{rights}}, $v;
  }
  #$c->app->log->debug("XXXXXXXXXXX dc_p hash:".$c->app->dumper(\%dc_p));
  my $dc_p_xml = $self->_create_dc_from_hash($c, \%dc_p);
  #$c->app->log->debug("XXXXXXXXXXX dc_p xml:".$dc_p_xml);

  # see https://guidelines.openaire.eu/wiki/OpenAIRE_Guidelines:_For_Literature_repositories
  my %dc_oai = %dc_p;
  $dc_oai{creator} = $creators_oai if(defined($creators_oai));
  $dc_oai{type} = $types_oai;
  for my $v (@$versions_oai){
    push @{$dc_oai{type}}, $v;
  }
  $dc_oai{publisher} = $publishers_oai if(defined($publishers_oai));
  $dc_oai{contributor} = $contributors_oai if(defined($contributors_oai));
  $dc_oai{rights} = $licenses;
  for my $v (@{$infoeurepoaccess_oai}){
    push @{$dc_oai{rights}}, $v;
  }
  #$c->app->log->debug("XXXXXXXXXXX dc_oai hash:".$c->app->dumper(\%dc_oai));
  my $dc_oai_xml = $self->_create_dc_from_hash($c, \%dc_oai);
  #$c->app->log->debug("XXXXXXXXXXX dc_oai xml:".$dc_oai_xml);

  return ($dc_p_xml, $dc_oai_xml);
}

sub _get_uwm_relations {
  my ($self, $c, $dom) = @_;

  my $relations;
  for my $idnode ($dom->find($doc_uwns{'histkult'}.'\:reference_number')->each){
    my $res = $idnode->find($doc_uwns{'histkult'}.'\:reference')->first;
    if(defined($res)){
      $res = $res->text;
    }
    #my $reslabel;
    #if(defined($res)){
    #  $reslabel = $self->_get_value_label($c, $doc_uwns{'extended'}, 'resource', $res->text, $uw_vocs{'reference'} $tree, $metadata_model, 'en');
    #}
    my $id = $idnode->find($doc_uwns{'histkult'}.'\:number')->first;
    if(defined($id) && $id->text ne ''){
      my $prefix = '';
      if($res eq '1556222'){
        push @$relations, { value => 'info:eu-repo/grantAgreement/EC/FP7/'.$id->text };
      }
    }
  }

  return $relations;
}

sub _get_sources {
  my ($self, $c, $dom, $tree, $metadata_model) = @_;

  my $srcs;
  for my $idnode ($dom->find($doc_uwns{'extended'}.'\:identifiers')->each){
    my $res = $idnode->find($doc_uwns{'extended'}.'\:resource')->first;
    if(defined($res)){
      $res = $res->text;
    }
    #my $reslabel;
    #if(defined($res)){
    #  $reslabel = $self->_get_value_label($c, $doc_uwns{'extended'}, 'resource', $res->text, $uw_vocs{'resource'}, $tree, $metadata_model, 'en');
    #}
    my $id = $idnode->find($doc_uwns{'extended'}.'\:identifier')->first;
    if(defined($id) && $id->text ne ''){
      my $prefix = '';
      if($res eq '1552101' || $res eq '1552255' || $res eq '1552256'){
        push @$srcs, { value => 'ISSN:'.$id->text };
      }

    }
  }

  my $journal = $dom->find($doc_uwns{'digitalbook'}.'\:name_magazine')->first;
  $journal = $journal->text if(defined($journal));

  my $volume = $dom->find($doc_uwns{'digitalbook'}.'\:volume')->first;
  $volume = $volume->text if(defined($volume));

  my $booklet = $dom->find($doc_uwns{'digitalbook'}.'\:booklet')->first;
  $booklet = $booklet->text if(defined($booklet));

  my $from = $dom->find($doc_uwns{'digitalbook'}.'\:from_page')->first;
  $from = $from->text if(defined($from));

  my $to = $dom->find($doc_uwns{'digitalbook'}.'\:to_page')->first;
  $to = $to->text if(defined($to));

  my $releaseyear = $dom->find($doc_uwns{'digitalbook'}.'\:releaseyear')->first;
  $releaseyear = $releaseyear->text if(defined($releaseyear));

  my $source = $journal;
  $source .= " $volume" if(defined($volume) && $volume ne '');
  $source .= "($booklet)" if(defined($booklet) && $booklet ne '');
  $source .= ", $from" if(defined($from) && $from ne '');
  $source .= "-$to" if(defined($to) && $to ne '');
  $source .= " ($releaseyear)" if(defined($releaseyear) && $releaseyear ne '');
  if (defined($journal) && $journal ne '')
  {
    push @{$srcs}, { value => $source };
  }

  return $srcs;
}

sub _get_identifiers {
  my ($self, $c, $dom, $tree, $metadata_model) = @_;

  my $ids;
  for my $idnode ($dom->find($doc_uwns{'extended'}.'\:identifiers')->each){
    my $res = $idnode->find($doc_uwns{'extended'}.'\:resource')->first;
    if(defined($res)){
      $res = $res->text;
    }
    #my $reslabel;
    #if(defined($res)){
    #  $reslabel = $self->_get_value_label($c, $doc_uwns{'extended'}, 'resource', $res->text, $uw_vocs{'resource'}, $tree, $metadata_model, 'en');
    #}
    my $id = $idnode->find($doc_uwns{'extended'}.'\:identifier')->first;
    if(defined($id) && $id->text ne ''){
      my $prefix = '';
      if($res eq '1552099'){
        push @$ids, { value => 'http://dx.doi.org/'.$id->text };
      }
      if($res eq '1552103'){
        push @$ids, { value => 'urn:'.$id->text };
      }
    }
  }
  return $ids;
}

sub _get_licenses {

  my ($self, $c, $dom, $tree, $metadata_model) = @_;

  my @arr;
  my $vals = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:license');

  my $licenses_model = PhaidraAPI::Model::Licenses->new;
  my $licenses = $licenses_model->get_licenses($c);
  for my $v (@{$vals}){
    my $lic_label = '';
    my $lic_link = '';
    for my $lic (@{$licenses->{licenses}}){
      if($v->{value} eq $lic->{lid}){
        push @arr, { value => $lic->{labels}->{en} };
        push @arr, { value => $lic->{link_uri} };
      }
    }
  }

  return \@arr;
}

sub _get_infoeurepoaccess {

  my ($self, $c, $dom, $tree, $metadata_model, $mode) = @_;

  my @acc;
  my $vals = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'extended'}.'\:infoeurepoaccess');

  for my $v (@{$vals}){
    #$c->app->log->debug("XXXXXXXX ".$v->{value});
    my $acclabel = $self->_get_value_label($c, $uwns_rev{'extended'}, 'infoeurepoaccess', $v->{value}, $uw_vocs{'infoeurepoaccess'}, $tree, $metadata_model, 'en');
    #$c->app->log->debug("XXXXXXXX ".$c->app->dumper($vals));
    if($mode eq 'oai'){
      push @acc, { value => "info:eu-repo/semantics/$acclabel"};
    }else{
      push @acc, { value => $acclabel};
    }
  }

  return \@acc;
}

sub _get_value_label {
  my ($self, $c, $ns, $xmlname, $id, $vocid, $tree, $metadata_model, $lang) = @_;

  my $n = $metadata_model->get_json_node($c, $ns, $xmlname, $tree);
  foreach my $term (@{$n->{vocabularies}[0]->{terms}}){
    if($term->{uri} eq $ns."/voc_$vocid/$id"){
      return $term->{labels}->{$lang};
    }
  }
}

sub _get_types {
  my ($self, $c, $cmodel, $dom, $tree, $metadata_model, $mode) = @_;

  my $types;
  if(my $hst = $dom->find($doc_uwns{'organization'}.'\:hoschtyp')->first){
    my $id = $hst->text;
    my $n = $metadata_model->get_json_node($c, $uwns_rev{'organization'}, 'hoschtyp', $tree);
    foreach my $term (@{$n->{vocabularies}[0]->{terms}}){
      if($term->{uri} eq $uwns_rev{'organization'}."/voc_".$uw_vocs{'hoschtyp'}."/$id"){

        if($mode eq 'oai'){

          if($id eq '1552261' || $id eq '1552259' || $id eq '1743' || $id eq '1552258'){
            # 1) in case it's a value which is not supported by OpenAIRE, put 'Other'
            # "Lecture series (one person)", "Multimedia", "Professorial Dissertation", "Theses"
            push @{$types}, { value => "info:eu-repo/semantics/other" };
          }elsif($id eq '1739' || $id eq '1740' || $id eq '1741'){
            # 2) mapping of "Diploma Dissertation", "Master's (Austria) Dissertation", "Master's Dissertation"
            push @{$types}, { value => "info:eu-repo/semantics/masterThesis" };
          }else{
            my $value = $term->{labels}->{en};
            $value = lcfirst($value);
            $value =~ s/\s+//g;
            push @{$types}, { value => "info:eu-repo/semantics/".$value };
          }
        }elsif($mode eq 'p'){
          # en, I think we should not need this in another language really..
          push @{$types}, { value => lcfirst($term->{labels}->{en}), lang => 'en' };
        }

      }
    }
  }
  if(defined($types) && scalar @{$types} > 0){
    return $types;
  }

  if(defined($cmodel) && exists($cmodelMapping{$cmodel})){
    return $cmodelMapping{$cmodel};
  }

}

sub _get_entities {
  my ($self, $c, $contributions, $type) = @_;

  my @res;
  for my $ctr (@{$contributions}){
    for my $e ($ctr->find($doc_uwns{'lom'}.'\:entity')->sort(sub{ $a->attr('seq') cmp $b->attr('seq') })->each){
      my $firstname = $e->find($doc_uwns{'entity'}.'\:firstname')->first;
      if(defined($firstname)){
        $firstname = $firstname->text;
      }
      my $lastname = $e->find($doc_uwns{'entity'}.'\:lastname')->first;
      if(defined($lastname)){
        $lastname = $lastname->text;
      }

      if($firstname && $lastname){
        if($type eq 'oai'){
          # APA bibliographic style
          my $initials = ucfirst(substr($firstname, 0, 1));
          push @res, { value => "$lastname, $initials ($firstname)"};
        }else{
          push @res, { value => "$lastname, $firstname"};
        }
      }else{
        push @res, { value => $firstname } if(defined($firstname) && $firstname ne '');
        push @res, { value => $lastname } if(defined($lastname) && $lastname ne '');
      }

      my $institution = $e->find($doc_uwns{'entity'}.'\:institution')->first;
      if(defined($institution)){
        $institution = $institution->text;
      }

      if(defined($institution) &&  $institution ne ''){
        if ($c->app->config->{dcaffiliationcodes} && $institution =~ m/(\d)+/){
          if ($c->app->config->{directory}->{org_units_languages})
          {
            foreach my $lang (@{$c->app->config->{directory}->{org_units_languages}})
            {
              if(my $inststr = $self->_get_affiliation_cached($c, $institution, $lang)){
                push @res, { value => $inststr, lang => $lang };
              }
            }
          }
        }
        else
        {
          push @res, { value => $institution } if ($institution ne '');
        }
      }
    }
  }

  return @res;
}


sub _get_contributors {

  my ($self, $c, $dom, $type) = @_;

  my @conts;
  my @editors;
  my $has_authors = 0;
  for my $con ($dom->find($doc_uwns{'lom'}.'\:contribute')->sort(sub{ $a->attr('seq') cmp $b->attr('seq') })->each){
    my $role = $con->find($doc_uwns{'lom'}.'\:role')->first->text;
    # save editors, we need them if there *are* authors defined
    if($role eq $non_contributor_role_ids{'editor'}){
      push @editors, $con;
    }
    if($role eq $non_contributor_role_ids{'author_analog'} || $role eq $non_contributor_role_ids{'author_digital'}){
      $has_authors = 1;
    }
    if(!exists($non_contributor_role_ids_rev{$role})){
      push @conts, $con;
    };
  }

  # if there are no authors then editors are creators
  # if there are authors then editors are contributors
  if($has_authors){
    for my $e (@editors){
      push @conts, $e;
    }
  }

  my @res = $self->_get_entities($c, \@conts, $type);

  return \@res;
}

sub _get_publishers {

  my ($self, $c, $dom, $type) = @_;

  my @publishers;
  for my $con ($dom->find($doc_uwns{'lom'}.'\:contribute')->sort(sub{ $a->attr('seq') cmp $b->attr('seq') })->each){
    my $role = $con->find($doc_uwns{'lom'}.'\:role')->first->text;
    if($role eq $non_contributor_role_ids{'publisher'}){
      push @publishers, $con;
    };
  }

  my @res = $self->_get_entities($c, \@publishers, $type);

  my $publishers = $dom->find($doc_uwns{'digitalbook'}.'\:publisher')->first;
  push @res, $publishers->text if(defined($publishers));

  return \@res;
}

sub _get_creators {

  my ($self, $c, $dom, $type) = @_;

  my %creators;
  for my $con ($dom->find($doc_uwns{'lom'}.'\:contribute')->sort(sub{ $a->attr('seq') cmp $b->attr('seq') })->each){
    my $role = $con->find($doc_uwns{'lom'}.'\:role')->first->text;
    if($role eq $non_contributor_role_ids{'author_analog'}){
      push @{$creators{author_analog}}, $con;
    };
    if($role eq $non_contributor_role_ids{'author_digital'}){
      push @{$creators{author_digital}}, $con;
    };
    if($role eq $non_contributor_role_ids{'editor'}){
      push @{$creators{editor}}, $con;
    };
  }

  my @creators;
  if(exists($creators{author_analog}) && scalar @{$creators{author_analog}} > 0){
    @creators = @{$creators{author_analog}};
  }elsif(exists($creators{author_digital}) && scalar @{$creators{author_digital}} > 0){
    @creators = @{$creators{author_digital}};
  }elsif(exists($creators{editor}) && scalar @{$creators{editor}} > 0){
    @creators = @{$creators{editor}};
  }

  my @res = $self->_get_entities($c, \@creators, $type);

  return \@res;
}

sub _get_affiliation_cached {
  my ($self, $c, $code, $lang) = @_;

  my $inststr;
  my $cachekey = 'affid_'.$code.'_'.$lang;
  unless($inststr = $c->app->chi->get($cachekey))
  {
    # FIXME: test!!
    $inststr = "blabla";#$c->app->directory->get_affiliation($c, $code, $lang);
    $c->app->chi->set($cachekey, $inststr, '1 day');
  }

  return $inststr;
}

sub _get_titles {

  my ($self, $c, $dom) = @_;

  my $maintitles = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:title');
  my $subtitles = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'extended'}.'\:subtitle');

  # merge titles and subtitles
  my $titles;
  for my $mt (@{$maintitles}){
    if(exists($mt->{lang})){ # should always
      my $found = 0;
      # find subtitle with matching language
      for my $st (@{$subtitles}){
        if($mt->{lang} eq $st->{lang}){
          push @{$titles}, { value => $mt->{value}.': '.$st->{value}, lang => $mt->{lang}};
          $found = 1;
        }
      }
      if(!$found){
        push @{$titles}, $mt;
      }
    }
  }

  return $titles;
}

sub _get_versions {

  my ($self, $c, $dom, $tree, $metadata_model, $mode) = @_;

  my @vals;
  for my $e ($dom->find($doc_uwns{'extended'}.'\:infoeurepoversion')->each){
    my %v = ( ns => $e->namespace );

    my $n = $metadata_model->get_json_node($c, $uwns_rev{'extended'}, 'infoeurepoversion', $tree);
    foreach my $term (@{$n->{vocabularies}[0]->{terms}}){
      my $id = $e->text;
      if($term->{uri} eq $uwns_rev{'extended'}."/voc_".$uw_vocs{'infoeurepoversion'}."/$id"){
        if($mode eq 'oai'){
          $v{value} = "info:eu-repo/semantics/".$term->{labels}->{en};
        }else{
          $v{value} = $term->{labels}->{en};
        }
        push @vals, \%v;
      }
    }

  }

  return \@vals;
}

sub _get_uwm_element_values {

  my ($self, $c, $dom, $elm) = @_;

  my @vals;
  for my $e ($dom->find($elm)->each){
    my %v = ( value => $e->text, ns => $e->namespace );
    if($e->attr('language')){
        $v{lang} = $e->attr('language');
    }
    push @vals, \%v;
  }

  return \@vals;
}

sub _create_dc_from_hash {

  my ($self, $c, $dc) = @_;

  my $dc_xml = '<oai_dc:dc xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/">'."\n";
  foreach my $k (keys %{$dc})
  {
    next unless $dc->{$k};    
    foreach my $n (@{$dc->{$k}}){
      next if ($n eq '');      
      next unless (defined ($n->{value}));

      $dc_xml .= '   <dc:' . $k;
      $dc_xml .= ' xml:lang="' . $PhaidraAPI::Model::Util::iso639map{$n->{lang}} . '"'if (exists($n->{lang}));
      $dc_xml .= '>' . xml_escape($n->{value}) . '</dc:' . $k . ">\n";
    }
  }
  $dc_xml .= "</oai_dc:dc>\n";

  return $dc_xml;
}

1;
__END__