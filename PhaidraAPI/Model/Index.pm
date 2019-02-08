package PhaidraAPI::Model::Index;

use strict;
use warnings;
use v5.10;
use utf8;
use Time::HiRes qw/tv_interval gettimeofday/;
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

our %indexed_datastreams = (
  "UWMETADATA" => 1,
  "MODS" => 1,
  "ANNOTATIONS" => 1,
  "GEO" => 1,
  "RELS-EXT" => 1,
  "JSON-LD" => 1
);

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

our %uwm_metadataqualitycheck = (
  "http://phaidra.univie.ac.at/XML/metadata/extended/V1.0/voc_40/1557089" => "nok",
  "http://phaidra.univie.ac.at/XML/metadata/extended/V1.0/voc_40/1557088" => "ok",
  "http://phaidra.univie.ac.at/XML/metadata/extended/V1.0/voc_40/1557087" => "todo"
);

our %educational_learningresourcetype = (
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1700" => "problem_statement",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1695" => "slide",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1692" => "figure",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1690" => "questionnaire",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1689" => "simulation",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1701" => "self_assessment",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1693" => "graph",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1699" => "experiment",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1698" => "exam",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1697" => "narrative_text",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1694" => "index",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1696" => "table",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1691" => "diagram",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1702" => "lecture",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_11/1688" => "exercise"
);

our %educational_enduserrole = (
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_14/1713" => "teacher",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_14/1715" => "learner",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_14/1716" => "manager"
);

our %educational_context = (
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_15/1719" => "training",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_15/1720" => "other",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_15/1717" => "school",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational/voc_15/1718" => "higher_education"
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
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1561147" => "conservator",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1562629" => "calligrapher",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1562630" => "transcriber",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1562631" => "editorofcompilation",

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
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1557099" => "adp",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1562795" => "trl",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1561102" => "adr",

  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1561224" => "mfr",
  "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/voc_3/1562796" => "mfr" # remove this from objects, it's a duplicate

);

