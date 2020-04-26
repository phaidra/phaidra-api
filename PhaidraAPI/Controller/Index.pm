package PhaidraAPI::Controller::Index;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::ByteStream qw(b);
use Mojo::Util qw(xml_escape html_unescape);
use Mojo::JSON qw(encode_json decode_json);
use PhaidraAPI::Model::Index;
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Dc;

sub get {
  my ($self) = @_;

  my $pid = $self->stash('pid');
  my $ignorestatus = $self->param('ignorestatus');
  
  my $index_model = PhaidraAPI::Model::Index->new;
  my $r = $index_model->get($self, $pid, $ignorestatus);

  $self->render(json => $r, status => $r->{status});
}

sub get_relationships {
  my ($self) = @_;

  my $res = { alerts => [], status => 200 };

  my $pid = $self->stash('pid');

  my $ua = Mojo::UserAgent->new;
  my $urlget = Mojo::URL->new;
  $urlget->scheme($self->app->config->{solr}->{scheme});
  $urlget->host($self->app->config->{solr}->{host});
  $urlget->port($self->app->config->{solr}->{port});
  if($self->app->config->{solr}->{path}){
    $urlget->path("/".$self->app->config->{solr}->{path}."/solr/".$self->app->config->{solr}->{core}."/select");
  }else{
    $urlget->path("/solr/".$self->app->config->{solr}->{core}."/select");
  }

  $self->app->log->debug("getting doc of $pid");
  my $idx = $self->get_doc_for_pid($ua, $urlget, $pid);
  my $rels = {
    # own
    # these two are supported elswhere, not needed here
    # hascollectionmember => [],
    # hasmember => [],
    references => [],
    isbacksideof => [],
    hassuccessor => [],
    isalternativeformatof => [],
    isalternativeversionof => [],
    # reverse
    ispartof => [],
    ismemberof => [],
    isreferencedby => [],
    hasbackside => [],
    issuccesorof => [],
    haslaternativeformat => [],
    haslaternativeversion => []
  };

  # reverse only
  #'info:fedora/fedora-system:def/relations-external#hasCollectionMember'
  if ($idx->{ispartof}) {
    for my $relpid (@{$idx->{ispartof}}) {
      $self->app->log->debug("reverse: getting doc of $relpid (of which $pid is ispartof)");
      my $d = $self->get_doc_for_pid($ua, $urlget, $relpid);
      push $rels->{ispartof}, $d if $d;
    }
  }

  # reverse only
  #'http://pcdm.org/models#hasMember'
  if ($idx->{ismemberof}) {
    for my $relpid (@{$idx->{ismemberof}}) {
      $self->app->log->debug("reverse: getting doc of $relpid (of which $pid is ismemberof)");
      my $d = $self->get_doc_for_pid($ua, $urlget, $relpid);
      push $rels->{ismemberof}, $d if $d;
    }
  }

  #'http://purl.org/dc/terms/references'
  $self->add_indexed_and_reverse($ua, $urlget, $idx, 'references', 'isreferencedby', $pid, $rels);

  #'http://phaidra.org/XML/V1.0/relations#isBackSideOf'
  $self->add_indexed_and_reverse($ua, $urlget, $idx, 'isbacksideof', 'hasbackside', $pid, $rels);

  #'http://phaidra.org/XML/V1.0/relations#isThumbnailFor'
  $self->add_indexed_and_reverse($ua, $urlget, $idx, 'isthumbnailfor', 'hasthumbnail', $pid, $rels);

  #'http://phaidra.univie.ac.at/XML/V1.0/relations#hasSuccessor'
  $self->add_indexed_and_reverse($ua, $urlget, $idx, 'hassuccessor', 'issuccesorof', $pid, $rels);

  #'http://phaidra.org/XML/V1.0/relations#isAlternativeFormatOf'
  $self->add_indexed_and_reverse($ua, $urlget, $idx, 'isalternativeformatof', 'haslaternativeformat', $pid, $rels);

  #'http://phaidra.org/XML/V1.0/relations#isAlternativeVersionOf'
  $self->add_indexed_and_reverse($ua, $urlget, $idx, 'isalternativeversionof', 'haslaternativeversion', $pid, $rels);

  my @versions;
  my $versionsCheck = {
    $pid => {
      loaded => 1,
      checked => 1
    }
  };
  for my $v (@{$rels->{hassuccessor}}) {
    push @versions, $v;
    $versionsCheck->{$v->{pid}} = {
      loaded => 1,
      checked => 0
    }
  }
  for my $v (@{$rels->{issuccesorof}}) {
    push @versions, $v;
    $versionsCheck->{$v->{pid}} = {
      loaded => 1,
      checked => 0
    }
  }
  $self->add_set_rec($ua, $urlget, 'hassuccessor', $pid, \@versions, $versionsCheck);
  $res->{versions} = \@versions;

  my @altformats;
  my $altformatsCheck = {
    $pid => {
      loaded => 1,
      checked => 1
    }
  };
  for my $v (@{$rels->{isalternativeformatof}}) {
    push @altformats, $v;
    $altformatsCheck->{$v->{pid}} = {
      loaded => 1,
      checked => 0
    }
  }
  for my $v (@{$rels->{haslaternativeversion}}) {
    push @altformats, $v;
    $altformatsCheck->{$v->{pid}} = {
      loaded => 1,
      checked => 0
    }
  }
  $self->add_set_rec($ua, $urlget, 'isalternativeformatof', $pid, \@altformats, $altformatsCheck);
  $res->{alternativeformats} = \@altformats;

  my @altversions;
  my $altversionsCheck = {
    $pid => {
      loaded => 1,
      checked => 1
    }
  };
  for my $v (@{$rels->{isalternativeversionof}}) {
    push @altversions, $v;
    $altversionsCheck->{$v->{pid}} = {
      loaded => 1,
      checked => 0
    }
  }
  for my $v (@{$rels->{isalternativeversionof}}) {
    push @altversions, $v;
    $altversionsCheck->{$v->{pid}} = {
      loaded => 1,
      checked => 0
    }
  }
  $self->add_set_rec($ua, $urlget, 'isalternativeversionof', $pid, \@altversions, $altversionsCheck);
  $res->{alternativeversions} = \@altversions;

  $res->{relationships} = $rels;

  $self->render(json => $res, status => 200);
}

