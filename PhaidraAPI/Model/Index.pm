package PhaidraAPI::Model::Index;

use strict;
use warnings;
use v5.10;
use utf8;
use Mojo::ByteStream qw(b);
use Mojo::Util qw(xml_escape encode decode);
use Mojo::JSON qw(encode_json decode_json);
use Mojo::URL;
use Mojo::UserAgent;
use base qw/Mojo::Base/;
use XML::LibXML;
use Storable qw(dclone);
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Mods;
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Dc;
use PhaidraAPI::Model::Relationships;
use PhaidraAPI::Model::Annotations;

our %cmodel_2_resourcetype = (
  "Asset" => "other",
  "Audio" => "sound",
  "Book" => "book",
  "Collection" => "collection",
  "Container" => "dataset",
  "LaTeXDocument" => "text",
  "PDFDocument" => "text",
  "Page" => "bookpart",
  "Picture" => "image",
  "Resource" => "interactiveresource",
  "Video" => "video"
);

our %uwm_2_mods_roles = (

  # unmapped
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/49" => "initiator",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/51" => "evaluator",  
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/56" => "technicalinspector",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/58" => "textprocessor",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/59" => "pedagogicexpert",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/61" => "interpreter",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1552154" => "digitiser",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1552155" => "keeperoftheoriginal",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1552167" => "adviser",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557124" => "degreegrantor",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557146" => "uploader",

  # data supplier -> data contributor
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/55" => "dtc",
  # author digital
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/46" => "aut",
  # author analogue
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1552095" => "aut",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/47" => "pbl",  
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/52" => "edt",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/53" => "dsr",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/54" => "trl",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/60" => "exp",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/63" => "oth",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/10867" => "art",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/10868" => "dnr",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/10869" => "pht",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1552168" => "jud",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557130" => "prf",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557145" => "wde",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557142" => "rce",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557139" => "sce",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557136" => "ths",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557133" => "sds",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557129" => "lyr",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557126" => "ilu",  
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557121" => "eng",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557116" => "cnd",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557113" => "dto",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557111" => "opn",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557109" => "cmp",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557107" => "ctg",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557104" => "dub",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557103" => "wam",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557100" => "arc",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557144" => "vdg",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557140" => "scl",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557138" => "aus",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557134" => "own",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557131" => "fmo",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557127" => "mus",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557122" => "ive",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557119" => "ill",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557117" => "cng",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557114" => "dte",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557110" => "sad",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557105" => "mte",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557101" => "arr",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557098" => "etr",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557143" => "dis",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557141" => "prt",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557137" => "flm",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557135" => "rev",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557132" => "pro",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557128" => "att",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557125" => "lbt",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557123" => "ivr",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557120" => "egr",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557118" => "msd",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557115" => "ard",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557112" => "chr",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557108" => "com",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557106" => "sng",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557102" => "act",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557099" => "adp"  

);

sub update {
  my ($self, $c, $pid, $dc_model, $search_model, $rel_model, $object_model) = @_;

  my $res = { status => 200 };    

  if( exists($c->app->config->{index_mongodb}) || exists($c->app->config->{solr})){

    my $r = $self->_get($c, $pid, $dc_model, $search_model, $rel_model, $object_model);
    $res = $r;

    if($r->{status} eq 200){
      if(exists($c->app->config->{index_mongodb})){

        $c->index_mongo->db->collection($c->app->config->{index_mongodb}->{collection})->update({pid => $pid}, $r->{index}, { upsert => 1 });
        $c->app->log->debug("[$pid] mongo index updated");          
      }

      if(exists($c->app->config->{solr})){

        my $url = Mojo::URL->new;
        $url->scheme($c->app->config->{solr}->{scheme});
        $url->userinfo($c->app->config->{solr}->{username}.":".$c->app->config->{solr}->{password});
        $url->host($c->app->config->{solr}->{host});
        $url->port($c->app->config->{solr}->{port});
        $url->path("/solr/".$c->app->config->{solr}->{core}."/update/json/docs");
        $url->query({commit => 'true'});

        my $ua = Mojo::UserAgent->new;
        my $post = $ua->post($url => json => $r->{index});

        if (my $r = $post->success) {
          $c->app->log->debug("[$pid] solr updated");
        }else {
          my ($err, $code) = $post->error;
          unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
          $res->{status} =  $code ? $code : 500;
        }
        
      }
    }

  }

  return $res;
}