sub update {
  my ($self, $c, $pid, $dc_model, $search_model, $rel_model, $object_model, $ignorestatus) = @_;

  my $res = { status => 200 };    

  if( exists($c->app->config->{index_mongodb}) || exists($c->app->config->{solr})){

    my $cmodel_res = $search_model->get_cmodel($c, $pid);
    if($cmodel_res->{status} ne 200){
      return $cmodel_res;
    }

    if($cmodel_res->{cmodel} && $cmodel_res->{cmodel} ne 'Page'){

      my $t0 = [gettimeofday];
      my $r = $self->_get($c, $pid, $dc_model, $search_model, $rel_model, $object_model, $ignorestatus);
      #$c->app->log->debug("XXXXXXX indexing took ".tv_interval($t0));
      $res = $r;

      my $collectionMembers = $r->{index}->{haspart} if exists $r->{index}->{haspart};
      # don't save this
      delete $r->{index}->{haspart};

      my $members = $r->{index}->{hasmember} if exists $r->{index}->{hasmember};
      # don't save this
      delete $r->{index}->{hasmember};

      my $updateurl = Mojo::URL->new;
      $updateurl->scheme($c->app->config->{solr}->{scheme});
      $updateurl->userinfo($c->app->config->{solr}->{username}.":".$c->app->config->{solr}->{password});
      $updateurl->host($c->app->config->{solr}->{host});
      $updateurl->port($c->app->config->{solr}->{port});
      if($c->app->config->{solr}->{path}){
        $updateurl->path("/".$c->app->config->{solr}->{path}."/solr/".$c->app->config->{solr}->{core}."/update");
      }else{
        $updateurl->path("/solr/".$c->app->config->{solr}->{core}."/update");
      }
      $updateurl->query(commit => 'true');

      my $ua = Mojo::UserAgent->new;

      if($r->{status} eq 200){

        if(exists($c->app->config->{index_mongodb})){
          $c->index_mongo->db->collection($c->app->config->{index_mongodb}->{collection})->update({pid => $pid}, $r->{index}, { upsert => 1 });
          $c->app->log->debug("[$pid] mongo index updated");          
        }

        if(exists($c->app->config->{solr})){
          $t0 = [gettimeofday];
          my @docs = ($r->{index});
          my $post = $ua->post($updateurl => json => \@docs);
          #$c->app->log->debug("XXXXXXX posting index took ".tv_interval($t0));
          if (my $r = $post->success) {
            $c->app->log->debug("[$pid] solr document updated");
          }else {
            my ($err, $code) = $post->error;
            unshift @{$res->{alerts}}, { type => 'danger', msg => "[$pid] Error updating solr: ".$c->app->dumper($err) };
            $res->{status} =  $code ? $code : 500;
          }
          
        }
      }elsif(($r->{status} eq 301) || ($r->{status} eq 302)){
        # 301 - object is in state Deleted
        # 302 - object is in state Inactive
        if(exists($c->app->config->{solr})){
          my $post = $ua->post($updateurl => json => { delete => $pid });
          if (my $r = $post->success) {
            $c->app->log->debug("[$pid] solr document deleted");
          }else {
            my ($err, $code) = $post->error;
            unshift @{$res->{alerts}}, { type => 'danger', msg => "[$pid] Error deleting document from solr: ".$c->app->dumper($err) };
            $res->{status} =  $code ? $code : 500;
          }
        }
        # change back to 200, deleting an Inactive or Deleted object from index is ok
        $res->{status} = 200;
      }

      if($r->{index}->{cmodel} eq 'Collection' && defined($collectionMembers)){
        my $umr = $self->_update_members($c, $pid, $updateurl, $collectionMembers, 'ispartof');
        if($umr->{status} ne 200){
          $res->{status} = $umr->{status};
          for my $a (@{$umr->{alerts}}){
            push @{$res->{alerts}}, $a;
          }
        }
      }

      if($r->{index}->{cmodel} eq 'Container' && defined($members)){
        my $umr = $self->_update_members($c, $pid, $updateurl, $members, 'ismemberof');
        if($umr->{status} ne 200){
          $res->{status} = $umr->{status};
          for my $a (@{$umr->{alerts}}){
            push @{$res->{alerts}}, $a;
          }
        }
      }

    }else{
      my $msg = "[$pid] cmodel: ".$cmodel_res->{cmodel}.", skipping update";
      $c->app->log->debug($msg); 
      unshift @{$res->{alerts}}, { type => 'info', msg => $msg };
    }

  }

  return $res;
}

