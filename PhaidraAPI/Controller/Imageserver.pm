package PhaidraAPI::Controller::Imageserver;

use strict;
use warnings;
use v5.10;
use Mango 0.24;
use base 'Mojolicious::Controller';
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(decode encode url_escape url_unescape);
use Mojo::ByteStream qw(b);
use Digest::SHA qw(hmac_sha1_hex);
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Authorization;

sub process {

  my $self = shift;

  my $pid = $self->stash('pid');
  my $ds = $self->param('ds');
  my $skipexisting = $self->param('skipexisting');

  my $authz_model = PhaidraAPI::Model::Authorization->new;
  my $res = $authz_model->check_rights($self, $pid, 'rw');
	unless($res->{status} eq '200'){
		$self->render(json => $res->{json}, status => $res->{status});
    return;
	}

  if($skipexisting && ($skipexisting eq 1)){
    if(defined($ds)){
      my $res1 = $self->paf_mongo->db->collection('jobs')->find({pid => $pid, ds => $ds})->sort({ "created" => -1})->next;
      if($res1->{pid}){
        $self->render(json => { alerts => [{ type => 'info', msg => "Job for pid[$pid] and ds[$ds] already created" }], job => $res1}, status => 200);
        return;
      }
    }else{
      my $res1 = $self->paf_mongo->db->collection('jobs')->find({pid => $pid})->sort({ "created" => -1})->next;
      if($res1->{pid}){
        $self->render(json => { alerts => [{ type => 'info', msg => "Job for pid[$pid] already created" }], job => $res1}, status => 200);
        return;
      }
    }
  }

  my $hash;
  if(defined($ds)){
    $hash = hmac_sha1_hex($pid."_".$ds, $self->app->config->{imageserver}->{hash_secret});
    $self->paf_mongo->db->collection('jobs')->insert({pid => $pid, ds => $ds, agent => "pige", status => "new", idhash => $hash, created => time });  
  }else{
    $hash = hmac_sha1_hex($pid, $self->app->config->{imageserver}->{hash_secret});
    $self->paf_mongo->db->collection('jobs')->insert({pid => $pid, agent => "pige", status => "new", idhash => $hash, created => time });   
  }

  my $res = $self->paf_mongo->db->collection('jobs')->find({pid => $pid})->sort({ "created" => -1})->next;

  $self->render(json => $res, status => 200);
}

sub process_pids {

  my $self = shift;  

  my $skipexisting = $self->param('skipexisting');
  my $pids = $self->param('pids');
  unless(defined($pids)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No pids sent' }]} , status => 400) ;
    return;
  }

  eval {
    if(ref $pids eq 'Mojo::Upload'){
      $self->app->log->debug("Pids sent as file param");
      $pids = $pids->asset->slurp;
      $self->app->log->debug("parsing json");
      $pids = decode_json($pids);
    }else{
      $self->app->log->debug("parsing json");
      $pids = decode_json(b($pids)->encode('UTF-8'));
    }
  };

  if($@){
    $self->app->log->error("Error: $@");
    $self->render(json => { alerts => [{ type => 'danger', msg => $@ }]} , status => 400);
    return;
  }

  my @results;
  for my $pid (@{$pids->{pids}}){

    if($skipexisting && ($skipexisting eq 1)){
      my $res1 = $self->paf_mongo->db->collection('jobs')->find({pid => $pid})->sort({ "created" => -1})->next;
      next if $res1->{pid};
    }

    # create new job to process image
    my $hash = hmac_sha1_hex($pid, $self->app->config->{imageserver}->{hash_secret});    
    $self->paf_mongo->db->collection('jobs')->insert({ pid => $pid, agent => "pige", status => "new", idhash => $hash, created => time });

    # create a temporary hash for the image to hide the real hash in case we want to forbid access to the picture
    my $tmp_hash = hmac_sha1_hex($hash, $self->app->config->{imageserver}->{tmp_hash_secret});
    $self->mango->db->collection('imgsrv.hashmap')->insert({ pid => $pid, idhash => $hash, tmp_hash => $tmp_hash, created => time });    
    
    push @results, { pid => $pid, idhash => $hash, tmp_hash => $tmp_hash };
  }

  $self->render(json => \@results, status => 200);

}

sub status {

  my $self = shift;  

  my $pid = $self->stash('pid');

  my $authz_model = PhaidraAPI::Model::Authorization->new;
  my $res = $authz_model->check_rights($self, $pid, 'ro');
	unless($res->{status} eq '200'){
		$self->render(json => $res->{json}, status => $res->{status});
    return;
	}

  my $res = $self->paf_mongo->db->collection('jobs')->find({pid => $pid})->sort({ "created" => -1})->next;

  $self->render(json => $res, status => 200);

}