sub add_set_rec {
  my ($self, $ua, $urlget, $relationfield, $pid, $related, $relatedCheck) = @_;

  for my $pid (keys %{$relatedCheck}) {
    unless ($relatedCheck->{$pid}->{loaded}) {
      # load
      $self->app->log->debug("getting doc of $pid ($relationfield)");
      my $d = $self->get_doc_for_pid($ua, $urlget, $pid);
      push @{$related}, $d;
      $relatedCheck->{$pid}->{loaded} = 1;
      # add found relationships
      if ($d->{$relationfield}) {
        for my $r (@{$d->{$relationfield}}) {
          unless ($relatedCheck->{$pid}) {
            $relatedCheck->{$pid} = {
              loaded => 0,
              checked => 0
            };
          }
        }
      }
    }
    
    # add reverse relationships
    $self->app->log->debug("reverse: getting docs where $pid is $relationfield");
    $urlget->query(q => "$relationfield:\"$pid\"", rows => "1000", wt => "json");
    my $r = $ua->get($urlget)->result;
    if ($r->is_success) {
      for my $d (@{$r->json->{response}->{docs}}) {
        if ($relatedCheck->{$d->{pid}}) {
          unless ($relatedCheck->{$d->{pid}}->{loaded}) {
            push @{$related}, $d;
            $relatedCheck->{$d->{pid}}->{loaded} = 1;
          }
        } else {
          push @{$related}, $d;
          $relatedCheck->{$pid} = {
            loaded => 1,
            checked => 0
          };
        }
      }
    } else {
      $self->app->log->error("[$pid] error getting solr query[$relationfield:\"$pid\"]: ".$r->code." ".$r->message);
    }
    $relatedCheck->{$pid}->{checked} = 1;
  }

  $self->app->log->debug("relatedCheck: ".$self->app->dumper($relatedCheck));

  for my $pid (keys %{$relatedCheck}) {
    unless ($relatedCheck->{$pid}->{checked}) {
      $self->add_set_rec($ua, $urlget, 'hassuccessor', $pid, $related, $relatedCheck);
    }
  }
}