sub _update_members {

  my ($self, $c, $pid, $updateurl, $members, $relation) = @_;

  my $res = { status => 200 }; 

  $c->app->log->debug("[$pid] this object should have ".(scalar @{$members})." $relation relations");
  #$c->app->log->debug("XXXXXXXXXXXX ".$c->app->dumper($members));

  # get current members
  my $urlget = Mojo::URL->new;
  $urlget->scheme($c->app->config->{solr}->{scheme});
  $urlget->host($c->app->config->{solr}->{host});
  $urlget->port($c->app->config->{solr}->{port});
  if($c->app->config->{solr}->{path}){
    $urlget->path("/".$c->app->config->{solr}->{path}."/solr/".$c->app->config->{solr}->{core}."/select");
  }else{
    $urlget->path("/solr/".$c->app->config->{solr}->{core}."/select");
  }

  $urlget->query(q => "$relation:\"$pid\"", fl => "pid", rows => "0", wt => "json");

  my $ua = Mojo::UserAgent->new;

  my $get = $ua->get($urlget);
  my $numFound;
  if (my $r_num = $get->success) {
    $numFound = $r_num->json->{response}->{numFound};
  }else{
    my ($err, $code) = $get->error;
    $c->app->log->error("[$pid] error getting object $relation relations count ".$c->app->dumper($err));
    unshift @{$res->{alerts}}, { type => 'danger', msg => "error getting object $relation relations count" };
    unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
    $res->{status} =  $code ? $code : 500;
    return $res;
  }

  $urlget->query(q => "$relation:\"$pid\"", fl => "pid", rows => $numFound, wt => "json"); 

  $get = $ua->get($urlget);

  my @curr_members;
  if (my $r_mem = $get->success) {
    for my $c_m (@{$r_mem->json->{response}->{docs}}){
      push @curr_members, $c_m->{pid};
    }
  }else{
    my ($err, $code) = $get->error;
    $c->app->log->error($urlget);
    $c->app->log->error("[$pid] error getting object $relation relations ".$c->app->dumper($err));
    unshift @{$res->{alerts}}, { type => 'danger', msg => "error getting object $relation relations" };
    unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
    $res->{status} =  $code ? $code : 500;
    return $res;
  }       

  $c->app->log->debug("[$pid] this object currently has ".(scalar @curr_members)." $relation relations");
  #$c->app->log->debug("XXXXXXXXXXXX ".$c->app->dumper(\@curr_members));

  my @add_to;
  my @remove_from;

  for my $m (@{$members}){
    unless( $m ~~ @curr_members ) {
      push  @add_to, $m;
    }
  } 
  $c->app->log->debug("[$pid] found ".(scalar @add_to)." $relation relations to add");
  #$c->app->log->debug("XXXXXXXXXXXX ".$c->app->dumper(\@add_to));
  for my $m (@curr_members){
    unless( $m ~~ @{$members} ) {
      push  @remove_from, $m;
    }
  }
  $c->app->log->debug("[$pid] found ".(scalar @remove_from)." $relation relations to remove");
  #$c->app->log->debug("XXXXXXXXXXXX ".$c->app->dumper(\@remove_from));

  if(scalar @add_to > 0){
    my $r_add = $self->_update_relation($c, $pid, $relation, \@add_to, $updateurl, 'add');
    if($r_add->{status} ne 200){
      $res->{status} = $r_add->{status};
      for my $a (@{$r_add->{alerts}}){
        push @{$res->{alerts}}, $a;
      }
    }
  }

  if(scalar @remove_from > 0){
    my $r_remove = $self->_update_relation($c, $pid, $relation, \@remove_from, $updateurl, 'remove');
    if($r_remove->{status} ne 200){
      $res->{status} = $r_remove->{status};
      for my $a (@{$r_remove->{alerts}}){
        push @{$res->{alerts}}, $a;
      }
    }
  }

  return $res;
}

sub _update_relation {

  my ($self, $c, $pid, $relation, $members, $updateurl, $action) = @_;

  my $res = { status => 200 };

  #$c->app->log->debug("[$pid] updating ".(scalar @{$members})." members");

  if(scalar @{$members} <= 500){
    return $self->_update_relation_post($c, $pid, $relation, $members, $updateurl, $action);
  }else{
    my @batch;
    for my $m (@{$members}){
      push @batch, $m;
      if(scalar @batch >= 500){
        my $r = $self->_update_relation_post($c, $pid, $relation, \@batch, $updateurl, $action);
        if($r->{status} ne 200){
          for my $a (@{$r->{alerts}}){
            push @{$res->{alerts}}, $a;
            $res->{status} = $r->{status};
          }
        }
        @batch = ();
      }
    }
    my $r = $self->_update_relation_post($c, $pid, $relation, \@batch, $updateurl, $action);
      if($r->{status} ne 200){
        for my $a (@{$r->{alerts}}){
          push @{$res->{alerts}}, $a;
          $res->{status} = $r->{status};
       }
    }
  }
  
  return $res;
}

sub _update_relation_post {

  my ($self, $c, $pid, $relation, $members, $updateurl, $action) = @_;

  my $res = { status => 200 };

  my @update;
  for my $m (@{$members}){
    push @update, {
      pid => $m,
      $relation => { $action => $pid }
    };
  }

  my $ua = Mojo::UserAgent->new;

  # versions makes sure the document exists already
  # if it does not the field would be created as "ispartof.add" which is wrong
  # plus the member might not exist for a reason, eg it's a Page, we don't want to add it
  $updateurl->query(commit => 'true', versions => 'true', _version_ => 1);

  my $post = $ua->post($updateurl => json => \@update);

  if (my $r = $post->success) {
    $c->app->log->debug("[$pid] updated ".(scalar @{$members})." documents");
  }else{
    my ($err, $code) = $post->error;
    unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
    $res->{status} =  $code ? $code : 500;
  }

  return $res;
}

