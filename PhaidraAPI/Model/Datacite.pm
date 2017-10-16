package PhaidraAPI::Model::Datacite;

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
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Uwmetadata::Extraction;
use PhaidraAPI::Model::Mods::Extraction;
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Languages;

our $datacite_ns = "http://datacite.org/schema/kernel-4";

our %cmodelMapping =
(
  'Picture'       => 'Image',
  'Audio'         => 'Sound',
  'Collection'    => 'Collection',
  'Container'     => 'Dataset',
  'Video'         => 'Audiovisual',
  'PDFDocument'   => 'Text',
  'LaTeXDocument' => 'Text',
  'Resource'      => 'InteractiveResource',
  'Asset'         => 'Other',
  'Book'          => 'Other',
  'Page'          => 'Other',
  'Paper'         => 'Text'
);

sub get {

  my ($self, $c, $pid, $username, $password) = @_;

  my $res = { alerts => [], status => 200 };

  my $search_model = PhaidraAPI::Model::Search->new;
  my $object_model = PhaidraAPI::Model::Object->new;
  
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

  my $r = $search_model->datastreams_hash($c, $pid);
  if($r->{status} ne 200){
    return $r;
  }

  if($r->{dshash}->{'MODS'}){ 

    my $r1 = $object_model->get_datastream($c, $pid, 'MODS', $username, $password, 1);
    if($r1->{status} ne 200){
      return $r1;
    }

    my $datacite = $self->map_mods_2_datacite($c, $pid, $cmodel, $r1->{MODS});

    $res->{datacite} = $datacite;
  }

  if($r->{dshash}->{'UWMETADATA'}){ 

    my $r1 = $object_model->get_datastream($c, $pid, 'UWMETADATA', $username, $password, 1);
    if($r1->{status} ne 200){
      return $r1;
    }

    my $datacite = $self->map_uwmetadata_2_datacite($c, $pid, $cmodel, $r1->{UWMETADATA});

    $res->{datacite} = $datacite;
  }

  return $res;

}


sub map_uwmetadata_2_datacite {

  my ($self, $c, $pid, $cmodel, $xml) = @_;

  my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;

  my $r0 = $metadata_model->metadata_tree($c);
  if($r0->{status} ne 200){
      return $r0;
  }
  my $tree = $r0->{metadata_tree};

  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($xml);

  my $ext = PhaidraAPI::Model::Uwmetadata::Extraction->new;

  my %doc_uwns = {};

  # FIXME GEO datastream to DCMI BOX

  # fill $doc_ns, namespace mapping for this document
  my $nss = $dom->find('uwmetadata')->first->attr;
  for my $nsa_key (keys %{$nss}){
    $nsa_key =~ /(\w+):(\w+)/;
    $doc_uwns{$PhaidraAPI::Model::Uwmetadata::Extraction::uwns{$nss->{$nsa_key}}} = $2;
  }

  my %data;
  my $relids = $self->_get_relsext_identifiers($c, $pid);
  my $relids2 = $ext->_get_uwm_identifiers($c, $dom, \%doc_uwns, $tree, $metadata_model);
  for my $ri (@{$relids2}){
    push $relids, $ri;
  }
  for my $relid (@$relids){
    if($relid->{value} =~ /hdl/i){
      $relid->{type} = 'Handle';
      push @{$data{identifiers}}, $relid;
    }elsif($relid->{value} =~ /doi/i){
      $relid->{type} = 'DOI';
      $relid->{value} =~ s/^doi://;
      push @{$data{identifiers}}, $relid;
    }elsif($relid->{value} =~ /urn/i){
      $relid->{type} = 'URN';
      push @{$data{identifiers}}, $relid;
    }elsif($relid->{value} =~ /issn/i){
      $relid->{type} = 'ISSN';
      push @{$data{identifiers}}, $relid;
    }elsif($relid->{value} =~ /isbn/i){
      $relid->{type} = 'ISBN';
      push @{$data{identifiers}}, $relid;
    }elsif($relid->{value} =~ /eissn/i){
      $relid->{type} = 'EISSN';
      push @{$data{identifiers}}, $relid;
    }
  }
  push @{$data{identifiers}}, { value => "http://".$c->app->config->{phaidra}->{baseurl}."/".$pid, type => "URL" };
  $data{titles} = $ext->_get_titles($c, $dom, \%doc_uwns);
  $data{descriptions} = $ext->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:description');
  $data{creators} = $ext->_get_creators($c, $dom, \%doc_uwns);
  $data{pubyears} = $ext->_get_uwm_element_values($c, $dom, $doc_uwns{'digitalbook'}.'\:releaseyear');
  $data{uploaddates} = $ext->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:upload_date');
  $data{embargodates} = $ext->_get_uwm_element_values($c, $dom, $doc_uwns{'extended'}.'\:infoeurepoembargo');
  $data{formats} = $ext->_get_formats($c, $pid, $cmodel, $dom, \%doc_uwns);
  $data{filesizes} = $self->_get_dsinfo_filesize($c, $pid, $cmodel);
  $data{publishers} = $ext->_get_publishers($c, $dom, \%doc_uwns);
  $data{contributors} = $ext->_get_contributors($c, $dom, \%doc_uwns);
  $data{licenses} = $ext->_get_licenses($c, $dom, \%doc_uwns, $tree, $metadata_model);
  my $keywords = $ext->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:keyword');
  my $classifications = $ext->_get_uwm_classifications($c, $dom, \%doc_uwns);
  for my $k (@{$keywords}){
    push @{$data{subjects}}, $k;
  }
  for my $c (@{$classifications}){
    push @{$data{subjects}}, $c;
  }
  my $languages = $ext->_get_uwm_element_values($c, $dom, $doc_uwns{'lom'}.'\:language');
  for my $l (@{$languages}){
    unless($l->{value} eq 'xx'){
      push @{$data{langs}}, { value => $l->{value} };
    }
  }

  return $self->data_2_datacite($c, $cmodel, \%data);

}


