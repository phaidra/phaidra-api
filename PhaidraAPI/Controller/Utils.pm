package PhaidraAPI::Controller::Utils;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::ByteStream qw(b);
use Mojo::JSON qw(decode_json);
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Dc;
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Geo;
use PhaidraAPI::Model::Relationships;

our %uwm_2_mods_roles = (

  # unmapped
  "49" => "initiator",
  "51" => "evaluator",  
  "56" => "technicalinspector",
  "58" => "textprocessor",
  "59" => "pedagogicexpert",
  "61" => "interpreter",
  "1552154" => "digitiser",
  "1552155" => "keeperoftheoriginal",
  "1552167" => "adviser",
  "1557124" => "degreegrantor",
  "1557146" => "uploader",

  # data supplier -> data contributor
  "55" => "dtc",
  # author digital
  "46" => "aut",
  # author analogue
  "1552095" => "aut",
  "47" => "pbl",  
  "52" => "edt",
  "53" => "dsr",
  "54" => "trl",
  "60" => "exp",
  "63" => "oth",
  "10867" => "art",
  "10868" => "dnr",
  "10869" => "pht",
  "1552168" => "jud",
  "1557130" => "prf",
  "1557145" => "wde",
  "1557142" => "rce",
  "1557139" => "sce",
  "1557136" => "ths",
  "1557133" => "sds",
  "1557129" => "lyr",
  "1557126" => "ilu",  
  "1557121" => "eng",
  "1557116" => "cnd",
  "1557113" => "dto",
  "1557111" => "opn",
  "1557109" => "cmp",
  "1557107" => "ctg",
  "1557104" => "dub",
  "1557103" => "wam",
  "1557100" => "arc",
  "1557144" => "vdg",
  "1557140" => "scl",
  "1557138" => "aus",
  "1557134" => "own",
  "1557131" => "fmo",
  "1557127" => "mus",
  "1557122" => "ive",
  "1557119" => "ill",
  "1557117" => "cng",
  "1557114" => "dte",
  "1557110" => "sad",
  "1557105" => "mte",
  "1557101" => "arr",
  "1557098" => "etr",
  "1557143" => "dis",
  "1557141" => "prt",
  "1557137" => "flm",
  "1557135" => "rev",
  "1557132" => "pro",
  "1557128" => "att",
  "1557125" => "lbt",
  "1557123" => "ivr",
  "1557120" => "egr",
  "1557118" => "msd",
  "1557115" => "ard",
  "1557112" => "chr",
  "1557108" => "com",
  "1557106" => "sng",
  "1557102" => "act",
  "1557099" => "adp"  

);


sub get_all_pids {

  my $self = shift;  

  my $search_model = PhaidraAPI::Model::Search->new;
  my $sr = $search_model->triples($self, "* <http://purl.org/dc/elements/1.1/identifier> *");
  if($sr->{status} ne 200){
    return $sr;
  }

  my @pids;
  foreach my $statement (@{$sr->{result}}){

    # get only o:N pids (there are also bdef etc..)
    next unless(@{$statement}[0] =~ m/(o:\d+)/);

    @{$statement}[2] =~ m/^\<info:fedora\/([a-zA-Z\-]+:[0-9]+)\>$/g;
    my $pid = $1;
    $pid =~ m/^[a-zA-Z\-]+:([0-9]+)$/g;
    my $pidnum = $1;
    push @pids, { pid => $pid, pos => $pidnum };
  }

  @pids = sort { $a->{pos} <=> $b->{pos} } @pids;
  my @resarr;
  for my $p (@pids){
    push @resarr, $p->{pid};
  }

  $self->render(json => { pids => \@resarr }, status => 200);

}