sub get {
  my ($self, $c, $pid, $ignorestatus) = @_;

  my $dc_model = PhaidraAPI::Model::Dc->new;
  my $search_model = PhaidraAPI::Model::Search->new;
  my $rel_model = PhaidraAPI::Model::Relationships->new;
  my $object_model = PhaidraAPI::Model::Object->new;

  return $self->_get($c, $pid, $dc_model, $search_model, $rel_model, $object_model, $ignorestatus);
}

sub _get {

  my ($self, $c, $pid, $dc_model, $search_model, $rel_model, $object_model, $ignorestatus) = @_;

  my $res = { status => 200 };        

  my $t0 = [gettimeofday];

  my %index;

  $c->app->log->debug("indexing $pid: getting foxml");
  my $r_oxml = $object_model->get_foxml($c, $pid);
  $c->app->log->debug("indexing $pid: parsing foxml");
  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($r_oxml->{foxml});
  $c->app->log->debug("indexing $pid: foxml parsed!");

  for my $e ($dom->find('foxml\:objectProperties')->each){
    for my $e1 ($e->find('foxml\:property')->each){

      if($e1->attr('NAME') eq 'info:fedora/fedora-system:def/model#state'){
        if($ignorestatus && ($ignorestatus eq '1')){
          $c->app->log->debug("[_get index] ignorestatus=$ignorestatus");
        }else{
          # skip inactive objects
          my $state = $e1->attr('VALUE');
          if($state ne 'Active'){
            my $errmsg = "[_get index] $pid is $state, deleting from index.";
            $c->app->log->warn($errmsg);
            push @{$res->{alerts}}, { type => 'danger', msg => $errmsg };
            if($state eq 'Deleted'){
              $res->{status} = 301;
            }
            if($state eq 'Inactive'){
              $res->{status} = 302;
            }
            return $res;
          }
        }
      }

      if($e1->attr('NAME') eq 'info:fedora/fedora-system:def/model#ownerId'){
        $index{owner} = $e1->attr('VALUE');
      }

      if($e1->attr('NAME') eq 'info:fedora/fedora-system:def/model#createdDate'){
        $index{created} = $e1->attr('VALUE');
      }

      if($e1->attr('NAME') eq 'info:fedora/fedora-system:def/model#lastModifiedDate'){
        $index{modified} = $e1->attr('VALUE');
      }

    }
  }

  my %datastreams;
  my %datastreamids;
  for my $e ($dom->find('foxml\:datastream')->each){

    $datastreamids{$e->attr('ID')} = 1;

    if($indexed_datastreams{$e->attr('ID')}){
      my $latestVersion = $e->find('foxml\:datastreamVersion')->first;
      for my $e1 ($e->find('foxml\:datastreamVersion')->each){
        if($e1->attr('CREATED') gt $latestVersion->attr('CREATED')){
          $latestVersion = $e1;
        }
      }
      $datastreams{$e->attr('ID')} = $latestVersion;
    }

  }

  push @{$index{datastreams}}, keys %datastreamids; 

  if(exists($datastreams{'RELS-EXT'})){ # it should

    my $r_relsext = $self->_index_relsext($c, $datastreams{'RELS-EXT'}->find('foxml\:xmlContent')->first, \%index);
    if($r_relsext->{status} ne 200){
      push @{$res->{alerts}}, { type => 'danger', msg => "Error indexing RELS-EXT for $pid" };
      for $a (@{$r_relsext->{alerts}}){
        push @{$res->{alerts}}, $a;
      }
    }

  }

  if(exists($datastreams{'UWMETADATA'})){

    my $r_add_uwm = $self->_add_uwm_index($c, $pid, $datastreams{'UWMETADATA'}->find('foxml\:xmlContent')->first, \%index);
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
      my ($dc_p, $dc_oai) = $dc_model->map_uwmetadata_2_dc_hash($c, $pid, $index{cmodel}, $datastreams{'UWMETADATA'}->find('foxml\:xmlContent')->first, $r0->{metadata_tree}, $uw_model, 1);
      #$c->app->log->debug("XXXXXXXXXXXXXXXXX ".$c->app->dumper($dc_p));
      $self->_add_dc_index($c, $dc_p, \%index);
    }
  }
 
  if(exists($datastreams{'GEO'})){

    my $geo_model = PhaidraAPI::Model::Geo->new;
    my $r_geo = $geo_model->xml_2_json($c, $datastreams{'GEO'}->find('foxml\:xmlContent')->first);
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
          $index{latlon} = (($minLat + $maxLat)/2).','.(($minLon + $maxLon)/2);
        }
        
        # latlon -> latitude,longitude
        if(exists($plm->{point})){
          $index{latlon} = $plm->{point}->{coordinates}->{latitude}.",".$plm->{point}->{coordinates}->{longitude};
        }
      }      
    }

  }

  if(exists($datastreams{'MODS'})){
    
    my $mods_model = PhaidraAPI::Model::Mods->new;  
    my $r_mods = $mods_model->xml_2_json($c, $datastreams{'MODS'}->find('foxml\:xmlContent')->first, 'basic');
    if($r_mods->{status} ne 200){        
      push @{$res->{alerts}}, { type => 'danger', msg => "Error converting MODS xml to json for $pid" };
      for $a (@{$r_mods->{alerts}}){
        push @{$res->{alerts}}, $a;
      }           
    }else{
      my $r_add_mods = $self->_add_mods_index($c, $pid, $r_mods->{mods}, \%index);
      if($r_add_mods->{status} ne 200){
        push @{$res->{alerts}}, { type => 'danger', msg => "Error adding MODS fields for $pid" };
        for $a (@{$r_add_mods->{alerts}}){
          push @{$res->{alerts}}, $a;
        }
      }else{
        my ($dc_p, $dc_oai) = $dc_model->map_mods_2_dc_hash($c, $pid, $index{cmodel}, $datastreams{'MODS'}->find('foxml\:xmlContent')->first, $mods_model, 1);
        $self->_add_dc_index($c, $dc_p, \%index);
      }
    }

  }

  if(exists($datastreams{'JSON-LD'})){
    my $jsonld_model = PhaidraAPI::Model::Jsonld->new;  
    my $r_jsonld = $jsonld_model->get_object_jsonld_parsed($c, $pid, $c->app->config->{phaidra}->{intcallusername}, $c->app->config->{phaidra}->{intcallpassword});
    #$c->app->log->debug("XXXXXXXXX found JSON-LD: ".$c->app->dumper($r_jsonld));
    if($r_jsonld->{status} ne 200){        
      push @{$res->{alerts}}, { type => 'danger', msg => "Error getting JSON-LD for $pid" };
      for $a (@{$r_jsonld->{alerts}}){
        push @{$res->{alerts}}, $a;
      }           
    }else{

      my $jsonld = $r_jsonld->{'JSON-LD'};

      my $r_add_jsonld = $self->_add_jsonld_index($c, $pid, $jsonld, \%index);
      if($r_add_jsonld->{status} ne 200){
        push @{$res->{alerts}}, { type => 'danger', msg => "Error adding JSON-LD fields for $pid" };
        for $a (@{$r_add_jsonld->{alerts}}){
          push @{$res->{alerts}}, $a;
        }
      }else{
        my ($dc_p, $dc_oai) = $dc_model->map_jsonld_2_dc_hash($c, $pid, $index{cmodel}, $jsonld, $jsonld_model, 1);
        # $c->app->log->debug("found JSON-LD: ".$c->app->dumper($dc_p));
        $self->_add_dc_index($c, $dc_p, \%index);
      }
    }

  }

  if(exists($datastreams{'ANNOTATIONS'})){

    my $ann_model = PhaidraAPI::Model::Annotations->new;
    my $r_ann = $ann_model->xml_2_json($c, $datastreams{'ANNOTATIONS'}->find('foxml\:xmlContent')->first);
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

    # for fast annotation access, add them as json as well
    $index{annotations_json} = b(encode_json($r_ann->{annotations}))->decode('UTF-8');
  }

  # relations
  my $r_add_rrels = $self->_add_reverse_relations($c, $pid, $search_model, \%index);
  if($r_add_rrels->{status} ne 200){
    push @{$res->{alerts}}, { type => 'danger', msg => "Error adding reverse relationships for $pid" };
    for $a (@{$r_add_rrels->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }
  
  # inventory
  if(exists($c->app->config->{paf_mongodb})){
    my $inv_coll = $c->paf_mongo->db->collection('foxml.ds');
    if($inv_coll){
      my $ds_doc = $inv_coll->find({pid => $pid})->sort({ "updated_at" => -1})->next;
      $index{size} = $ds_doc->{fs_size};
    }
  }

  # pid
  $index{pid} = $pid;    

  my $resourcetype;
  $resourcetype = $cmodel_2_resourcetype{$index{cmodel}};    
  if($index{"bib_ir"} eq "yes"){
    $resourcetype = "journalarticle";
  }  
  if($index{"owner"} eq "ubmapsp2"){
    $resourcetype = "map";
  }
  if(exists($index{"dc_subject"})){
    for my $s (@{$index{"dc_subject"}}){
      if ($s eq "Altkarte" || $s eq "Karte" || $s eq "Themakarte"){
        $resourcetype = "map";
      }
    }  
  }
  $index{resourcetype} = $resourcetype;

  # ts
  $index{_updated} = time; 

  $res->{index} = \%index;

  #$c->app->log->debug("XXXXXXX indexing took ".tv_interval($t0));
  return $res;
}

=cut
info:fedora/fedora-system:def/model#hasModel
info:fedora/fedora-system:def/relations-external#hasCollectionMember
http://purl.org/dc/terms/references
http://phaidra.org/XML/V1.0/relations#isBackSideOf
http://phaidra.univie.ac.at/XML/V1.0/relations#hasSuccessor
http://phaidra.org/XML/V1.0/relations#isAlternativeFormatOf
http://phaidra.org/XML/V1.0/relations#isAlternativeVersionOf
=cut
sub _index_relsext {
  my ($self, $c, $xml, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my $cmodel = $xml->find('hasModel')->first->attr('rdf:resource');
  $cmodel =~ s/^info:fedora\/cmodel:(.*)$/$1/;
  $index->{cmodel} = $cmodel;

  for my $e ($xml->find('identifier')->each){
    my $o = $e->attr('rdf:resource');
    push @{$index->{dc_identifier}}, $o;
  }
  
  for my $e ($xml->find('references')->each){
    my $o = $e->attr('rdf:resource');
    $o =~ s/^info:fedora\/(.*)$/$1/;
    push @{$index->{references}}, $o;
  }

  for my $e ($xml->find('isBackSideOf')->each){
    my $o = $e->attr('rdf:resource');
    $o =~ s/^info:fedora\/(.*)$/$1/;
    push @{$index->{isbacksideof}}, $o;
  }

  for my $e ($xml->find('hasSuccessor')->each){
    my $o = $e->attr('rdf:resource');
    $o =~ s/^info:fedora\/(.*)$/$1/;
    push @{$index->{hassuccessor}}, $o;
  }

  for my $e ($xml->find('isAlternativeFormatOf')->each){
    my $o = $e->attr('rdf:resource');
    $o =~ s/^info:fedora\/(.*)$/$1/;
    push @{$index->{isalternativeformatof}}, $o;
  }

  for my $e ($xml->find('isAlternativeVersionOf')->each){
    my $o = $e->attr('rdf:resource');
    $o =~ s/^info:fedora\/(.*)$/$1/;
    push @{$index->{isalternativeversionof}}, $o;
  }

  # we save this now as haspart but this is later removed
  # instead the array is used to create ispartof in members
  for my $e ($xml->find('hasCollectionMember')->each){
    my $o = $e->attr('rdf:resource');
    $o =~ s/^info:fedora\/(.*)$/$1/;
    push @{$index->{haspart}}, $o;
  }

  # we save this now as hasmember but this is later removed
  # instead the array is used to create ismember in members
  for my $e ($xml->find('hasMember')->each){
    my $o = $e->attr('rdf:resource');
    $o =~ s/^info:fedora\/(.*)$/$1/;
    push @{$index->{hasmember}}, $o;
  }

  return $res;
}

sub _add_dc_index {

  my ($self, $c, $dc, $index) = @_;
  while (my ($xmlname, $values) = each %{$dc}) {
    for my $v (@{$values}){
      if($v->{value} ne ''){

        my $val = $v->{value};
        if(exists($v->{lang})){
          if (($xmlname eq 'title') || ($xmlname eq 'description')){
            push @{$index->{'dc_'.$xmlname}}, $val
          }
          my $lang = $v->{lang};
          if(length($v->{lang}) eq 2){
            $lang = $PhaidraAPI::Model::Languages::iso639map{$v->{lang}};
          }
          push @{$index->{'dc_'.$xmlname."_".$lang}}, $val;     
          if($xmlname eq 'title'){
            $index->{sort_dc_title} = $val;
            $index->{'sort_' . $lang . '_dc_title'} = $val;
          }
        }else{
          push @{$index->{'dc_'.$xmlname}}, $val;
          if($xmlname eq 'title'){
            $index->{sort_dc_title} = $val;
          }
        }
      }
    }
  }
     
}

sub _add_reverse_relations {

  my ($self, $c, $pid, $search_model, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my $r_trip = $search_model->triples($c, "* <info:fedora/fedora-system:def/relations-external#hasCollectionMember> <info:fedora/$pid>", 0);
  if($r_trip->{status} ne 200){
    return $r_trip;
  }
   
  for my $triple (@{$r_trip->{result}}){
    my $subject = @$triple[0];
    if($subject =~ m/^<info:fedora\/(.*)>$/){
      push @{$index->{ispartof}}, $1;        
    }    
  }

  my $r_trip = $search_model->triples($c, "* <http://pcdm.org/models#hasMember> <info:fedora/$pid>", 0);
  if($r_trip->{status} ne 200){
    return $r_trip;
  }
   
  for my $triple (@{$r_trip->{result}}){
    my $subject = @$triple[0];
    if($subject =~ m/^<info:fedora\/(.*)>$/){
      push @{$index->{ismemberof}}, $1;        
    }    
  }

  return $res;
}

=cut
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
=cut
sub _add_mods_index {
  my ($self, $c, $pid, $modsjson, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my @roles;
  for my $n (@{$modsjson}){

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

sub _add_jsonld_index {
  my ($self, $c, $pid, $jsonld, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my @roles;

  my @descriptions;
  if($jsonld->{'bf:note'}){
   for my $d (@{$jsonld->{'bf:note'}}){
      push @descriptions, $d;
    }
  }

  my $roles_res = $self->_add_jsonld_roles($c, $pid, $jsonld, $index);
  for my $a (@{$roles_res->{alerts}}){
    push @{$res->{alerts}}, $a;
  }
  for my $r (@{$roles_res->{roles}}){
    push @roles, $r;
  }

  if($jsonld->{'opaque:ethnographic'}){
    for my $o (@{$jsonld->{'opaque:ethnographic'}}) {
      for my $l (@{$o->{'rdfs:label'}}) {
        push @{$index->{"opaque_ethnographic"}}, $l->{'@value'};
      }
    }
  }

  if($jsonld->{'vra:hasInscription'}){
    for my $o (@{$jsonld->{'vra:hasInscription'}}) {
      for my $l (@{$o->{'rdfs:label'}}) {
        push @{$index->{"vra_inscription"}}, $l->{'@value'};
      }
    }
  }

  $index->{"roles_json"} = b(encode_json(\@roles))->decode('UTF-8');

  if(scalar @descriptions){
    $index->{"descriptions_json"} = b(encode_json(\@descriptions))->decode('UTF-8');
  }

  if($jsonld->{'dcterms:subject'}){
    for my $o (@{$jsonld->{'dcterms:subject'}}) {
      if ($o->{'@type'} eq 'phaidra:Subject') {
        my $rr = $self->_add_jsonld_index($c, $pid, $o, $index);
        for my $a (@{$rr->{alerts}}){
          push @{$res->{alerts}}, $a;
        }
      }
    }
  }

  if($jsonld->{'phaidra:digitizedObject'}){
    my $rr = $self->_add_jsonld_index($c, $pid, $jsonld->{'phaidra:digitizedObject'}, $index);
    for my $a (@{$rr->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }

  return $res;
}

sub _add_jsonld_roles {
  my ($self, $c, $pid, $jsonld, $index) = @_;
  my $res = { alerts => [], status => 200 };
  my @roles;
  for my $pred (keys %{$jsonld}){
    if($pred =~ m/role:(\w+)/g){
      my $role = $1;
      push @roles, { $pred => $jsonld->{$pred} };
      my $name;
      for my $contr (@{$jsonld->{$pred}}){
        if($contr->{'@type'} eq 'schema:Person'){
          $name = $contr->{'schema:givenName'}[0]->{'@value'}." ".$contr->{'schema:familyName'}[0]->{'@value'};
        }elsif($contr->{'@type'} eq 'schema:Organisation'){
          $name = $contr->{'schema:name'}[0]->{'@value'};
        }else{
          $c->app->log->error("Unknown contributor type in jsonld for pid $pid");
          push @{$res->{alerts}}, { type => 'danger', msg => "Unknown contributor type in jsonld for pid $pid"};
        }
      }
      push @{$index->{"bib_roles_pers_$role"}}, $name unless ($name eq '' || $name eq ' ');
    }
  }
  $res->{roles} = \@roles;
  return $res;
}

sub _add_uwm_index {
  my ($self, $c, $pid, $uwmetadata, $index) = @_;

  my $res = { alerts => [], status => 200 };

  my $uwmetadata_model = PhaidraAPI::Model::Uwmetadata->new;  
  my $r_uwm = $uwmetadata_model->uwmetadata_2_json_basic($c, $uwmetadata, 'resolved');
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

  # lifecycle -> metadataqualitycheck
  my $metadataqualitycheck = $self->_find_first_uwm_node_rec($c, "http://phaidra.univie.ac.at/XML/metadata/extended/V1.0", "metadataqualitycheck", $uwm);
  if($metadataqualitycheck){
    $index->{"bib_mqc"} = $uwm_metadataqualitycheck{$metadataqualitycheck->{ui_value}};
  }

  # roles
  my ($roles, $contributions) = $self->_get_uwm_roles($c, $uwm);
  # $c->app->log->debug("XXXXXXXXXXXX ".$c->app->dumper($contributions));
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
        if($dbf->{xmlname} eq 'alephurl'){
          $dbf->{ui_value} =~ m/(AC\d+)/;
          if($1){
            push @{$index->{"dc_identifier"}}, $1;
          }
        }
      }
    }
  }

  my $edu = $self->_get_uwm_educational($c, $uwm);
  for my $e (@{$edu}){
    push @{$index->{'educational_'.$e->{xmlname}}}, $e->{ui_value} if $e->{ui_value} ne '';
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

sub _get_uwm_educational {
  my ($self, $c, $uwm) = @_;

  my @edu;
  for my $n (@{$uwm}){
    if(($n->{xmlns} eq 'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0') && ($n->{xmlname} eq 'educational')){
      if(defined($n->{children})){
        for my $n1 (@{$n->{children}}){
          if(($n1->{xmlns} eq 'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0') && ($n1->{xmlname} eq 'educationals')){
            if(defined($n1->{children})){
              for my $n2 (@{$n1->{children}}){
                if(($n2->{xmlns} eq 'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational') && ($n2->{xmlname} eq 'learningresourcetype')){
                  push @edu, { xmlname => $n2->{xmlname}, ui_value => $educational_learningresourcetype{$n2->{ui_value}} };
                }
                if(($n2->{xmlns} eq 'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational') && ($n2->{xmlname} eq 'enduserrole')){
                  push @edu, { xmlname => $n2->{xmlname}, ui_value => $educational_enduserrole{$n2->{ui_value}} };
                }
                if(($n2->{xmlns} eq 'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational') && ($n2->{xmlname} eq 'context')){
                  push @edu, { xmlname => $n2->{xmlname}, ui_value => $educational_context{$n2->{ui_value}} };
                }
              }
            }
          }
        }
      }
      last;
    }
  }

  return \@edu;
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
        if($n->{xmlname} eq "date"){
          $contribution_json{date} = $n->{ui_value} if $n->{ui_value} ne '';
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
          next if $l1->{xmlname} eq "date";

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