sub tmp_hash {

  my $self = shift;  

  my $pid = $self->stash('pid');

  # check rights
  my $object_model = PhaidraAPI::Model::Object->new;
  my $rres = $object_model->get_datastream($self, $pid, 'READONLY', $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if($rres->{status} eq '404'){
      
    # it's ok
    my $res = $self->mango->db->collection('imgsrv.hashmap')->find_one({pid => $pid});
    if(!defined($res) || !exists($res->{tmp_hash})){
      # if we could not find the temp hash, look into the jobs if the image isn't there as processed
      my $res1 = $self->paf_mongo->db->collection('jobs')->find({pid => $pid})->sort({ "created" => -1})->next;
      if(!defined($res1) || $res1->{status} ne 'finished'){
        # if it isn't then this image isn't known to imageserver
        $self->render(json => { alerts => [{ type => 'info', msg => 'Not found in imageserver' }]}, status => 404);
        return;
      }else{        
        # if it is, create the temp hash
        if($res1->{idhash}){
          my $tmp_hash = hmac_sha1_hex($res1->{idhash}, $self->app->config->{imageserver}->{tmp_hash_secret});
          $self->mango->db->collection('imgsrv.hashmap')->insert({ pid => $pid, idhash => $res1->{idhash}, tmp_hash => $tmp_hash, created => time });    
          $self->render(text => $tmp_hash, status => 200);
          return;
        }        
      }
      
    }else{
      $self->render(text => $res->{tmp_hash}, status => 200);
      return;
    }


  }else{
     $self->render(json => {}, status => 403);
     return;
  }    

}

sub get {

  my $self = shift;  

  #my $pid = $self->stash('pid');
      
  my $res = { alerts => [], status => 200 };

  my $url = Mojo::URL->new;

  $url->scheme($self->app->config->{imageserver}->{scheme});
  $url->host($self->app->config->{imageserver}->{host});
  $url->path($self->app->config->{imageserver}->{path});

  my $isr = $self->app->config->{imageserver}->{image_server_root};

  my $p;
  my $p_name;
  my $params = $self->req->params->to_hash;  
  for my $param_name ('FIF','IIIF','Zoomify','DeepZoom') {
    if(exists($params->{$param_name})){          
      $p = $params->{$param_name};
      $p_name = $param_name;
      last;
    }
  }

  unless($p){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Cannot find IIIF, Zoomify or DeepZoom parameter' }]} , status => 400);
  }

  # get pid
  $p =~ m/([a-z]+:[0-9]+)_?([A-Z]+)?\.tif/;
  my $pid = $1;
  my $ds = $2;

  # check rights        
  my $cachekey = 'img_rights_'.$self->stash->{basic_auth_credentials}->{username}."_$pid";
  my $status_cacheval = $self->app->chi->get($cachekey);
  unless($status_cacheval){
    $self->app->log->debug("[cache miss] $cachekey");
    my $object_model = PhaidraAPI::Model::Object->new;
    my $rres = $object_model->get_datastream($self, $pid, 'READONLY', $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
    $status_cacheval = $rres->{status};
    $self->app->chi->set($cachekey, $status_cacheval, '1 day');        
  }else{
    $self->app->log->debug("[cache hit] $cachekey");
  }

  unless($status_cacheval eq 404){
    $self->render(json => {}, status => 403);
    return;
  }

  # infer hash
  my $hash;
  if(defined($ds)){
    $hash = hmac_sha1_hex($pid."_".$ds, $self->app->config->{imageserver}->{hash_secret});
  }else{
    $hash = hmac_sha1_hex($pid, $self->app->config->{imageserver}->{hash_secret});
  }
  my $root = $self->app->config->{imageserver}->{image_server_root};
  my $first = substr($hash, 0, 1);
  my $second = substr($hash, 1, 1);
  my $imgpath = "$root/$first/$second/$hash.tif";

  # add leading slash if missing
  $p =~ s/^\/*/\//;
  # replace pid with hash
  $p =~ s/([a-z]+:[0-9]+)(_[A-Z]+)?\.tif/$imgpath/;

  # we have to put the imagepath param first, imageserver needs this order
  my $new_params = Mojo::Parameters->new;
  $new_params->append($p_name => $p);

  # have to go through pairs because ->params->names changes the order and the order is
  # significant for FIF
  # "Note that the FIF command must always be the first parameter and the JTL or CVT command must always be the last."
  # (from http://iipimage.sourceforge.net/documentation/protocol/)
  for (my $i = 0; $i < @{$self->req->params->pairs}; $i += 2) {
    my ($name, $value) = @{$self->req->params->pairs}[$i, $i + 1];
    next if $name eq $p_name;
    $new_params->append( $name => $self->req->params->every_param($name));
  }

  my $xurl = $url->to_string."?".$self->param_to_string($new_params->pairs);

  $self->render_later;    
  $self->ua->get( $xurl => sub { my ($ua, $tx) = @_; $self->tx->res($tx->res); $self->rendered; } );

  #my $tx = $self->ua->get( $xurl );
  #$self->tx->res($tx->res);
  #$self->rendered; 
}

# we cannot let mojo url-escape the values, imageserver won't take it
sub param_to_string {
  my $self = shift;
  my $pairs = shift;

  # Build pairs (HTML Living Standard)  
  return '' unless @$pairs;
  my @pairs;
  for (my $i = 0; $i < @$pairs; $i += 2) {
    my ($name, $value) = @{$pairs}[$i, $i + 1];

    # Escape and replace whitespace with "+"
    $name  = encode 'UTF-8', $name;
    $name  = url_escape $name,  '^*\-.0-9A-Z_a-z';
    $value = encode 'UTF-8', $value;
    #$value = url_escape $value, '^*\-.0-9A-Z_a-z';
    s/\%20/\+/g for $name, $value;

    push @pairs, "$name=$value";
  }

  return join '&', @pairs;
}

1;