sub add_indexed_and_reverse {
  my ($self, $ua, $urlget, $idx, $relationfield, $reverserelation, $pid, $rels) = @_;

  if ($idx->{$relationfield}) {
    # get doc of the related document
    for my $relpid (@{$idx->{$relationfield}}) {
      $self->app->log->debug("getting doc of $relpid ($relationfield of $pid)");
      my $d = $self->get_doc_for_pid($ua, $urlget, $relpid);
      push @{$rels->{$relationfield}}, $d if $d;
    }
  }

  # get reverse relationships
  $self->app->log->debug("reverse: getting docs where $pid is $relationfield");
  $urlget->query(q => "$relationfield:\"$pid\"", rows => "1000", wt => "json");
  my $r = $ua->get($urlget)->result;
  if ($r->is_success) {
    for my $d (@{$r->json->{response}->{docs}}) {
      push $rels->{$reverserelation}, $d;
    }
  }else{
    $self->app->log->error("[$pid] error getting solr query[$relationfield:\"$pid\"]: ".$r->code." ".$r->message);
  }
  return undef;
}

sub get_doc_for_pid {
  my ($self, $ua, $urlget, $pid) = @_;

  $urlget->query(q => "pid:\"$pid\"", rows => "1", wt => "json");
  my $r = $ua->get($urlget)->result;
  if ($r->is_success) {
    for my $d (@{$r->json->{response}->{docs}}) {
      return $d;
    }
  }else{
    $self->app->log->error("[$pid] error getting solr doc for object[$pid]: ".$r->code." ".$r->message);
  }
}

sub get_dc {
  my ($self) = @_;

  my $pid = $self->stash('pid');
  my $ignorestatus = $self->param('ignorestatus');
  
  my $index_model = PhaidraAPI::Model::Index->new;
  my $r = $index_model->get($self, $pid, $ignorestatus);

  if($r->{status} ne 200){
    $self->render(json => $r, status => $r->{status});
    return;
  }

  my $dc = '<oai_dc:dc xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd">';
  my %have_lang_field;
  
  for my $field (keys %{$r->{index}}){
    if($field =~ m/^dc_(\w+)_(\w+)/){
      $have_lang_field{$1} = 1
    }
  }
  for my $field (keys %{$r->{index}}){
    if($field =~ m/^dc_(\w+)_(\w+)/){
      for my $value (@{$r->{index}->{$field}}){
        $dc .= "\n  <dc:$1 xml:lang=\"$2\">". xml_escape(html_unescape($value)) ."</dc:$1>"
      }
    }elsif($field =~ m/^dc_(\w+)/){
      # if there is eg dc_title_deu do not add dc_title too, except for authors and contributors (where institutions have language but names do not)
      next if ($have_lang_field{$1}) && ($field ne 'dc_creator') && ($field ne 'dc_contributor');
      
      for my $value (@{$r->{index}->{$field}}){
        $dc .= "\n  <dc:$1>". xml_escape(html_unescape($value)) ."</dc:$1>"
      }
      
    }    
  }

  $dc .= "\n</oai_dc:dc>";

  $self->render(text => $dc, format => 'xml', status => 200);
}


sub update {

  my $self = shift;
  my $pid_param = $self->stash('pid');
  my $ignorestatus = $self->param('ignorestatus');

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

    unless(defined($pids->{pids})){
      $self->render(json => { alerts => [{ type => 'danger', msg => 'No pids found' }]} , status => 400) ;
      return;
    }

    @pidsarr = @{$pids->{pids}};
  }
  
  my $index_model = PhaidraAPI::Model::Index->new;
  my $dc_model = PhaidraAPI::Model::Dc->new;
  my $search_model = PhaidraAPI::Model::Search->new;
  my $object_model = PhaidraAPI::Model::Object->new;
  my @res;
  my $pidscount = scalar @pidsarr;
  my $i = 0;
  for my $pid (@pidsarr){

    $i++;
    $self->app->log->info("Processing $pid [$i/$pidscount]");

    eval {

	    my $r = $index_model->update($self, $pid, $dc_model, $search_model, $object_model, $ignorestatus);  
	    if($r->{status} eq 200 && $pidscount > 1){      
	      push @res, { pid => $pid, status => 200 };
	    }else{
	      $r->{pid} = $pid;
	      push @res, $r;
	    }
	  };

	  if($@){
      $self->app->log->error("pid $pid Error: $@");         
    }
    
  }
  
  if(scalar @res == 1){
    $self->render(json => { result => $res[0] }, status => 200);
  }else{
    $self->render(json => { results => \@res }, status => 200);
  }
}

1;