sub update_dc {

  my $self = shift;
  my $pid_param = $self->stash('pid');

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  my @pidsarr;
  if(defined($pid_param)){

    push @pidsarr, $pid_param;
  }else{

    my $pids = $self->param('pids');

    unless(defined($pids)){
      $self->render(json => { alerts => [{ type => 'danger', msg => 'No pids sent' }]} , status => 400) ;
      return;
    }

    if(ref $pids eq 'Mojo::Upload'){
      $self->app->log->debug("Pids sent as file param");
      $pids = $pids->asset->slurp;
      $pids = decode_json($pids);
    }else{
      $pids = decode_json(b($pids)->encode('UTF-8'));
    }

    unless(defined($pids->{pids})){
      $self->render(json => { alerts => [{ type => 'danger', msg => 'No pids found' }]} , status => 400) ;
      return;
    }

    @pidsarr = @{$pids->{pids}};
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $dc_model = PhaidraAPI::Model::Dc->new;
  my $search_model = PhaidraAPI::Model::Search->new;
  my @res;
  my $pidscount = scalar @pidsarr;
  my $i = 0;
  for my $pid (@pidsarr){
    $i++;
    $self->app->log->info("Processing $pid [$i/$pidscount]");

    # check if it's active
    my $r = $search_model->get_state($self, $pid);
    if($r->{status} ne 200){
      push @res, { pid => $pid, res => $r };
      next;
    }
    unless($r->{state} eq 'Active'){
      $self->app->log->warn("Object $pid is ".$r->{state}.", skipping");
      next;
    }

    my $r = $search_model->datastreams_hash($self, $pid);
    if($r->{status} ne 200){
      push @res, { pid => $pid, res => $r };
      next;
    }

    if($r->{dshash}->{'UWMETADATA'}){
      my $res = $object_model->get_datastream($self, $pid, 'UWMETADATA', $username, $password);
      if($res->{status} ne 200){
        push @res, { pid => $pid, res => $res };
        next;
      }  
      $res->{UWMETADATA} = b($res->{UWMETADATA})->decode('UTF-8');
      my $gr = $dc_model->generate_dc_from_uwmetadata($self, $pid, $res->{UWMETADATA}, $username, $password);
      if($gr->{status} ne 200){
        push @res, { pid => $pid, res => $gr };
        next;
      }  
    }
    if($r->{dshash}->{'MODS'}){
      my $res = $object_model->get_datastream($self, $pid, 'MODS', $username, $password);
      if($res->{status} ne 200){
        push @res, { pid => $pid, res => $res };
        next;
      }  
      $res->{MODS} = b($res->{MODS})->decode('UTF-8');
      my $gr = $dc_model->generate_dc_from_mods($self, $pid, $res->{MODS}, $username, $password);
      if($gr->{status} ne 200){
        push @res, { pid => $pid, res => $gr };
        next;
      }  
    }

    push @res, { pid => $pid, res => 'OK'};
  }
  
  $self->render(json => { results => \@res }, status => 200);
}

sub update_index {

  my $self = shift;
  my $pid_param = $self->stash('pid');

  unless(exists($self->app->config->{index_mongodb})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'The index database is not configured' }]} , status => 400) ;
    return;
  }

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  my @pidsarr;
  if(defined($pid_param)){

    push @pidsarr, $pid_param;
  }else{

    my $pids = $self->param('pids');

    unless(defined($pids)){
      $self->render(json => { alerts => [{ type => 'danger', msg => 'No pids sent' }]} , status => 400) ;
      return;
    }

    if(ref $pids eq 'Mojo::Upload'){
      $self->app->log->debug("Pids sent as file param");
      $pids = $pids->asset->slurp;
      $pids = decode_json($pids);
    }else{
      $pids = decode_json(b($pids)->encode('UTF-8'));
    }

    unless(defined($pids->{pids})){
      $self->render(json => { alerts => [{ type => 'danger', msg => 'No pids found' }]} , status => 400) ;
      return;
    }

    @pidsarr = @{$pids->{pids}};
  }

  #my $object_model = PhaidraAPI::Model::Object->new;
  my $dc_model = PhaidraAPI::Model::Dc->new;
  my $search_model = PhaidraAPI::Model::Search->new;
  my $rel_model = PhaidraAPI::Model::Relationships->new;
  my @res;
  my $pidscount = scalar @pidsarr;
  my $i = 0;
  for my $pid (@pidsarr){

    $i++;
    $self->app->log->info("Processing $pid [$i/$pidscount]");

    my $r = $self->_get_index($pid, $dc_model, $search_model, $rel_model);    
    if($r->{status} eq 200){
      # save
      $self->index_mongo->db->collection($self->app->config->{index_mongodb}->{collection})->update({pid => $pid}, $r->{index}, { upsert => 1 });         
      push @res, { pid => $pid, status => 200 };
    }else{
      $r->{pid} = $pid;
      push @res, $r;
    }
    
  }
  
  $self->render(json => { results => \@res }, status => 200);
}

sub get_index {
  my ($self) = @_;

  my $pid = $self->stash('pid');
  my $dc_model = PhaidraAPI::Model::Dc->new;
  my $search_model = PhaidraAPI::Model::Search->new;
  my $rel_model = PhaidraAPI::Model::Relationships->new;

  my $r = $self->_get_index($pid, $dc_model, $search_model, $rel_model);

  $self->render(json => $r, status => $r->{status});
}

