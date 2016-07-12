package PhaidraAPI::Model::Dc;

use strict;
use warnings;
use v5.10;
use utf8;
use Mojo::ByteStream qw(b);
use Mojo::Util qw(xml_escape encode decode);
use base qw/Mojo::Base/;
use XML::LibXML;
use Storable qw(dclone);
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Util;
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Licenses;
use PhaidraAPI::Model::Terms;
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Languages;

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

  my $output_label = ($dsid eq 'DC_P') || ($dsid eq 'DC') ? 'dc' : 'oai_dc';
  return $self->xml_2_json($c, $res->{$dsid}, $output_label);

}


sub generate_dc_from_mods {

  my ($self, $c, $pid, $dscontent, $username, $password) = @_;

  my $res = { alerts => [], status => 200 };
  
  my $object_model = PhaidraAPI::Model::Object->new;
  my $search_model = PhaidraAPI::Model::Search->new;
  my $mods_model = PhaidraAPI::Model::Uwmetadata->new;

  my $cmodel;
  
  my $res_cmodel = $search_model->get_cmodel($c, $pid);
  foreach my $a (@{$res_cmodel->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($res_cmodel->{status} ne 200){
    $res->{status} = $res_cmodel->{status};
  }else{
    $cmodel = $res_cmodel->{cmodel};
  }  

  my ($dc_p, $dc_oai) = $self->map_mods_2_dc($c, $pid, $cmodel, $dscontent, $mods_model);

  # Phaidra DC
  my $r1 = $object_model->add_or_modify_datastream($c, $pid, "DC_P", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_p, "X", $username, $password, 1);
  foreach my $a (@{$r1->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r1->{status} ne 200){
    $res->{status} = $r1->{status};
  }

  # OAI DC - unqualified
  my $r2 = $object_model->add_or_modify_datastream($c, $pid, "DC_OAI", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_oai, "X", $username, $password, 1);
  foreach my $a (@{$r2->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r2->{status} ne 200){
    $res->{status} = $r2->{status};
  }

  # we have to add this because we need that info in triplestore and old hooks won't update DC for MODS
  $r1 = $object_model->add_or_modify_datastream($c, $pid, "DC", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_p, "X", $username, $password, 1);
  foreach my $a (@{$r1->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r1->{status} ne 200){
    $res->{status} = $r1->{status};
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
  $dc_p{subject} = $self->_get_mods_subjects($c, $dom);
  my $classifications = $self->_get_mods_classifications($c, $dom);
  push @{$dc_p{subject}}, @$classifications;
  $dc_p{identifier} = $self->_get_mods_element_values($c, $dom, 'mods > identifier');
  push @{$dc_p{identifier}}, { value => "http://".$c->app->config->{phaidra}->{baseurl}."/".$pid };
  my $relids = $self->_get_relsext_identifiers($c, $pid);
  for my $relid (@$relids){
    push @{$dc_p{identifier}}, $relid;
  }
  $dc_p{relation} = $self->_get_mods_relations($c, $dom);
  my $editions = $self->_get_mods_element_values($c, $dom, 'mods > originInfo > edition');
  push @{$dc_p{relation}}, @$editions;
  $dc_p{language} = $self->_get_mods_element_values($c, $dom, 'mods > language > languageTerm');
  $dc_p{creator} = $self->_get_mods_creators($c, $dom, 'p');
  $dc_p{contributor} = $self->_get_mods_contributors($c, $dom, 'p');
  $dc_p{date} = $self->_get_mods_element_values($c, $dom, 'mods > originInfo > dateIssued[keyDate="yes"]');
  $dc_p{description} = $self->_get_mods_element_values($c, $dom, 'mods > note');
  # maps specific
  my $scales = $self->_get_mods_element_values($c, $dom, 'mods > subject > cartographics > scale');
  my @scales_arr = map { { value => "1:".$_->{value} } } @$scales;
  push @{$dc_p{description}}, @scales_arr;

  my $extents = $self->_get_mods_element_values($c, $dom, 'mods > physicalDescription > extent');
  push @{$dc_p{description}}, @$extents;

  $dc_p{publisher} = $self->_get_mods_element_values($c, $dom, 'mods > originInfo > publisher');

  # place of publishing should not be dc:publisher
  #my $publisher_places = $self->_get_mods_element_values($c, $dom, 'mods > originInfo > place > placeTerm');
  #push @{$dc_p{publisher}}, @$publisher_places;

  $dc_p{rights} = $self->_get_mods_element_values($c, $dom, 'mods > accessCondition[type="use and reproduction"]');

  my $filesize = $self->_get_dsinfo_filesize($c, $pid, $cmodel);
  push @{$dc_p{format}} => { value => "$filesize bytes" };

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
    my $text = $e->text;
    if(defined($text) && $text ne ''){
      if(defined($e->attr->{authority}) && $e->attr->{authority} ne ''){
        $text = $e->attr->{authority}.": ".$text; 
      }
      push @cls, { value => $text };
    }else{
      if(defined($e->attr->{valueURI})){    
        my $uri = $e->attr->{valueURI};
        my $terms_model = PhaidraAPI::Model::Terms->new;
        my $res = $terms_model->label($c, $uri); 
        if($res->{status} eq 200){
          if(defined($res->{labels})){
            if(defined($res->{labels}->{labels})){
              # use only en if available
              if(defined($res->{labels}->{labels}->{en})){
                push @cls, { value => $res->{labels}->{labels}->{en}, lang => 'eng' };
              }else{
                # if en not available, use everything else
                if(defined($res->{labels}->{labels}->{de})){
                  push @cls, { value => $res->{labels}->{labels}->{de}, lang => 'deu' };
                }
                if(defined($res->{labels}->{labels}->{it})){
                  push @cls, { value => $res->{labels}->{labels}->{it}, lang => 'ita' };
                }
              }
            }
          }
        }else{
          $c->app->log->error("Could not fetch label for classification uri[$uri] res=".$c->app->dumper($res));
        }
      }
    }
    
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

sub _get_mods_subjects {
  my ($self, $c, $dom) = @_;

  my @subs;

  for my $e ($dom->find('subject')->each){
    my @s_arr;
    # not 'cartographics' (scale is saved there), that goes to description
    push @s_arr, $e->find('geographic')->map('text')->join(";");
    push @s_arr, $e->find('topic')->map('text')->join(";");
    push @s_arr, $e->find('genre')->map('text')->join(";");
    push @s_arr, $e->find('temporal')->map('text')->join(";");
    for my $n ($e->find('name')->each){
      push @s_arr, $n->find('namePart')->map('text')->join(",");      
    }    

    @s_arr = grep defined, @s_arr;
    @s_arr = grep /\w+/, @s_arr;
    my $cnt = scalar @s_arr;
    if($cnt > 0){
      push @subs, { value => join(';', @s_arr) };
    }
  }

  return \@subs;
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
  my $search_model = PhaidraAPI::Model::Search->new;
  my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;

  my $cmodel;
  
  my $res_cmodel = $search_model->get_cmodel($c, $pid);
  foreach my $a (@{$res_cmodel->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($res_cmodel->{status} ne 200){
    $res->{status} = $res_cmodel->{status};
  }else{
    $cmodel = $res_cmodel->{cmodel};
  }  
  
  my $r0 = $metadata_model->metadata_tree($c);
  if($r0->{status} ne 200){
    return $res;
  }

  my ($dc_p, $dc_oai) = $self->map_uwmetadata_2_dc($c, $pid, $cmodel, $dscontent, $r0->{metadata_tree}, $metadata_model);

  # Phaidra DC
  my $r1 = $object_model->add_or_modify_datastream($c, $pid, "DC_P", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_p, "X", $username, $password, 1);
  foreach my $a (@{$r1->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r1->{status} ne 200){
    $res->{status} = $r1->{status};
  }

  # OAI DC - unqualified
  my $r2 = $object_model->add_or_modify_datastream($c, $pid, "DC_OAI", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_oai, "X", $username, $password, 1);
  foreach my $a (@{$r2->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r2->{status} ne 200){
    $res->{status} = $r2->{status};
  }

  # Fedora's DC - for backward compatibility with frontend which only updates DC (see Hooks)

  my $r3 = $object_model->add_or_modify_datastream($c, $pid, "DC", "text/xml", undef, $c->app->config->{phaidra}->{defaultlabel}, $dc_p, "X", $username, $password, 1);
  foreach my $a (@{$r3->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  if($r3->{status} ne 200){
    $res->{status} = $r3->{status};
  }


  return $res;
}

sub map_uwmetadata_2_dc {

  my ($self, $c, $pid, $cmodel, $xml, $tree, $metadata_model) = @_;

  my ($dc_p, $dc_oai) = $self->map_uwmetadata_2_dc_hash($c, $pid, $cmodel, $xml, $tree, $metadata_model);
  
  my $dc_p_xml = $self->_create_dc_from_hash($c, $dc_p);
  my $dc_oai_xml = $self->_create_dc_from_hash($c, $dc_oai);

  return ($dc_p_xml, $dc_oai_xml);
}

sub map_uwmetadata_2_dc_hash {

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

  my $identifiers = $self->_get_uwm_identifiers($c, $dom, $tree, $metadata_model);
  my $relids = $self->_get_relsext_identifiers($c, $pid);
  for my $relid (@$relids){
    push @$identifiers, $relid;
  }
  my $titles = $self->_get_titles($c, $dom);
  my $descriptions = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:description');
  my $languages = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:language');
  my $keywords = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:keyword');
  my $classifications = $self->_get_uwm_classifications($c, $dom);
  my $creators_p = $self->_get_creators($c, $dom, 'p');
  my $creators_oai = $self->_get_creators($c, $dom, 'oai');
  my $dates = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'digitalbook'}.'\:releaseyear');
  unless(defined($dates)){
    $dates = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:upload_date');
  }
  my $embargodates = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'extended'}.'\:infoeurepoembargo');
  $dates= [] unless (defined ($dates)); # this should fix this error: [Tue Mar 15 15:45:50 2016] [error] Type of arg 1 to push must be array (not private variable) at PhaidraAPI/Model/Dc.pm line 581, near "$em;"
  for my $em (@{$embargodates}){
    push @$dates, $em;
  }
  my $types_p = $self->_get_types($c, $cmodel, $dom, $tree, $metadata_model, 'p');
  my $types_oai = $self->_get_types($c, $cmodel, $dom, $tree, $metadata_model, 'oai');

  my $versions_p = $self->_get_versions($c, $dom, $tree, $metadata_model, 'p');
  my $versions_oai = $self->_get_versions($c, $dom, $tree, $metadata_model, 'oai');

  my $formats = $self->_get_formats($c, $pid, $cmodel, $dom);
  
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
  # <dc:subject xml:lang="deu">Apostelkommunion, tribelon</dc:subject>
  # <dc:subject xml:lang="eng">last supper, tribelon</dc:subject>
  my $licenses = $self->_get_licenses($c, $dom, $tree, $metadata_model);

  # FIXME GEO datastream to DCMI BOX

  # get provenience versions


  push @$identifiers, { value => "http://".$c->app->config->{phaidra}->{baseurl}."/".$pid };

  my @subjects;
  for my $k (@{$keywords}){
    push @subjects, $k;
  }
  for my $c (@{$classifications}){
    push @subjects, $c;
  }
  
  my @langs;  
  for my $l (@{$languages}){
    unless($l->{value} eq 'xx'){
      push @langs, { value => $PhaidraAPI::Model::Languages::iso639map{$l->{value}} };
    }
  }

  for my $v (@$creators_p){
if(ref($v) eq 'HASH'){
    if(defined($v->{date}) && ($v->{date} ne '')) {
      push @$dates, { value => $v->{date}};
    }
}
  }
  for my $v (@$publishers_p){
   if(ref($v) eq 'HASH'){
    if(defined($v->{date}) && ($v->{date} ne '')) {
      push @$dates, { value => $v->{date}};
    }
   }
  }
  for my $v (@$contributors_p){
if(ref($v) eq 'HASH'){
    if(defined($v->{date}) && ($v->{date} ne '')) {
      push @$dates, { value => $v->{date}};
}   
 }
  }

  my %dc_p;
  $dc_p{identifier} = $identifiers if(defined($identifiers));
  $dc_p{title} = $titles if(defined($titles));
  $dc_p{description} = $descriptions if(defined($descriptions));
  $dc_p{subject} = \@subjects if(@subjects);
  $dc_p{language} = \@langs if(@langs);
  $dc_p{creator} = $creators_p if(defined($creators_p));
  $dc_p{date} = $dates if(defined($dates));
  $dc_p{type} = $types_p;
  $dc_p{source} = $srcs;
  for my $v (@$versions_p){
    push @{$dc_p{type}}, $v;
  }
  $dc_p{format} = $formats;
  $dc_p{publisher} = $publishers_p if(defined($publishers_p));
  $dc_p{contributor} = $contributors_p if(defined($contributors_p));
  $dc_p{relation} = $relations;
  $dc_p{coverage} = $coverages;
  # copy this, not just assign reference
  # otherwise the $license will contain the $infoeurepoaccess_p values later
  for my $v (@{$licenses}){ 
    push @{$dc_p{rights}}, $v;
  }
  for my $v (@{$infoeurepoaccess_p}){
    push @{$dc_p{rights}}, $v;
  }

  # see https://guidelines.openaire.eu/wiki/OpenAIRE_Guidelines:_For_Literature_repositories
  my $dc_oai = dclone \%dc_p;
  $dc_oai->{creator} = $creators_oai if(defined($creators_oai));
  $dc_oai->{type} = $types_oai;
  for my $v (@$versions_oai){
    push @{$dc_oai->{type}}, $v;
  }
  $dc_oai->{rights} = ();
  for my $v (@{$licenses}){ 
    push @{$dc_oai->{rights}}, $v;
  }
  for my $v (@{$infoeurepoaccess_oai}){
    push @{$dc_oai->{rights}}, $v;
  }
  $dc_oai->{publisher} = $publishers_oai if(defined($publishers_oai));
  $dc_oai->{contributor} = $contributors_oai if(defined($contributors_oai));


  return (\%dc_p, $dc_oai);
}

sub _get_relsext_identifiers {
  my ($self, $c, $pid) = @_;

  my @ids;
  my $search_model = PhaidraAPI::Model::Search->new;

  my $query = "<info:fedora/$pid> <http://purl.org/dc/terms/identifier> *";
  my $sr = $search_model->triples($c, $query, 0);
  unless($sr->{status} eq 200){
    $c->app->log->error("Could not query triplestore for identifiers.");
    return \@ids;
  }

  for my $triple (@{$sr->{result}}){
    my $id = @$triple[2];
    $id =~ s/^\<+|\>+$//g;
    push @ids, { value => $id };
  }

  return \@ids;
}

# {i}, {b}, {br}, {mailto}, {link}
sub _remove_phaidra_tags($){
  my ($self, $c, $v) = @_;
  $v =~ s/{b}|{\/b}|{i}|{\/i}|{link}|{\/link}|{br}|{mailto}|{\/mailto}//g;
  return $v;
}

sub _get_uwm_classifications {
  my ($self, $c, $dom) = @_;

  my @classifications;
  for my $idnode ($dom->find($doc_uwns{'classification'}.'\:taxonpath')->each){

    my $cid = $idnode->find($doc_uwns{'classification'}.'\:source')->last;
    if(defined($cid)){
      $cid = $cid->text;
    }

    my $tid = $idnode->find($doc_uwns{'classification'}.'\:taxon')->last;
    if(defined($tid)){
      $tid = $tid->text;      
    }

    my $terms_model = PhaidraAPI::Model::Terms->new;
    my $cls_labels = $terms_model->_get_vocab_labels($c, undef, undef, $cid);

    my $labels = $terms_model->_get_taxon_labels($c, $cid, $tid);
    for my $lang (keys %{$labels->{labels}}){
      push @classifications, { value => $cls_labels->{$lang}.", ".$labels->{labels}->{$lang}, lang => $lang };
    }

  }

  return \@classifications;
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

sub _get_uwm_identifiers {
  my ($self, $c, $dom, $tree, $metadata_model) = @_;

  my $identifiers;
  for my $idnode ($dom->find($doc_uwns{'extended'}.'\:identifiers')->each){
    my $res = $idnode->find($doc_uwns{'extended'}.'\:resource')->first;
    my $reslabel;
    if(defined($res)){
      $res = $res->text;
      if($res eq '1552099'){
        $reslabel = 'doi:';
      }
      elsif($res eq '1552103'){
        $reslabel = 'urn:';
      }
      else{        
        $reslabel = $self->_get_value_label($c, $uwns_rev{'extended'}, 'resource', $res, $uw_vocs{'resource'}, $tree, $metadata_model, 'en');
        if($reslabel){
          $reslabel = $reslabel.": ";
        }
      }
    }
    
    my $id = $idnode->find($doc_uwns{'extended'}.'\:identifier')->first;
    if(defined($id) && $id->text ne ''){
      if($reslabel){
        push @$identifiers, { value => "$reslabel".$id->text };
      }else{
        push @$identifiers, { value => $id->text };
      }
    }
  }

  return $identifiers;
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
        push @arr, { value => $lic->{link_uri} } unless $lic->{lid} eq 1;
      }
    }
  }

  return \@arr;
}

sub _get_formats {

  my ($self, $c, $pid, $cmodel, $dom) = @_;
  
  my $formats = $self->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:format');

  # include filesize and mimetype of OCTETS
  
  my $filesize = $self->_get_dsinfo_filesize($c, $pid, $cmodel);
  push @$formats, { value => $filesize." bytes" } if defined($filesize);

  return $formats;
}

sub _get_dsinfo_filesize {

  my ($self, $c, $pid, $cmodel) = @_;
  
  my $search_model = PhaidraAPI::Model::Search->new;
  my $xml = $search_model->_get_dsinfo_xml($c, $pid, $cmodel);

  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($xml);

  my $bytesize;
  for my $e ($dom->find('dsinfo > filesize')->each){
     return $e->text;
  }
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
  #$c->app->log->debug("XXXXXXXXXXX ns[$ns] xmlname[$xmlname] id[$id] vocid[$vocid] node:".$c->app->dumper($n)."tree :".$c->app->dumper($tree)); 
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
  
  unless(defined($types)){        
    if(defined($cmodel) && exists($cmodelMapping{$cmodel})){
      push @{$types}, { value => $cmodelMapping{$cmodel}, lang => 'en' };      
    }
  }

  return $types;

}

sub _get_entities {
  my ($self, $c, $contributions, $ns, $type) = @_;

  my $entity_ns = $doc_uwns{'entity'};
  if($ns eq 'provenience'){
    $entity_ns = $doc_uwns{'provenience_entity'};
  }

  my @res;
  for my $ctr (@{$contributions}){
    for my $e ($ctr->find($doc_uwns{$ns}.'\:entity')->sort(sub{ $a->attr('seq') cmp $b->attr('seq') })->each){
      
      my $firstname = $e->find($entity_ns.'\:firstname')->first;
      if(defined($firstname)){
        $firstname = $firstname->text;
      }
      my $lastname = $e->find($entity_ns.'\:lastname')->first;
      if(defined($lastname)){
        $lastname = $lastname->text;
      }
      my $date = $ctr->find($doc_uwns{$ns}.'\:date')->first;
      if(defined($date)){
        $date = $date->text;
      }

      if($firstname && $lastname){
        if($type eq 'oai'){
          # APA bibliographic style
          my $initials = ucfirst(substr($firstname, 0, 1));
          push @res, { value => "$lastname, $initials ($firstname)", date => $date};
        }else{
          push @res, { value => "$lastname, $firstname", date => $date};
        }
      }else{
        push @res, { value => $firstname, date => $date } if(defined($firstname) && $firstname ne '');
        push @res, { value => $lastname, date => $date } if(defined($lastname) && $lastname ne '');
      }

      my $institution = $e->find($entity_ns.'\:institution')->first;
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
                push @res, { value => $inststr, lang => $lang, date => $date };
              }
            }
          }
        }
        else
        {
          push @res, { value => $institution, date => $date } if ($institution ne '');
        }
      }
    }
  }

  return @res;
}


sub _get_contributors {

  my ($self, $c, $dom, $type) = @_;

  my @res;  
  for my $ns (('lom','provenience')){
    my @conts;
    my @editors;
    my $has_authors = 0;
    for my $con ($dom->find($doc_uwns{$ns}.'\:contribute')->sort(sub{ $a->attr('seq') cmp $b->attr('seq') })->each){      
      my $role = $con->find($doc_uwns{$ns}.'\:role')->first;
      if(defined($role)){
        $role = $role->text;
      
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
    }

    # if there are no authors then editors are creators
    # if there are authors then editors are contributors
    if($has_authors){
      for my $e (@editors){
        push @conts, $e;
      }
    }

    push @res, $self->_get_entities($c, \@conts,  $ns, $type);
  }

  return \@res;
}

sub _get_publishers {

  my ($self, $c, $dom, $type) = @_;

  my @res;
  for my $ns (('lom','provenience')){
    my @publishers;
    for my $con ($dom->find($doc_uwns{$ns}.'\:contribute')->sort(sub{ $a->attr('seq') cmp $b->attr('seq') })->each){
      my $role = $con->find($doc_uwns{$ns}.'\:role')->first;
      if(defined($role)){
        $role = $role->text;
        if($role eq $non_contributor_role_ids{'publisher'}){
          push @publishers, $con;
        };
      }
    }

    push @res, $self->_get_entities($c, \@publishers, $ns, $type);

    # check publisher in digitalbook only once, not for 'provenience' namespace
    if($ns eq 'lom'){
      my $publishers = $dom->find($doc_uwns{'digitalbook'}.'\:publisher')->first;
      push @res, { value => $publishers->text } if(defined($publishers));
    }
  }

  return \@res;
}

sub _get_creators {

  my ($self, $c, $dom, $type) = @_;

  my @res;
  for my $ns (('lom','provenience')){
    my %creators;
    for my $con ($dom->find($doc_uwns{$ns}.'\:contribute')->sort(sub{ $a->attr('seq') cmp $b->attr('seq') })->each){
      my $role = $con->find($doc_uwns{$ns}.'\:role')->first;
      if(defined($role)){
        $role = $role->text;
      
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
    }

    my @creators;
    if(exists($creators{author_analog}) && scalar @{$creators{author_analog}} > 0){
      @creators = @{$creators{author_analog}};
    }elsif(exists($creators{author_digital}) && scalar @{$creators{author_digital}} > 0){
      @creators = @{$creators{author_digital}};
    }elsif(exists($creators{editor}) && scalar @{$creators{editor}} > 0){
      @creators = @{$creators{editor}};
    }

    push @res, $self->_get_entities($c, \@creators, $ns, $type);
  }
  return \@res;
}

sub _get_affiliation_cached {
  my ($self, $c, $code, $lang) = @_;

  my $inststr;
  my $cachekey = 'affid_'.$code.'_'.$lang;
  unless($inststr = $c->app->chi->get($cachekey))
  {
    $c->app->log->debug("[cache miss] $cachekey");
    $inststr = $c->app->directory->get_affiliation($c, $code, $lang);
    $c->app->chi->set($cachekey, $inststr, '1 day');
  }else{
    $c->app->log->debug("[cache hit] $cachekey");
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
    my $value = $e->text;
    $value = $self->_remove_phaidra_tags($c, $value);
    my %v = ( value => $value, ns => $e->namespace );
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

      if(ref($n) eq 'HASH'){
         next unless (defined ($n->{value}));
      
         $dc_xml .= '   <dc:' . $k;
         $dc_xml .= ' xml:lang="' . $PhaidraAPI::Model::Util::iso639map{$n->{lang}} . '"'if (exists($n->{lang}));
         $dc_xml .= '>' . xml_escape($n->{value}) . '</dc:' . $k . ">\n";
      }else{
         next if ($n eq '');
         $dc_xml .= '   <dc:' . $k;
         $dc_xml .= '>' . xml_escape($n) . '</dc:' . $k . ">\n";
      }

    }
  }
  $dc_xml .= "</oai_dc:dc>\n";

  return $dc_xml;
}

1;
__END__