sub map_mods_2_datacite {

  my ($self, $c, $pid, $cmodel, $xml) = @_;

  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($xml);

  my $ext = PhaidraAPI::Model::Mods::Extraction->new;

  #$c->app->log->debug("XXXXXXXXXXX mods xml:".$xml);

  # keep using 'mods' as the first node in selectors to avoid running into relatedItem
  my %data;
  $data{titles} = $ext->_get_mods_titles($c, $dom);
  $data{subjects} = $ext->_get_mods_subjects($c, $dom);
  my $classifications = $ext->_get_mods_classifications($c, $dom);
  push @{$data{subjects}}, @$classifications;
  my $relids = $self->_get_relsext_identifiers($c, $pid);
  my $relids2 = $ext->_get_mods_element_values($c, $dom, 'mods > identifier');
  for my $ri (@{$relids2}){
    push $relids, $ri;
  }
  for my $relid (@$relids){
    my $rrr = $relid->{value} =~ /doi/i;
    if($relid->{value} =~ /hdl/i){
      $relid->{type} = 'Handle';
      push @{$data{identifiers}}, $relid;
    }elsif($relid->{value} =~ /doi/i){
      $relid->{type} = 'DOI';
      $relid->{value} =~ s/^doi://;
      push @{$data{identifiers}}, $relid;
    }elsif($relid->{value} =~ /urn/i){
      $relid->{type} = 'URN';
      push @{$data{identifiers}}, $relid;
    }elsif($relid->{value} =~ /issn/i){
      $relid->{type} = 'ISSN';
      push @{$data{identifiers}}, $relid;
    }elsif($relid->{value} =~ /isbn/i){
      $relid->{type} = 'ISBN';
      push @{$data{identifiers}}, $relid;
    }elsif($relid->{value} =~ /eissn/i){
      $relid->{type} = 'EISSN';
      push @{$data{identifiers}}, $relid;
    }
  }
  push @{$data{identifiers}}, { value => "http://".$c->app->config->{phaidra}->{baseurl}."/".$pid, type => "URL" };
  $data{relations} = $ext->_get_mods_relations($c, $dom);
  my $editions = $ext->_get_mods_element_values($c, $dom, 'mods > originInfo > edition');
  push @{$data{relations}}, @$editions;
  $data{languages} = $ext->_get_mods_element_values($c, $dom, 'mods > language > languageTerm');
  $data{creators} = $ext->_get_mods_creators($c, $dom, 'p');
  $data{contributors} = $ext->_get_mods_contributors($c, $dom, 'p');
  $data{dates} = $ext->_get_mods_element_values($c, $dom, 'mods > originInfo > dateIssued[keyDate="yes"]');
  $data{descriptions} = $ext->_get_mods_element_values($c, $dom, 'mods > note');
  $data{publishers} = $ext->_get_mods_element_values($c, $dom, 'mods > originInfo > publisher');
  $data{rights} = $ext->_get_mods_element_values($c, $dom, 'mods > accessCondition[type="use and reproduction"]');
  $data{filesizes} = $self->_get_dsinfo_filesize($c, $pid, $cmodel);

  return $self->data_2_datacite($c, $cmodel, \%data);
}