sub get {
  my ($self, $c, $pid) = @_;

  my $dc_model = PhaidraAPI::Model::Dc->new;
  my $search_model = PhaidraAPI::Model::Search->new;
  my $rel_model = PhaidraAPI::Model::Relationships->new;
  my $object_model = PhaidraAPI::Model::Object->new;

  return $self->_get($c, $pid, $dc_model, $search_model, $rel_model, $object_model);
}

sub _get {
  my ($self, $c, $pid, $dc_model, $search_model, $rel_model, $object_model) = @_;

  my $res = { status => 200 };        

  my %index;

  # check if it's active
  my $r_state = $search_model->get_state($c, $pid);
  if($r_state->{status} ne 200){
    return $r_state;
  }
  unless($r_state->{state} eq 'Active'){
    $c->app->log->warn("[_get index] Object $pid is ".$r_state->{state}.", skipping");
    push @{$res->{alerts}}, { type => 'danger', msg => "[_get index] Object $pid is ".$r_state->{state}.", skipping" };
    return $res;
  }

  my $r_ds = $search_model->datastreams_hash($c, $pid);
  if($r_ds->{status} ne 200){
    return $r_ds;
  }

  # get GEO and turn to solr geospatial types
  if($r_ds->{dshash}->{'GEO'}){
    my $geo_model = PhaidraAPI::Model::Geo->new;
    my $r_geo = $geo_model->get_object_geo_json($c, $pid, $c->stash->{basic_auth_credentials}->{username}, $c->stash->{basic_auth_credentials}->{password});
    if($r_geo->{status} ne 200){      
      push @{$res->{alerts}}, { type => 'danger', msg => "Error adding GEO fields from $pid" };
      for $a (@{$r_geo->{alerts}}){
        push @{$res->{alerts}}, $a;
      }
    }else{
      for my $plm (@{$r_geo->{geo}->{kml}->{document}->{placemark}}){
        # bbox -> WKT/CQL ENVELOPE syntax. Example: ENVELOPE(-175.360000, -173.906827, -18.568055, -21.268064) which is minX, maxX, maxY, minY order
        if(exists($plm->{polygon})){
          my $coords = $plm->{polygon}->{outerboundaryis}->{linearring}->{coordinates};
          # we have to sort them minX, maxX, maxY, minY
          my $minLat = 90;
          my $maxLat = -90;
          my $minLon = 180;
          my $maxLon = -180;
          for my $ll (@$coords){            
            $maxLon = $ll->{longitude} if $ll->{longitude} >= $maxLon;
            $minLon = $ll->{longitude} if $ll->{longitude} <= $minLon;
            $maxLat = $ll->{latitude} if $ll->{latitude} >= $maxLat;
            $minLat = $ll->{latitude} if $ll->{latitude} <= $minLat;
          }          

          push @{$index{bbox}}, "ENVELOPE($minLon, $maxLon, $maxLat, $minLat)";

          # add some latlon
          push @{$index{latlon}}, (($minLat + $maxLat)/2).','.(($minLon + $maxLon)/2);
        }
        
        # latlon -> latitude,longitude
        if(exists($plm->{point})){
          push @{$index{latlon}}, $plm->{point}->{coordinates}->{latitude}.",".$plm->{point}->{coordinates}->{longitude};
        }
      }      
    }
  }

  # get ANNOTATIONS 
  if($r_ds->{dshash}->{'ANNOTATIONS'}){
    my $ann_model = PhaidraAPI::Model::Annotations->new;
    my $r_ann = $ann_model->get_object_annotations_json($c, $pid, $c->stash->{basic_auth_credentials}->{username}, $c->stash->{basic_auth_credentials}->{password});
    if($r_ann->{status} ne 200){      
      push @{$res->{alerts}}, { type => 'danger', msg => "Error adding ANNOTATIONS from $pid" };
      for $a (@{$r_ann->{alerts}}){
        push @{$res->{alerts}}, $a;
      }
    }else{
      for my $id (keys %{$r_ann->{annotations}}){
        
          my $title = $r_ann->{annotations}->{$id}->{title} if exists $r_ann->{annotations}->{$id}->{title};
          my $text = $r_ann->{annotations}->{$id}->{text} if exists $r_ann->{annotations}->{$id}->{text};
          my $ann = ""; 
          $ann .= $title . ": " if defined $title;
          $ann .= $text;
          push @{$index{annotations}}, $ann;

      }      
    }
  }

  # triples
  my $r_add_triples = $self->_add_triples_index($c, $pid, $search_model, \%index);
  if($r_add_triples->{status} ne 200){
    push @{$res->{alerts}}, { type => 'danger', msg => "Error getting triples for $pid" };
    for $a (@{$r_add_triples->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }

  my $cmodel = $index{cmodel};

  # uwmetadata
  if($r_ds->{dshash}->{'UWMETADATA'}){
    my $r_uw = $object_model->get_datastream($c, $pid, 'UWMETADATA', $c->stash->{basic_auth_credentials}->{username}, $c->stash->{basic_auth_credentials}->{password}, 1);
    if($r_uw->{status} ne 200){
      push @{$res->{alerts}}, { type => 'danger', msg => "Error adding UWMETADATA fields for $pid" };
      for $a (@{$r_uw->{alerts}}){
        push @{$res->{alerts}}, $a;
      }
    }else{
      my $uwmetadataxml = $r_uw->{UWMETADATA};
      my $r_add_uwm = $self->_add_uwm_index($c, $pid, $uwmetadataxml, \%index);
      if($r_add_uwm->{status} ne 200){
        push @{$res->{alerts}}, { type => 'danger', msg => "Error adding UWMETADATA fields for $pid" };
        for $a (@{$r_add_uwm->{alerts}}){
          push @{$res->{alerts}}, $a;
        }
      }
        
      my $uw_model = PhaidraAPI::Model::Uwmetadata->new;
      my $r0 = $uw_model->metadata_tree($c);
      if($r0->{status} ne 200){
        push @{$res->{alerts}}, { type => 'danger', msg => "Error getting UWMETADATA tree for $pid" };
        for $a (@{$r_add_uwm->{alerts}}){
          push @{$res->{alerts}}, $a;
        }
      }else{
        my ($dc_p, $dc_oai) = $dc_model->map_uwmetadata_2_dc_hash($c, $pid, $cmodel, $uwmetadataxml, $r0->{metadata_tree}, $uw_model);
        $self->_add_dc_index($c, $dc_p, \%index);
      }
    }
  }

  # mods
  if($r_ds->{dshash}->{'MODS'}){
    my $r_mods = $object_model->get_datastream($c, $pid, 'MODS', $c->stash->{basic_auth_credentials}->{username}, $c->stash->{basic_auth_credentials}->{password}, 1);
    if($r_mods->{status} ne 200){
      push @{$res->{alerts}}, { type => 'danger', msg => "Error adding MODS fields for $pid" };
      for $a (@{$r_mods->{alerts}}){
        push @{$res->{alerts}}, $a;
      }
    }else{
      my $modsxml = $r_mods->{MODS};
      my $r_add_mods = $self->_add_mods_index($c, $pid, $modsxml, \%index);
      if($r_add_mods->{status} ne 200){
        push @{$res->{alerts}}, { type => 'danger', msg => "Error adding MODS fields for $pid" };
        for $a (@{$r_add_mods->{alerts}}){
          push @{$res->{alerts}}, $a;
        }
      }else{
        my $mods_model = PhaidraAPI::Model::Mods->new;
        my ($dc_p, $dc_oai) = $dc_model->map_mods_2_dc_hash($c, $pid, $cmodel, $modsxml, $mods_model);
        $self->_add_dc_index($c, $dc_p, \%index);
      }
    }
  }

  # relationships
  my $r_rel = $rel_model->get($c, $pid, $search_model);
  if($r_rel->{status} ne 200){
    push @{$res->{alerts}}, { type => 'danger', msg => "Error getting relationships for $pid" };
    for $a (@{$r_rel->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }else{
    while (my ($k, $v) = each %{$r_rel->{relationships}}) {
      # don't index haspart, too much data, for search we only need ispartof anyways
      unless($k eq 'haspart'){
        if($k eq 'altformats'){
          for my $kf (keys %{$r_rel->{relationships}->{altformats}}){
            push @{$index{altformats}}, $kf;
          }
        }elsif($k eq 'altversions'){
          for my $kv (keys %{$r_rel->{relationships}->{altversions}}){
            push @{$index{altversions}}, $kv;
          }
        }else{
          $index{$k} = $v;
        }
      }
    }
  }
    
  # list of datastreams
  my @dskeys = keys %{$r_ds->{dshash}};
  $index{datastreams} = \@dskeys;

  # inventory
  my $inv_coll = $c->paf_mongo->db->collection('foxml.ds');
  if($inv_coll){
    my $ds_doc = $inv_coll->find({pid => $pid})->sort({ "updated_at" => -1})->next;
    $index{size} = $ds_doc->{fs_size};
  }

  # pid
  $index{pid} = $pid;    

  my $resourcetype;
  $resourcetype = $cmodel_2_resourcetype{$index{cmodel}};    
  if($index{"bib_ir"} eq "yes"){
    $resourcetype = "journalarticle";
  }  
  if(exists($index{"dc_subject"})){
    for my $s (@{$index{"dc_subject"}}){
      if ($s eq "Altkarte"){
        $resourcetype = "map";
      }
    }  
  }
  $index{resourcetype} = $resourcetype;

  # ts
  $index{_updated} = time;    

  $res->{index} = \%index;
  return $res;
}

sub _add_dc_index {

  my ($self, $c, $dc, $index) = @_;

  while (my ($xmlname, $values) = each %{$dc}) {
    for my $v (@{$values}){
      if(exists($v->{lang})){
        push @{$index->{'dc_'.$xmlname}}, $v->{value};
        push @{$index->{'dc_'.$xmlname."_".$v->{lang}}}, $v->{value};     
        if($xmlname eq 'title'){
          $index->{sort_dc_title} = $v->{value};
          $index->{'sort_' . $v->{lang} . '_dc_title'} = $v->{value};
        }
      }else{
        push @{$index->{'dc_'.$xmlname}}, $v->{value};
        if($xmlname eq 'title'){
          $index->{sort_dc_title} = $v->{value};
        }
      }
    }
  }
     
}

sub _add_triples_index {

  my ($self, $c, $pid, $search_model, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my $r_trip = $search_model->triples($c, "<info:fedora/$pid> * *", 0);
  if($r_trip->{status} ne 200){
    return $r_trip;
  }
   
  for my $triple (@{$r_trip->{result}}){
    my $predicate = @$triple[1];
    my $object = @$triple[2];

    if($predicate eq '<info:fedora/fedora-system:def/model#hasModel>'){      
      if($object =~ m/^<info:fedora\/cmodel:(.*)>$/){
        $index->{cmodel} = $1;        
      }
    }

    if($predicate eq '<info:fedora/fedora-system:def/model#ownerId>'){
      $object =~ m/^"(.*)"$/;
      $index->{owner} = $1;  
    }

    if($predicate eq '<info:fedora/fedora-system:def/view#lastModifiedDate>'){
      $object =~ m/\"([\d\-\:\.TZ]+)\"/;
      $index->{modified} = $1;    
    }

    if($predicate eq '<info:fedora/fedora-system:def/model#createdDate>'){
      $object =~ m/\"([\d\-\:\.TZ]+)\"/;
      $index->{created} = $1;
    }

  }

  return $res;

}

sub _add_mods_index {
  my ($self, $c, $pid, $modsxml, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my $mods_model = PhaidraAPI::Model::Mods->new;  
  my $r_mods = $mods_model->xml_2_json($c, $modsxml, 'basic');
  #my $r_mods = $mods_model->get_object_mods_json($c, $pid, 'basic', $c->stash->{basic_auth_credentials}->{username}, $c->stash->{basic_auth_credentials}->{password});      
  if($r_mods->{status} ne 200){        
    return $r_mods;            
  }

  my @roles;
  for my $n (@{$r_mods->{mods}}){

    if($n->{xmlname} eq 'name'){
      next unless exists $n->{children};
      my $firstname;
      my $lastname;
      my $institution;
      my $role;
      for my $n1 (@{$n->{children}}){        
        if($n1->{xmlname} eq 'namePart'){          
          if(exists($n1->{attributes})){
            for my $a (@{$n1->{attributes}}){
              if($a->{xmlname} eq 'type' && $a->{ui_value} eq 'given'){
                $firstname = $n1->{ui_value} if $n1->{ui_value} ne '';
              }
              if($a->{xmlname} eq 'type' && $a->{ui_value} eq 'family'){
                $lastname = $n1->{ui_value} if $n1->{ui_value} ne '';
              }
              if($a->{xmlname} eq 'type' && $a->{ui_value} eq 'corporate'){
                $institution = $n1->{ui_value} if $n1->{ui_value} ne '';
              }
            }
          }
        }
        if($n1->{xmlname} eq 'role'){
          if(exists($n1->{children})){
            for my $ch (@{$n1->{children}}){
              if($ch->{xmlname} eq 'roleTerm'){
                $role = $ch->{ui_value} if $ch->{ui_value} ne '';
              }
            }
          }
        }        
      }
      my $name = "$firstname $lastname";
      push @{$index->{"bib_roles_pers_$role"}}, $name unless $name eq ' ';
      push @{$index->{"bib_roles_corp_$role"}}, $institution if defined $institution;
    }

    if($n->{xmlname} eq 'originInfo'){
      next unless exists $n->{children};
      for my $n1 (@{$n->{children}}){
        if($n1->{xmlname} eq 'dateIssued'){
          push @{$index->{"bib_published"}}, $n1->{ui_value} if $n1->{ui_value} ne '';
        }
        if($n1->{xmlname} eq 'publisher'){
          push @{$index->{"bib_publisher"}}, $n1->{ui_value} if $n1->{ui_value} ne '';
        }
        if($n1->{xmlname} eq 'place'){
          if(exists($n1->{children})){
            for my $n2 (@{$n1->{children}}){
              if($n2->{xmlname} eq 'placeTerm'){
                push @{$index->{"bib_publisherlocation"}}, $n2->{ui_value} if $n2->{ui_value} ne '';  
              }
            }            
          }          
        }
        if($n1->{xmlname} eq 'edition'){
          push @{$index->{"bib_edition"}}, $n1->{ui_value} if $n1->{ui_value} ne '';
        }
      }
    }
  }

  return $res;
}

sub _add_uwm_index {
  my ($self, $c, $pid, $uwmetadataxml, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my $uwmetadata_model = PhaidraAPI::Model::Uwmetadata->new;  
  my $r_uwm = $uwmetadata_model->uwmetadata_2_json_basic($c, $uwmetadataxml, 'resolved');
  #my $r_uwm = $uwmetadata_model->get_object_metadata($c, $pid, 'resolved', $c->stash->{basic_auth_credentials}->{username}, $c->stash->{basic_auth_credentials}->{password});      
#  $c->app->log->debug("XXXXXXXXXXXXXXX".$c->app->dumper($r_uwm));
  if($r_uwm->{status} ne 200){        
    return $r_uwm;            
  }

  my $uwm = $r_uwm->{uwmetadata};

  # general
  my $general = $self->_find_first_uwm_node_rec($c, "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0", "general", $uwm);
  if($general){
    if($general->{children}){
      for my $gf (@{$general->{children}}){
        if($gf->{xmlname} eq 'irdata'){
          $index->{"bib_ir"} = $gf->{ui_value} if $gf->{ui_value} ne '';  
        }        
      }
    }
  }
  
  # roles
  my ($roles, $contributions) = $self->_get_uwm_roles($c, $uwm);
#  $c->app->log->debug("XXXXXXXXXXXX ".$c->app->dumper($contributions));
  $index->{"uwm_roles_json"} = b(encode_json($contributions))->decode('UTF-8');
  for my $r (@{$roles}){
    push @{$index->{"bib_roles_pers_".$r->{role}}}, $r->{name} if $r->{name} ne '';   
    push @{$index->{"bib_roles_corp_".$r->{role}}}, $r->{institution} if $r->{institution} ne '';   
  }

  # digital book stuff
  my $digbook = $self->_find_first_uwm_node_rec($c, "http://phaidra.univie.ac.at/XML/metadata/digitalbook/V1.0", "digitalbook", $uwm);
  if($digbook){
    if($digbook->{children}){
      for my $dbf (@{$digbook->{children}}){
        if($dbf->{xmlname} eq 'publisher'){
          push @{$index->{"bib_publisher"}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
        if($dbf->{xmlname} eq 'publisherlocation'){
          push @{$index->{"bib_publisherlocation"}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
        if($dbf->{xmlname} eq 'name_magazine'){
          push @{$index->{"bib_journal"}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
        if($dbf->{xmlname} eq 'volume'){
          push @{$index->{"bib_volume"}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
        if($dbf->{xmlname} eq 'edition'){
          push @{$index->{"bib_edition"}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
        if($dbf->{xmlname} eq 'releaseyear'){
          push @{$index->{"bib_published"}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
      }
    }
  }  

  # "GPS"
  #<ns9:gps>13°3&apos;6&apos;&apos;E|47°47&apos;45&apos;&apos;N</ns9:gps>
  #<ns9:gps>23°12&apos;19&apos;&apos;E|35°27&apos;8&apos;&apos;N</ns9:gps>
  my $gps = $self->_find_first_uwm_node_rec($c, "http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0", "gps", $uwm);
  #"ui_value": "13Â°3'6''E|47Â°47'45''N",
  if($gps){
    my $coord = $gps->{ui_value};
    $coord =~ s/Â//g;
    if($coord =~ m/(\d+)°(\d+)'(\d+)''(E|W)\|(\d+)°(\d+)'(\d+)''(N|S)/g){
      my $lon_deg = $1;
      my $lon_min = $2;
      my $lon_sec = $3;
      my $lon_sign = $4;
      my $lat_deg = $5;
      my $lat_min = $6;
      my $lat_sec = $7;
      my $lat_sign = $8;

      my $lon_dec = $lon_deg + ($lon_min/60) + ($lon_sec/3600);
      $lon_dec = -$lon_dec if $lon_sign eq 'S';

      my $lat_dec = $lat_deg + ($lat_min/60) + ($lat_sec/3600);
      $lat_dec = -$lat_dec if $lat_sign eq 'W';
      
      push @{$index->{latlon}}, "$lat_dec,$lon_dec";
    }
  }

  return $res;
}

sub _get_uwm_roles {
  my ($self, $c, $uwm) = @_;

  my $life = $self->_find_first_uwm_node_rec($c, "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0", "lifecycle", $uwm);

  my @roles;
  my @contributions_json;
  for my $ch (@{$life->{children}}){
    if($ch->{xmlname} eq "contribute"){

      my %contribution_json;
      my $contribution_data_order;
      my $role;
      my @names;
      for my $n (@{$ch->{children}}){
        if(($n->{xmlname} eq "role")){
          if(exists($uwm_2_mods_roles{$n->{ui_value}})){
            $role = $uwm_2_mods_roles{$n->{ui_value}};
            $contribution_json{role} = $role;
          }else{
            $c->app->log->error("Failed to map uwm role ".$n->{ui_value}." to a role code.");
          }
        }
      }
      for my $n (@{$ch->{attributes}}){
        if($n->{xmlname} eq 'data_order'){
          # we are going to make the hierarchy flat so multiply the higher level order value
          $contribution_data_order = $n->{ui_value}*100;
          $contribution_json{data_order} = $n->{ui_value};
        }
      }

      if($role){
        for my $l1 (@{$ch->{children}}){

          my %entity;
          my %entity_json;

          next if $l1->{xmlname} eq "role";

          if($l1->{xmlname} eq "entity"){      
            my $firstname;      
            my $lastname;
            my $institution;
            for my $l2 (@{$l1->{children}}){
              next if $l2->{xmlname} eq "type";

              $entity_json{$l2->{xmlname}} = $l2->{ui_value};

              if($l2->{xmlname} eq "firstname"){
                $firstname = $l2->{ui_value} if $l2->{ui_value} ne '';
              }elsif($l2->{xmlname} eq "lastname"){
                $lastname = $l2->{ui_value} if $l2->{ui_value} ne '';
              }elsif($l2->{xmlname} eq "institution"){
                $institution = $l2->{ui_value} if $l2->{ui_value} ne '';
              }else{
                $entity{$l2->{xmlname}} = $l2->{ui_value} if $l2->{ui_value} ne '';
              }
            }
            my $name = "$firstname $lastname";
            $entity{name} = $name unless $name eq ' ';
            $entity{institution} = $institution if defined($institution);
            $entity{role} = $role;
          }

          for my $n (@{$l1->{attributes}}){
            if($n->{xmlname} eq 'data_order'){
              $entity{data_order} = $n->{ui_value} + $contribution_data_order;
              $entity_json{data_order} = $n->{ui_value};
            }
          }

          push @{$contribution_json{entities}}, \%entity_json;        

          push @roles, \%entity if defined $role;
        }
      }

      push @contributions_json, \%contribution_json;
    }    
  }

  return \@roles, \@contributions_json;
}

sub _find_first_uwm_node_rec {
  my ($self, $c, $xmlns, $xmlname, $uwm) = @_;

  my $ret;
  for my $n (@{$uwm}){
    if(($n->{xmlname} eq $xmlname) && ($n->{xmlns} eq $xmlns)){
      $ret = $n;
      last;
    }else{
      my $ch_size = defined($n->{children}) ? scalar (@{$n->{children}}) : 0;
      if($ch_size > 0){
        $ret = $self->_find_first_uwm_node_rec($c, $xmlns, $xmlname, $n->{children});
        last if $ret;
      }
    }
  }

  return $ret;
}

1;
__END__
