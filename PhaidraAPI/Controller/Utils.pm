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

    $r = $search_model->datastreams_hash($self, $pid);
    if($r->{status} ne 200){

      # get DC (prefferably DC_P)
      my $dclabel = 'DC';
      if($r->{dshash}->{'DC_P'}){
        $dclabel = 'DC_P';
      }
      my $res = $dc_model->get_object_dc_json($self, $pid, $dclabel, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
      if($res->{status} ne 200){
        if($res->{status} eq 404){
          push @res, { pid => $pid, res => $res };
        }      
      }
      # DC fields
      my %index;
      for my $f (@{$res->{dc}}){      
        if(exists($f->{attributes})){
          for my $a (@{$f->{attributes}}){
            if($a->{xmlname} eq 'xml:lang'){
              push @{$index{$f->{xmlname}."_".$a->{ui_value}}}, $f->{ui_value};    
            }
          }        
        }
        push @{$index{$f->{xmlname}}}, $f->{ui_value};
      }    

      # get GEO
      if($r->{dshash}->{'GEO'}){
        my $geo_model = PhaidraAPI::Model::Geo->new;
        my $r_geo = $geo_model->get_object_geo_json($self, $pid, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
        push @{$index{'geo'}}, $r_geo->{geo};
      }

      # metadata
      if($r->{dshash}->{'UWMETADATA'}){
        $self->_add_uwm_index($c, $pid, $index);
      }
      if($r->{dshash}->{'MODS'}){
        $self->_add_mods_index($c, $pid, $index);
      }
      
      

    }else{
      push @res, { pid => $pid, res => $r };
    }    

    

    # list of datastreams
    my @dskeys = keys %{$r->{dshash}};
    $index{datastreams} = \@dskeys;

    # pid
    $index{pid} = $pid;    

    # ts
    $index{updated} = time;    

    # save
    $self->index_mongo->db->collection($self->app->config->{index_mongodb}->{collection})->update({pid => $pid}, \%index, { upsert => 1 });         

    push @res, { pid => $pid, res => 'OK'};
  }
  
  $self->render(json => { results => \@res }, status => 200);
}

sub _add_mods_index {
  my ($self, $c, $pid, $index) = @_;

}

sub _add_uwm_index {
  my ($self, $c, $pid, $index) = @_;

  my $uwmetadata_model = PhaidraAPI::Model::Uwmetadata->new;  
  my $r_uwm = $uwmetadata_model->get_object_metadata($self, $pid, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password}, 'resolved');      
  if($r_uwm->{status} ne 200){        
    push @res, { pid => $pid, res => $r_uwm };              
  }

  my $uwm = $r_uwm->{uwmetadata};

  # author
  my $digital_authors = $self->_get_uwm_role($c, "46", $uwm);
  my $analogue_authors = $self->_get_uwm_role($c, "1552095", $uwm);
  push @{$index{uwm}->{authors}} = $digital_authors if defined $digital_authors; 
  push @{$index{uwm}->{authors}} = $analogue_authors if defined $analogue_authors; 

  # publisher
  my $publishers = $self->_get_uwm_role($c, "47", $uwm);
  push @{$index{uwm}->{publishers}} = $publishers if defined $publishers; 
}

sub _get_uwm_role {
  my ($self, $c, $role, $uwm, $index) = @_;

  my $life = $self->_find_first_uwm_node_rec("http://phaidra.univie.ac.at/XML/metadata/lom/V1.0", "lifecycle", $uwm);

  my @names;
  for my $ch (@{$life}){
    if($ch->{xmlname} eq "contribute"){
      my $found = 0;
      for my $n (@{$ch->{children}}){
        if(($ch->{xmlname} eq "role") && ($ch->{ui_value} eq $role)){
          $found = 1;
        }
      }
      
      if($found){
        for my $l1 (@{$ch->{children}}){

          my $fn;
          my $ln;
          my $in;
          if($l1->{xmlname} eq "entity"){
            
            for my $l2 (@{$l1->{children}}){
              if($l2->{xmlname} eq "firstname"){
                $fn = $l2->{ui_value};
              }
              if($l2->{xmlname} eq "lastname"){
                $ln = $l2->{ui_value};
              }
              if($l2->{xmlname} eq "institution"){
                $in = $l2->{ui_value};
              }
            }
          }

          my $name;
          if($fn || $ln){
            $name = "$fn $ln";
          }else{
            if($in){
              $name = $in;
            }
          }

          push @names, $name if defined $name;
        }
      }
    }
  }

  return \@names;
}

sub _find_first_uwm_node_rec {
  my ($self, $c, $xmlns, $xmlname, $uwm) = @_;

  my $ret;
  for my $n (@{$uwm}){
    if(($n->{xmlname} eq $xmlname) && ($n->{xmlns} eq $xmlns)){
      $ret = $n;
      last;
    }else{
      my $ch_size = defined($->{children}) ? scalar (@{$n->{children}}) : 0;
      if($ch_size > 0){
        $ret = $self->_find_uwm_node_rec($c, $n->{children});
        last if $ret;
      }
    }
  }

  return $ret;
}

1;