sub data_2_datacite {

  my ($self, $c, $cmodel, $data) = @_;

  my @datacite;

=begin comment

... does not apply, we need a DataCite DOI, no just any DOI

  if(exists($data->{identifiers})){
    #<identifier identifierType="DOI">10.5072/example-full</identifier>
    for my $i (@{$data->{identifiers}}){
      if($i->{type} eq "DOI"){
        push @datacite, {
          xmlname => "identifier",
          value => $i->{value},
          attributes => [
            {
              xmlname => "identifierType",
              value => $i->{type}
            }
          ]
        };
      }
    }

=end comment
=cut

=begin comment

DataCite is unhappy about this (or the ordering)

    #
    #<alternateIdentifiers>
    #  <alternateIdentifier alternateIdentifierType="URL">
    #    http://schema.datacite.org/schema/meta/kernel-3.1/example/datacite-example-full-v3.1.xml
    #  </alternateIdentifier>
    #</alternateIdentifiers>
    for my $i (@{$data->{identifiers}}){
      my @alt_identifiers_children;
      if($i->{type} ne "DOI"){
        push @alt_identifiers_children, {
          xmlname => "alternateIdentifier",
          value => $i->{value},
          attributes => [
            {
              xmlname => "alternateIdentifierType",
              value => $i->{type}
            }
          ]
        };
      }
      if(scalar @alt_identifiers_children > 0){
        push @datacite, {
          xmlname => "alternateIdentifiers",
          children => \@alt_identifiers_children
        };
      }
    }
  }

=end comment
=cut

  if(exists($data->{creators})){
    #
    #<creators>
    # <creator>
    #  <creatorName>Miller, Elizabeth</creatorName>
    #  <givenName>Elizabeth</givenName>
    #  <familyName>Miller</familyName>
    #  <nameIdentifier schemeURI="http://orcid.org/" nameIdentifierScheme="ORCID">0000-0001-5000-0007</nameIdentifier>
    #  <affiliation>DataCite</affiliation>
    # </creator>
    #</creators>
    my @creators_children;
    for my $cr (@{$data->{creators}}){
      my $ch = {
        xmlname => "creator",
        children => []
      };
      push @{$ch->{children}}, { xmlname => "creatorName", value => $cr->{value} };
      if($cr->{firstname}){
        push @{$ch->{children}}, { xmlname => "givenName", value => $cr->{firstname} };
      }
      if($cr->{lastname}){
        push @{$ch->{children}}, { xmlname => "familyName", value => $cr->{lastname} };
      }
      push @creators_children, $ch;
    }
    push @datacite, {
      xmlname => "creators",
      children => \@creators_children
    };
    
  }

  if(exists($data->{contributors})){
    #<contributors>
    #  <contributor contributorType="ProjectLeader">
    #    <contributorName>Starr, Joan</contributorName>
    #    <nameIdentifier schemeURI="http://orcid.org/" nameIdentifierScheme="ORCID">0000-0002-7285-027X</nameIdentifier>
    #    <affiliation>California Digital Library</affiliation>
    #  </contributor>
    #</contributors>
    my @contributors_children;
    for my $cr (@{$data->{contributors}}){
      my $ch = {
        xmlname => "contributor",
        children => []
      };
      push @{$ch->{children}}, { xmlname => "contributorName", value => $cr->{value} };
      if($cr->{firstname}){
        push @{$ch->{children}}, { xmlname => "givenName", value => $cr->{firstname} };
      }
      if($cr->{lastname}){
        push @{$ch->{children}}, { xmlname => "familyName", value => $cr->{lastname} };
      }
      push @contributors_children, $ch;
    }
    push @datacite, {
      xmlname => "contributors",
      children => \@contributors_children
    };
  }

  if(exists($data->{titles})){
    #<titles>
    #  <title xml:lang="en-us">Full DataCite XML Example</title>
    #  <title xml:lang="en-us" titleType="Subtitle">Demonstration of DataCite Properties.</title>
    #</titles>
    my @titles_children;
    for my $t (@{$data->{titles}}){
      push @titles_children, {
        xmlname => "title",
        value => $t->{title},

        # ATTN: register_doi POST metadata returned code1=[400] res1=[[xml] xml error: cvc-complex-type.3.2.2: Attribute 'lang' is not allowed to appear in element 'title'.]
        # attributes => [
        #   {
        #     xmlname => "lang",
        #     value => $t->{lang} 
        #   }
        # ]

      };
      if(defined($t->{subtitle})){
        push @titles_children, {
          xmlname => "title",
          value => $t->{subtitle},
          attributes => [
            {
              xmlname => "titleType",
              value => "Subtitle"
            },
            {
              xmlname => "lang",
              value => $t->{lang} 
            }
          ]
        };
      }
    }
    push @datacite, {
      xmlname => "titles",
      children => \@titles_children
    };
  }

  if(exists($data->{publishers})){
    #<publisher>DataCite</publisher>
    for my $p (@{$data->{publishers}}){
      if ($p->{value})
      {
        push @datacite, {
          xmlname => "publisher",
          value => $p->{value}
        };
      }
    }
  }
  else
  {
    # TODO/DEFAULTS
    push (@datacite, { xmlname => "publisher", value => "UniWien" });
  }

  # NOTE: the code below seems to allow multiple publicationYear, check if this is valid
  if(exists($data->{embargodates}) || exists($data->{pubyears})){
    #<publicationYear>2014</publicationYear>
    # Year when the data is made publicly available. If an embargo period has been in effect, use the date when the embargo period ends.
    if(defined($data->{embargodates})){
      for my $em (@{$data->{embargodates}}){
        push @datacite, {
          xmlname => "publicationYear",
          value => $em->{value}
        };	
      }
    }else{  
      for my $py (@{$data->{pubyears}}){
        push @datacite, {
          xmlname => "publicationYear",
          value => $py->{value}
        };
      }
    }
  }

  if(exists($data->{descriptions})){
    #
    #<descriptions>
    # <description xml:lang="en-us" descriptionType="Abstract">
    #   XML example of all DataCite Metadata Schema v4.0 properties.
    # </description>
    #</descriptions>
    my @descriptions_children;
    for my $de (@{$data->{descriptions}}){
      my $ch = {
        xmlname => "description",
        value => $de->{value}, 

         attributes => [
         {
           # cvc-complex-type.4: Attribute 'descriptionType' must appear on element 'description'.
	   # https://schema.test.datacite.org/meta/kernel-4.1/include/datacite-descriptionType-v4.xsd
	   # values: Abstract Methods SeriesInformation TableOfContents TechnicalInfo Other

           xmlname => "descriptionType",
           value => "Other" # we don't have description type; TODO: add heuristics to select one of the allowed values
         },
# ATTN: register_doi POST metadata returned code1=[400] res1=[[xml] xml error: cvc-complex-type.3.2.2: Attribute 'lang' is not allowed to appear in element 'description'.]
#          {
#            xmlname => "lang",
#            value => $de->{lang} 
#          }
        ]
      };
      push @descriptions_children, $ch;
    }
    push @datacite, {
      xmlname => "descriptions",
      children => \@descriptions_children
    };
  }

  # <resourceType resourceTypeGeneral="Software">XML</resourceType>
  push @datacite, {
    xmlname => "resourceType",
    value => $cmodel,
    attributes => [
      {
        xmlname => "resourceTypeGeneral",
        value => $cmodelMapping{$cmodel}
      }
    ]
  };

  if(exists($data->{langs})){
    #<language>en-us</language>
    for my $l (@{$data->{langs}}){
      push @datacite, {
        xmlname => "language",
        value => $l->{value}
      };
    }
  }

  if(exists($data->{uploaddates})){
    #<dates>
    #  <date dateType="Updated">2014-10-17</date>
    #</dates>
    my @dates_children;
    for my $d (@{$data->{uploaddates}}){
      my $ch = {
        xmlname => "date" ,
        value => $d->{value},
        attributes => [
          {
            xmlname => "dateType",
            value => "Created"
          }
        ]
      };
      push @dates_children, $ch;
    }
    push @datacite, {
      xmlname => "dates",
      children => \@dates_children
    };
  }
  
  if(exists($data->{subjects})){
    #<subjects>
    # <subject xml:lang="en-us" schemeURI="http://dewey.info/" subjectScheme="dewey">000 computer science</subject>
    #</subjects>
    # the scheme and URI are optional
    my @subject_children;
    for my $s (@{$data->{subjects}}){
      my $ch = {
        xmlname => "subject",
        value => $s->{value},
# ATTN: register_doi POST metadata returned code1=[400] res1=[[xml] xml error: cvc-complex-type.3.2.2: Attribute 'lang' is not allowed to appear in element 'subject'.]
#        attributes => [
#          {
#            xmlname => "lang",
#            value => $s->{lang}
#          }
#        ]
      };
      push @subject_children, $ch;
    }
    push @datacite, {
      xmlname => "subjects",
      children => \@subject_children
    };
  }
  
  if(exists($data->{filesizes})){
    #<sizes>
    #  <size>3KB</size>
    #</sizes>
    for my $fs (@{$data->{filesizes}}){
      push @datacite, {
        xmlname => "sizes",
        children => [
          {
            xmlname => "size",
            value => $fs->{value}.' b'
          }
        ]
      }
    }
  }

  if(exists($data->{filesizes})){
    #<formats>
    #  <format>application/xml</format>
    #</formats>
    for my $f (@{$data->{filesizes}}){
      push @datacite, {
        xmlname => "formats",
        children => [
          {
            xmlname => "format",
            value => $f->{value}
          }
        ]
      }
    }
  }

  if(($cmodel ne 'Resource') && ($cmodel ne 'Collection')){
    #<rightsList>
    # <rights rightsURI="http://creativecommons.org/publicdomain/zero/1.0/">CC0 1.0 Universal</rights>
    #</rightsList>
    # rightsURI is optional
    if(exists($data->{licenses})){
      for my $v (@{$data->{licenses}}){ 
        push @datacite, {
          xmlname => "rightsList",
          children => [
            {
              xmlname => "rights",
              value => $v->{value}
            }
          ]
        }
      }
    }
  }

  return \@datacite;
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

sub _get_dsinfo_filesize {

  my ($self, $c, $pid, $cmodel) = @_;
  
  my $search_model = PhaidraAPI::Model::Search->new;
  my $xml = $search_model->_get_dsinfo_xml($c, $pid, $cmodel);

  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($xml);

  my $bytesize;
  for my $e ($dom->find('dsinfo > filesize')->each){
     $bytesize = $e->text;
  }
  my @sizes;
  push @sizes, { value => $bytesize };
  return \@sizes;
}

sub json_2_xml {

    my ($self, $c, $json) = @_;

    my $prefixmap = {
      $datacite_ns => 'datacite'
    };
    my $forced_declarations = [
      $datacite_ns
    ];

    my $xml = '';
    my $writer = XML::Writer->new(
      OUTPUT => \$xml,
      NAMESPACES => 1,
      PREFIX_MAP => $prefixmap,
      FORCED_NS_DECLS => $forced_declarations,
      DATA_MODE => 1,
      ENCODING => 'utf-8' # NOTE: apparently, this leads to double UTF-8 encoding
    );

    $writer->startTag("resource");
    $self->json_2_xml_rec($c, undef, $json, $writer);
    $writer->endTag("resource");

    $writer->end();

    return $xml;
}

sub json_2_xml_rec(){

  my $self = shift;
  my $c = shift;
  my $parent = shift;
  my $children = shift;
  my $writer = shift;

  foreach my $child (@{$children}){

    my $children_size = defined($child->{children}) ? scalar (@{$child->{children}}) : 0;
    my $attributes_size = defined($child->{attributes}) ? scalar (@{$child->{attributes}}) : 0;

    if((!defined($child->{value}) || ($child->{value} eq '')) && $children_size == 0 && $attributes_size == 0){
      next;
    }

    if (defined($child->{attributes}) && (scalar @{$child->{attributes}} > 0)){
      my @attrs;
      foreach my $a (@{$child->{attributes}}){
        if(defined($a->{value}) && $a->{value} ne ''){
          if($a->{xmlname} eq 'lang'){
            push @attrs, ['http://www.w3.org/XML/1998/namespace', 'lang'] => $a->{value};
          }else{
            push @attrs, $a->{xmlname} => $a->{value};
          }
        }
      }
    
      $writer->startTag($child->{xmlname}, @attrs);
    }else{
      $writer->startTag($child->{xmlname});
    }

    if($children_size > 0){
      $self->json_2_xml_rec($c, $child, $child->{children}, $writer);
    }else{
      $writer->characters($child->{value});
    }

    $writer->endTag($child->{xmlname});
  }
}


1;
__END__