sub _get_index {
  my ($self, $pid, $dc_model, $search_model, $rel_model) = @_;

  my $res = { status => 200 };        

  my %index;

  # check if it's active
  my $r_state = $search_model->get_state($self, $pid);
  if($r_state->{status} ne 200){
    return $r_state;
  }
  unless($r_state->{state} eq 'Active'){
    $self->app->log->warn("Object $pid is ".$r_state->{state}.", skipping");
    $res->{alerts} = [{ type => 'danger', msg => "Object $pid is ".$r_state->{state}.", skipping" }];
    return $res;
  }

  my $r_ds = $search_model->datastreams_hash($self, $pid);
  if($r_ds->{status} ne 200){
    return $r_ds;
  }

  # get DC (prefferably DC_P)
  my $dclabel = 'DC';
  if($r_ds->{dshash}->{'DC_P'}){
    $dclabel = 'DC_P';
  }
  my $r_dc = $dc_model->get_object_dc_json($self, $pid, $dclabel, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if($r_dc->{status} ne 200){    
    return $r_dc;        
  }
  # DC fields      
  for my $f (@{$r_dc->{dc}}){      
    if(exists($f->{attributes})){
      for my $a (@{$f->{attributes}}){
        if($a->{xmlname} eq 'xml:lang'){
          push @{$index{'dc.'.$f->{xmlname}}}, $f->{ui_value};
          push @{$index{'dc.'.$f->{xmlname}."_".$a->{ui_value}}}, $f->{ui_value};     
        }
      }        
    }else{
      push @{$index{'dc.'.$f->{xmlname}}}, $f->{ui_value};
    }
  }    

  # get GEO and turn to solr geospatial types
  if($r_ds->{dshash}->{'GEO'}){
    my $geo_model = PhaidraAPI::Model::Geo->new;
    my $r_geo = $geo_model->get_object_geo_json($self, $pid, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
    if($r_geo->{status} ne 200){      
      $res->{alerts} = [{ type => 'danger', msg => "Error adding GEO fields from $pid" }];
      for $a (@{$r_geo->{alerts}}){
        push @{$res->{alerts}}, $a;
      }
    }else{
      for my $plm (@{$r_geo->{geo}->{kml}->{document}->{placemark}}){

        # bbox -> WKT/CQL ENVELOPE syntax. Example: ENVELOPE(-10, 20, 15, 10) which is minX, maxX, maxY, minY order
        if(exists($r_geo->{polygon})){
          my $coords = $r_geo->{polygon}->{outerboundaryis}->{linearring}->{coordinates};
          # we have to sort them minX, maxX, maxY, minY
          my $minLat = 9999;
          my $maxLat = 0;
          my $minLon = 9999;
          my $maxLon = 0;
          for my $ll (@$coords){            
            $maxLon = $ll->{longitude} if $ll->{longitude} > $maxLon;
            $minLon = $ll->{longitude} if $ll->{longitude} < $minLon;
            $maxLat = $ll->{latitude} if $ll->{latitude} > $maxLat;
            $minLat = $ll->{latitude} if $ll->{latitude} < $minLat;
          }

          push @{$index{bbox}}, "ENVELOPE($minLat, $maxLat, $maxLon, $minLon)";
        }
        
        # latlong -> latitude,longitude
        if(exists($r_geo->{point})){
          push @{$index{latlong}}, $r_geo->{point}->{coordinates}->{latitude}.",".$r_geo->{point}->{coordinates}->{longitude};
        }
      }      
    }
  }

  # metadata
  if($r_ds->{dshash}->{'UWMETADATA'}){
    my $r_add_uwm = $self->_add_uwm_index($pid, \%index);
    if($r_add_uwm->{status} ne 200){
      $res->{alerts} = [{ type => 'danger', msg => "Error adding UWMETADATA fields for $pid, skipping" }];
      for $a (@{$r_add_uwm->{alerts}}){
        push @{$res->{alerts}}, $a;
      }
    }    
  }
  if($r_ds->{dshash}->{'MODS'}){
    my $r_add_mods = $self->_add_mods_index($pid, \%index);
    if($r_add_mods->{status} ne 200){
      $res->{alerts} = [{ type => 'danger', msg => "Error adding MODS fields for $pid, skipping" }];
      for $a (@{$r_add_mods->{alerts}}){
        push @{$res->{alerts}}, $a;
      }
    } 
  }

  # triples
  my $r_add_triples = $self->_add_triples_index($pid, $search_model, \%index);
  if($r_add_triples->{status} ne 200){
    $res->{alerts} = [{ type => 'danger', msg => "Error getting triples for $pid, skipping" }];
    for $a (@{$r_add_triples->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }   

  # relationships
  my $r_rel = $rel_model->get($self, $pid, $search_model);
  if($r_rel->{status} ne 200){
    $res->{alerts} = [{ type => 'danger', msg => "Error getting relationships for $pid, skipping" }];
    for $a (@{$r_rel->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }else{
    while (my ($k, $v) = each %{$r_rel->{relationships}}) {
      $index{$k} = $v;
    }
  }
    
  # list of datastreams
  my @dskeys = keys %{$r_ds->{dshash}};
  $index{datastreams} = \@dskeys;

  # inventory
  my $inv_coll = $self->paf_mongo->db->collection('foxml.ds');
  if($inv_coll){
    my $ds_doc = $inv_coll->find({pid => $pid})->sort({ "updated_at" => -1})->next;
    $index{size} = $ds_doc->{fs_size};
  }

  # pid
  $index{pid} = $pid;    

  # ts
  $index{_updated} = time;    

  $res->{index} = \%index;
  return $res;
}

sub _add_triples_index {

  my ($self, $pid, $search_model, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my $r_trip = $search_model->triples($self, "<info:fedora/$pid> * *", 0);
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
  my ($self, $pid, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my $mods_model = PhaidraAPI::Model::Mods->new;  
  my $r_mods = $mods_model->get_object_mods_json($self, $pid, 'basic', $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});      
  if($r_mods->{status} ne 200){        
    return $r_mods;            
  }

  my @roles;
  for my $n (@{$r_mods->{mods}}){

    if($n->{xmlname} eq 'name'){
      next unless exists $n->{children};
      my $firstname;
      my $lastname;
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
      push @roles, { name => "$firstname $lastname", role => $role } unless $name eq ' ';
    }

    if($n->{xmlname} eq 'originInfo'){
      next unless exists $n->{children};
      for my $n1 (@{$n->{children}}){
        if($n1->{xmlname} eq 'dateIssued'){
          push @{$index->{bib}->{published}}, $n1->{ui_value} if $n1->{ui_value} ne '';
        }
        if($n1->{xmlname} eq 'publisher'){
          push @{$index->{bib}->{publisher}}, $n1->{ui_value} if $n1->{ui_value} ne '';
        }
        if($n1->{xmlname} eq 'place'){
          if(exists($n1->{children})){
            for my $n2 (@{$n1->{children}}){
              if($n2->{xmlname} eq 'placeTerm'){
                push @{$index->{bib}->{publisherlocation}}, $n2->{ui_value} if $n2->{ui_value} ne '';  
              }
            }            
          }          
        }
        if($n1->{xmlname} eq 'edition'){
          push @{$index->{bib}->{edition}}, $n1->{ui_value} if $n1->{ui_value} ne '';
        }
      }
    }
  }

  push @{$index->{bib}->{roles}}, \@roles;   

  return $res;
}

sub _add_uwm_index {
  my ($self, $pid, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my $uwmetadata_model = PhaidraAPI::Model::Uwmetadata->new;  
  my $r_uwm = $uwmetadata_model->get_object_metadata($self, $pid, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password}, 'resolved');      
  if($r_uwm->{status} ne 200){        
    return $r_uwm;            
  }

  my $uwm = $r_uwm->{uwmetadata};

  # general
  my $general = $self->_find_first_uwm_node_rec("http://phaidra.univie.ac.at/XML/metadata/lom/V1.0", "general", $uwm);
  if($general){
    if($general->{children}){
      for my $gf (@{$general->{children}}){
        if($gf->{xmlname} eq 'irdata'){
          push @{$index->{bib}->{ir}}, $gf->{ui_value} if $gf->{ui_value} ne '';  
        }
      }
    }
  }

  # roles
  my $roles = $self->_get_uwm_roles($uwm);
  push @{$index->{bib}->{roles}}, $roles;   

  # digital book stuff
  my $digbook = $self->_find_first_uwm_node_rec("http://phaidra.univie.ac.at/XML/metadata/digitalbook/V1.0", "digitalbook", $uwm);
  if($digbook){
    if($digbook->{children}){
      for my $dbf (@{$digbook->{children}}){
        if($dbf->{xmlname} eq 'publisher'){
          push @{$index->{bib}->{publisher}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
        if($dbf->{xmlname} eq 'publisherlocation'){
          push @{$index->{bib}->{publisherlocation}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
        if($dbf->{xmlname} eq 'name_magazine'){
          push @{$index->{bib}->{journal}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
        if($dbf->{xmlname} eq 'volume'){
          push @{$index->{bib}->{volume}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
        if($dbf->{xmlname} eq 'edition'){
          push @{$index->{bib}->{edition}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
        if($dbf->{xmlname} eq 'releaseyear'){
          push @{$index->{bib}->{published}}, $dbf->{ui_value} if $dbf->{ui_value} ne '';  
        }
      }
    }
  }  

  # "GPS"
  #<ns9:gps>13°3&apos;6&apos;&apos;E|47°47&apos;45&apos;&apos;N</ns9:gps>
  #<ns9:gps>23°12&apos;19&apos;&apos;E|35°27&apos;8&apos;&apos;N</ns9:gps>
  my $gps = $self->_find_first_uwm_node_rec("http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0", "gps", $uwm);
  #"ui_value": "13Â°3'6''E|47Â°47'45''N",
  my $coord = $gps->{ui_value};
  $coord =~ s/Â//g;
  $coord =~ m/(\d+)°(\d+)'(\d+)''(E|W)\|(\d+)°(\d+)'(\d+)''(N|S)/g;
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
  
  push @{$index->{latlong}}, "$lat_dec,$lon_dec";

  return $res;
}

sub _get_uwm_roles {
  my ($self, $uwm) = @_;

  my $life = $self->_find_first_uwm_node_rec("http://phaidra.univie.ac.at/XML/metadata/lom/V1.0", "lifecycle", $uwm);

  my @roles;
  for my $ch (@{$life->{children}}){
    if($ch->{xmlname} eq "contribute"){

      my $role;
      my $contribution_data_order;
      my @names;
      for my $n (@{$ch->{children}}){
        if(($n->{xmlname} eq "role")){
          if(exists($uwm_2_mods_roles{$n->{ui_value}})){
            $role = $uwm_2_mods_roles{$n->{ui_value}};
          }else{
            $self->app->log->error("Failed to map uwm role ".$n->{ui_value}." to a role code.");
          }
        }
      }
      for my $n (@{$ch->{attributes}}){
        if($n->{xmlname} eq 'data_order'){
          # we are going to make the hierarchy flat so multiply the higher level order value
          $contribution_data_order = $n->{ui_value}*100;
        }
      }

      if($role){
        for my $l1 (@{$ch->{children}}){

          my %entity;

          next if $l1->{xmlname} eq "role";

          if($l1->{xmlname} eq "entity"){      
            my $firstname;      
            my $lastname;
            for my $l2 (@{$l1->{children}}){
              next if $l2->{xmlname} eq "type";
              if($l2->{xmlname} eq "firstname"){
                $firstname = $l2->{ui_value} if $l2->{ui_value} ne '';
              }elsif($l2->{xmlname} eq "lastname"){
                $lastname = $l2->{ui_value} if $l2->{ui_value} ne '';
              }else{
                $entity{$l2->{xmlname}} = $l2->{ui_value} if $l2->{ui_value} ne '';
              }
            }
            my $name = "$firstname $lastname";
            $entity{name} = $name unless $name eq ' ';
            $entity{role} = $role;
          }

          for my $n (@{$l1->{attributes}}){
            if($n->{xmlname} eq 'data_order'){
              $entity{data_order} = $n->{ui_value} + $contribution_data_order;
            }
          }

          push @roles, \%entity if defined $role;
        }
      }
    }
  }

  return \@roles;
}

sub _find_first_uwm_node_rec {
  my ($self, $xmlns, $xmlname, $uwm) = @_;

  my $ret;
  for my $n (@{$uwm}){
    if(($n->{xmlname} eq $xmlname) && ($n->{xmlns} eq $xmlns)){
      $ret = $n;
      last;
    }else{
      my $ch_size = defined($n->{children}) ? scalar (@{$n->{children}}) : 0;
      if($ch_size > 0){
        $ret = $self->_find_first_uwm_node_rec($xmlns, $xmlname, $n->{children});
        last if $ret;
      }
    }
  }

  return $ret;
}

1;
