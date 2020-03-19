package PhaidraAPI::Model::Object;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use Data::Dumper;
use Mojo::Util qw(xml_escape encode decode);
use Mojo::JSON qw(encode_json decode_json);
use Mojo::ByteStream qw(b);
use lib "lib/phaidra_binding";
use Phaidra::API;
use PhaidraAPI::Model::Rights;
use PhaidraAPI::Model::Geo;
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Mods;
use PhaidraAPI::Model::Jsonld;
use PhaidraAPI::Model::Jsonldprivate;
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Hooks;
use PhaidraAPI::Model::Membersorder;
use PhaidraAPI::Model::Index;
use IO::Scalar;
use File::MimeInfo;
use File::Temp 'tempfile';

# only those where a PID can be the object (in RDF sense)
my %relationships_to_object = (
  "info:fedora/fedora-system:def/model#hasModel" => 1,
  "info:fedora/fedora-system:def/relations-external#hasCollectionMember" => 1,
  "http://pcdm.org/models#hasMember" => 1,
  "http://purl.org/dc/terms/references" => 1,
  "http://phaidra.org/XML/V1.0/relations#isBackSideOf" => 1,
  "http://phaidra.univie.ac.at/XML/V1.0/relations#hasSuccessor" => 1,
  "http://phaidra.org/XML/V1.0/relations#isAlternativeFormatOf" => 1,
  "http://phaidra.org/XML/V1.0/relations#isAlternativeVersionOf" => 1
);

my %datastream_versionable = (
	'COLLECTIONORDER' => 'false',
	'UWMETADATA' => 'true',
	'MODS' => 'true',
	'JSON-LD' => 'true',
	'RIGHTS' => 'true',
	'GEO' => 'true',
	'DC' => 'false',
	'DC_P' => 'false',
	'DC_OAI' => 'false'
);

my %mime_to_cmodel = (
	'application/pdf' => 'cmodel:PDFDocument',
	'application/x-pdf' => 'cmodel:PDFDocument',

	'image/jpeg' => 'cmodel:Picture',
	'image/gif' => 'cmodel:Picture',
	'image/tiff' => 'cmodel:Picture',
	'image/png' => 'cmodel:Picture',

	'audio/x-wav' => 'cmodel:Audio',
	'audio/wav' => 'cmodel:Audio',
	'audio/mpeg' => 'cmodel:Audio',
	'audio/flac' => 'cmodel:Audio',
	'audio/ogg' => 'cmodel:Audio',

	'video/mpeg' => 'cmodel:Video',
	'video/avi' => 'cmodel:Video',
	'video/x-msvideo' => 'cmodel:Video',
	'video/mp4' => 'cmodel:Video',
	'video/quicktime' => 'cmodel:Video',
	'video/x-matroska' => 'cmodel:Video'
);


sub info {
  my $self = shift;
  my $c = shift;
  my $pid = shift;
  my $username = shift;
  my $password = shift;

  my $res = { alerts => [], status => 200 };
  my $info;

  my $index_model = PhaidraAPI::Model::Index->new;
  my $docres = $index_model->getDoc($c, $pid);
  if ($docres->{status} != 200) {
    return $docres;
  } else {
    $info = $docres->{doc};
  }

  if ($info->{cmodel} eq 'Collection') {
    my $urlget = Mojo::URL->new;
    $urlget->scheme($c->app->config->{solr}->{scheme});
    $urlget->host($c->app->config->{solr}->{host});
    $urlget->port($c->app->config->{solr}->{port});
    if($c->app->config->{solr}->{path}){
      $urlget->path("/".$c->app->config->{solr}->{path}."/solr/".$c->app->config->{solr}->{core}."/select");
    }else{
      $urlget->path("/solr/".$c->app->config->{solr}->{core}."/select");
    }

    $urlget->query(q => "ispartof:\"$pid\"", fl => "pid", rows => "0", wt => "json");

    my $ua = Mojo::UserAgent->new;

    my $r_num = $ua->get($urlget)->result;
    my $numFound;
    if ($r_num->is_success) {
      $info->{haspartsize} = $r_num->json->{response}->{numFound};
    }else{
      $c->app->log->error("[$pid] error getting object collection size: ".$r_num->code." ".$r_num->message);
      unshift @{$res->{alerts}}, { type => 'danger', msg => "error getting collection size: ".$r_num->code." ".$r_num->message};
    }
  }

  if (exists($info->{uwm_roles_json})) {
    my $rolesjsonstr = encode 'UTF-8', @{$info->{uwm_roles_json}}[0];
    $info->{uwm_roles_json} = decode_json($rolesjsonstr);
  }

  my %dshash;
  for my $ds (@{$info->{datastreams}}){
    $dshash{$ds} = 1
  }
  $info->{dshash} = \%dshash;
  
  $info->{metadata} = undef;

  if($dshash{'JSON-LD'}){   
    my $jsonld_model = PhaidraAPI::Model::Jsonld->new;  
    my $r_jsonld = $jsonld_model->get_object_jsonld_parsed($c, $pid, $username, $password);
    if($r_jsonld->{status} ne 200){
      push @{$res->{alerts}}, @{$r_jsonld->{alerts}} if scalar @{$r_jsonld->{alerts}} > 0;
      push @{$res->{alerts}}, { type => 'danger', msg => 'Error getting JSON-LD' };
    }else{
      $info->{metadata}->{'JSON-LD'} = $r_jsonld->{'JSON-LD'};
    }
  }

  if($dshash{'MODS'}){   
    my $mods_model = PhaidraAPI::Model::Mods->new;
    my $r = $mods_model->get_object_mods_json($c, $pid, 'basic', $username, $password);
    if($r->{status} ne 200){
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      push @{$res->{alerts}}, { type => 'danger', msg => 'Error getting MODS' };
    }else{
      $info->{metadata}->{mods} = $r->{mods};
    }
  }

  if($dshash{'UWMETADATA'}){   
    my $uwmetadata_model = PhaidraAPI::Model::Uwmetadata->new;
    my $r = $uwmetadata_model->get_object_metadata($c, $pid, 'resolved', $username, $password);
    if($r->{status} ne 200){
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      push @{$res->{alerts}}, { type => 'danger', msg => 'Error getting UWMETADATA' };
    }else{
      $info->{metadata}->{uwmetadata} = $r->{uwmetadata};
    }
  }

  if($dshash{'GEO'}){
    my $geo_model = PhaidraAPI::Model::Geo->new;
    my $r = $geo_model->get_object_geo_json($c, $pid, $username, $password);
    if($r->{status} ne 200){
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      push @{$res->{alerts}}, { type => 'danger', msg => 'Error getting GEO' };
    }else{
      $info->{metadata}->{geo} = $r->{geo};
    }
  }

  $info->{readrights} = 0;
  $info->{writerights} = 0;
  my $rores = $self->get_datastream($c, $pid, 'READONLY', $username, $password);
  if($rores->{status} eq '404'){
    $info->{readrights} = 1;
    if ($username) {
      my $rwres = $self->get_datastream($c, $pid, 'READWRITE', $username, $password);
      if($rwres->{status} eq '404'){
        $info->{writerights} = 1;
      }
    }
  }

  my $user_data = $c->app->directory->get_user_data($c, $info->{owner});
  $info->{owner} = {
    username => $user_data->{username},
    firstname => $user_data->{firstname},
    lastname => $user_data->{lastname},
    email => $user_data->{email}
  };

  # $c->app->log->debug("XXXXXXXXXXXXXX ".$c->app->dumper($info));

  $res->{info} = $info;
  return $res;
}

sub delete {
  my $self = shift;
  my $c = shift;
  my $pid = shift;
  my $username = shift;
  my $password = shift;

  my $res = { alerts => [], status => 200 };

	my $haswriterights = 0;
  $c->app->log->debug("[$pid] Changing object status to Deleted...");
  my $statusres = $self->modify($c, $pid, 'D', undef, undef, undef, undef, $username, $password);
  if ($statusres->{status} != 200) {
    return $statusres;
  } else {
		$haswriterights = 1;
	}
  $c->app->log->debug("[$pid] Object status changed to Deleted");

  # remove relationships - only do this AFTER it's clear the user has rights to delete this object since we're using intcall to remove relationships from related objects
	if($haswriterights){
    # 1) remove all relationships TO this object (RELS-EXT) from the related objects (eg remove it as a member from a collection)
    # - that will also trigger reindex on those objects
    my @remove_rels_from;
    my $search_model = PhaidraAPI::Model::Search->new;
    my $r_trip = $search_model->triples($c, "* * <info:fedora/$pid>", 0);
    if($r_trip->{status} ne 200){
      return $r_trip;
    }
    for my $triple (@{$r_trip->{result}}){
      my $subject = @$triple[0];
      my $predicate = @$triple[1];
      my $subjectpid;
      my $relationship;
      if($subject =~ m/^<info:fedora\/(.*)>$/){
        $subjectpid = $1;
      }
      if($predicate =~ m/^<(.*)>$/){
        $relationship = $1;
      }
      if($subjectpid && $relationship && defined($relationships_to_object{$relationship})){
        push @remove_rels_from, { from => $subjectpid, relationship => $relationship }
      }
    }
    for my $rel (@remove_rels_from){
      my @removerelationships;
      push @removerelationships, { predicate => $rel->{relationship}, object => "info:fedora/".$pid };
      $c->app->log->info("[$pid] Removing relationship to [$pid] from [".$rel->{from}."]");
      # use the array method purge_relationshipS, it triggers reindex
      my $r = $self->purge_relationships($c, $rel->{from}, \@removerelationships, $username, $password);
    }

    # 2) relationships from this object are saved in this object, so the delete will remove them
    # - but these relationships are often indexed in the related objects, so we need to reindex them
    #   (eg remove this collection from it's members index doc where it's saved like 'ispartof')
    # TODO. Meanwhile, if you want to delete eg a container but not it's members, remove the members from that container first (otherwise these will be invisible in search).
	}

  $c->app->log->debug("[$pid] Purging object...");
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid");

	my $ua = Mojo::UserAgent->new;
	my %headers;
  $self->add_upstream_headers($c, \%headers);

  my $deleteres = $ua->delete($url => \%headers)->result;
  if ($deleteres->code == 200) {
    $c->app->log->debug("[$pid] Object successfully purged");
    return $res;
  } else {
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $deleteres->message };
	  $res->{status} = $deleteres->code;
	}

  return $res;
}

sub add_upstream_headers {
  my $self = shift;
  my $c = shift;
  my $headers = shift;

  if ($c->stash->{remote_user}) {
    $headers->{$c->app->config->{authentication}->{upstream}->{principalheader}} = $c->stash->{remote_user};
    $headers->{$c->app->config->{authentication}->{upstream}->{affiliationheader}} = $c->stash->{remote_affiliation} if $c->stash->{remote_affiliation};
    $headers->{$c->app->config->{authentication}->{upstream}->{groupsheader}} = $c->stash->{remote_groups} if $c->stash->{remote_groups};
  }
}

sub modify {
	my $self = shift;
  my $c = shift;
  my $pid = shift;
  my $state = shift;
  my $label = shift;
  my $ownerid = shift;
  my $logmessage = shift;
  my $lastmodifieddate = shift;
  my $username = shift;
  my $password = shift;
  my $useadmin = shift;

  my $res = { alerts => [], status => 200 };

  my %params;
  $params{state} = $state if $state;
  $params{label} = $label if $label;
  $params{ownerId} = $ownerid if $ownerid;
  $params{logMessage} = $logmessage if $logmessage;
  $params{lastModifiedDate} = $lastmodifieddate if $lastmodifieddate;

  if($useadmin){
		$username = $c->app->{config}->{phaidra}->{adminusername};
		$password = $c->app->{config}->{phaidra}->{adminpassword};
	}

	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid");
	$url->query(\%params);

	my $ua = Mojo::UserAgent->new;
	my %headers;
  $self->add_upstream_headers($c, \%headers);

  my $putres = $ua->put($url => \%headers)->result;
  if ($putres->is_success) {
    my $hooks_model = PhaidraAPI::Model::Hooks->new;
    my $hr = $hooks_model->modify_object_hooks($c, $pid, $username, $password);
    if($hr->{status} ne 200){
      $c->app->log->error("Error indexing object $pid in modify_object_hooks: ".$c->app->dumper($hr));
    }
  } else {
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $putres->message };
	  $res->{status} =  $putres->{code} ? $putres->{code} : 500;
	}

  return $res;
}

sub create {
	my $self = shift;
    my $c = shift;
    my $contentmodel = shift;
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };

    $c->app->log->debug("Creating empty object");
    # create empty object
    my $r = $self->create_empty($c, $username, $password);
   	push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;

    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }

  	my $pid = $r->{pid};
  	$c->app->log->debug("Created object: $pid");
  	$res->{pid} = $pid;

  	my $oaiid = "oai:".$c->app->config->{phaidra}->{proaiRepositoryIdentifier}.":".$pid;
  	my @relationships;
	push @relationships, { predicate => "info:fedora/fedora-system:def/model#hasModel", object => "info:fedora/".$contentmodel };
	push @relationships, { predicate => "http://www.openarchives.org/OAI/2.0/itemID", object => $oaiid };

    # set cmodel and oai itemid
    $c->app->log->debug("Set cmodel ($contentmodel) and oaiitemid ($oaiid)");
		$r = $self->add_relationships($c, $pid, \@relationships, $username, $password, 1);
  	push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }

  	# add thumbnail
  	my $thumburl = "http://".$c->app->config->{phaidra}->{baseurl}."/preview/$pid";
  	$c->app->log->debug("Adding thumbnail ($thumburl)");
		$r = $self->add_datastream($c, $pid, "THUMBNAIL", "image/png", $thumburl, undef, undef, "E", undef, undef, $username, $password);
  	push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }

  	# add stylesheet
  	$r = $self->add_datastream($c, $pid, "STYLESHEET", "text/xml", $c->app->config->{phaidra}->{fedorastylesheeturl}, undef, undef, "E", undef, undef, $username, $password);
  	push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }

  	return $res;
}

sub get_state {
  my ($self, $c, $pid) = @_;

  my $res = { status => 200 };

  $c->app->log->debug("get_state $pid: getting foxml");
  my $r_oxml = $self->get_foxml($c, $pid);
  if($r_oxml->{status} ne 200){
    return $r_oxml;
  }
  $c->app->log->debug("get_state $pid: parsing foxml");
  my $dom = Mojo::DOM->new();
  $dom->xml(1);
  $dom->parse($r_oxml->{foxml});
  $c->app->log->debug("get_state $pid: foxml parsed!");

  for my $e ($dom->find('foxml\:objectProperties')->each){
    for my $e1 ($e->find('foxml\:property')->each){
      if($e1->attr('NAME') eq 'info:fedora/fedora-system:def/model#state'){
        my $state = $e1->attr('VALUE');
        $res->{state} = $state;
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
}

sub get_mimetype(){
	my ($self, $c, $asset) = @_;
	my $mimetype = undef;

	if($asset->is_file){
		# todo: maybe it won't be bad to look into the request headers as well

		$mimetype = File::MimeInfo::Magic::magic($asset->path);
		unless(defined($mimetype)){
			$mimetype = File::MimeInfo::Magic::globs($asset->path);
			unless(defined($mimetype)){
			    $mimetype = mimetype($asset->path);
			}
		}
	}else{
		my $data = $asset->slurp;
		my $sc = new IO::Scalar \$data;
		$mimetype = File::MimeInfo::Magic::magic($sc);
	}

	return $mimetype;
}

sub create_simple {

  my $self = shift;
  my $c = shift;
  my $cmodel = shift;
  my $metadata = shift;
  my $mimetype = shift;
  my $upload = shift;
  my $checksumtype = shift;
	my $checksum = shift;
  my $username = shift;
  my $password = shift;

  my $res = { alerts => [], status => 200 };

  unless(defined($metadata)){
    unshift @{$res->{alerts}}, { type => 'danger', msg => 'No metadata provided'};
    $res->{status} = 400;
    return $res;
  }

  # create object
  my $r = $self->create($c, $cmodel, $username, $password);
  if($r->{status} ne 200){
    $res->{status} = 500;
    unshift @{$res->{alerts}}, @{$r->{alerts}};
    unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error creating object'};
    return $res;
  }

  my $pid = $r->{pid};
  $res->{pid} = $pid;

  if ($cmodel eq 'cmodel:Resource') {
    unless (exists($metadata->{metadata}->{resourcelink})) {
      unshift @{$res->{alerts}}, { type => 'danger', msg => 'No resource link provided'};
      $res->{status} = 400;
      return $res;
    }
    # save link
    my $r = $self->add_datastream($c, $pid, "LINK", "text/html", $metadata->{metadata}->{resourcelink}, "Link to external resource", undef, "R", undef, undef, $username, $password);
    if($r->{status} ne 200){
      $res->{status} = $r->{status};
      foreach my $a (@{$r->{alerts}}){
        unshift @{$res->{alerts}}, $a;
      }
      unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving link'};
      return $res;
    }
  } else {

    # $c->app->log->debug("req Upload: ".$c->app->dumper($c->req->upload));
    # $c->app->log->debug("upload: ".$c->app->dumper($upload));

    my $size = $upload->size;
    my $name = $upload->filename;

    # save data first, because these may be needed (dsinfo..) when saving metadata
    $c->app->log->debug("[$pid] Saving octets: $name [$size B]");
    my %params;
    $params{controlGroup} = 'M';
    $params{dsLabel} = $name;
    if ($checksumtype) {
      $params{checksumType} = $checksumtype;
    }
    if ($checksum) {
      $params{checksum} = $checksum;
    }
    if(defined($mimetype)){
      $c->app->log->info("Provided mimetype $mimetype");
    }else{
      $mimetype = $self->get_mimetype($c, $upload->asset);
      unshift @{$res->{alerts}}, { type => 'info', msg => "Undefined mimetype, using magic: $mimetype" };
      $c->app->log->info("Undefined mimetype, using magic: $mimetype");
    }
    $params{mimeType} = $mimetype;

    my $url = Mojo::URL->new;
    $url->scheme('https');
    $url->userinfo("$username:$password");
    $url->host($c->app->config->{phaidra}->{fedorabaseurl});
    $url->path("/fedora/objects/$pid/datastreams/OCTETS");
    $url->query(\%params);

    my $ua = Mojo::UserAgent->new;
    my %headers;
    $self->add_upstream_headers($c, \%headers);
    $headers{'Content-Type'} = $mimetype;

    my $post = $ua->post($url => \%headers => form => { file => { file => $upload->asset }} );
    if ($r = $post->success) {
      $c->app->log->info("Data successfully uploaded: filename[$name] size[$size]");
    } else {
      my ($err, $code) = $post->error;
      unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
      $res->{status} =  $code ? $code : 500;
      return $res;
    }
  }

  # save metadata
  $r = $self->save_metadata($c, $pid, $cmodel, $metadata->{metadata}, $username, $password, 1);
  if($r->{status} ne 200){
    $res->{status} = $r->{status};
    foreach my $a (@{$r->{alerts}}){
      unshift @{$res->{alerts}}, $a;
    }
    unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving metadata'};
    return $res;
  }

  # activate
  $r = $self->modify($c, $pid, 'A', undef, undef, undef, undef, $username, $password);
  if($r->{status} ne 200){
    $res->{status} = $r->{status};
  foreach my $a (@{$r->{alerts}}){
    unshift @{$res->{alerts}}, $a;
  }
  unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error activating object'};
    return $res;
  }else{
    $c->app->log->info("Object successfully created pid[$pid]");
  }

  if (exists($metadata->{metadata}->{'ownerid'})) {
    $c->app->log->debug("Changing ownerid to ". $metadata->{metadata}->{'ownerid'});
    my $authorized = 0;
    if (
      ($username eq $c->app->config->{phaidra}->{intcallusername}) ||
      ($username eq $c->app->config->{phaidra}->{adminusername})
    ) {
      $authorized = 1;
    } else {
      if ($c->app->config->{authorization}) {
        if ($c->app->config->{authorization}->{canmodifyownerid}) {
          for my $user (@{$c->app->config->{authorization}->{canmodifyownerid}}) {
            if ($user eq $username) {
              $authorized = 1;
              last;
            }
          }
        }
      }
    }
    if ($authorized) {
      my $r = $self->modify($c, $pid, undef, undef, $metadata->{metadata}->{'ownerid'}, undef, undef, $username, $password, 1);
      if($r->{status} ne 200) {
        $res->{status} = $r->{status};
        foreach my $a (@{$r->{alerts}}) {
          unshift @{$res->{alerts}}, $a;
        }
        unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error modifying ownership'};
      }
    }
  }

  return $res;
}

sub create_container {

  my $self = shift;
  my $c = shift;
  my $metadata = shift;
  my $username = shift;
  my $password = shift;

  my $res = { alerts => [], status => 200 };

  unless(defined($metadata)){
    unshift @{$res->{alerts}}, { type => 'danger', msg => 'No metadata provided'};
    $res->{status} = 400;
    return $res;
  }

  my @children;
  $c->app->log->debug("Metadata: ".$c->app->dumper($metadata));

  my $container_metadata;

  if (exists($metadata->{metadata}->{'json-ld'}->{'container'})) {
    for my $k (keys %{$metadata->{metadata}->{'json-ld'}}){
      $c->app->log->debug("Found key: [$k]");
      if ( ($k ne 'container') ) {		
        my $childupload = $c->req->upload($k);
        unless(defined($childupload)){
          unshift @{$res->{alerts}}, { type => 'danger', msg => "Missing container member file [$k]"};
          $res->{status} = 400;
          return $res;
        }
        my $size = $childupload->size;
        my $name = $childupload->filename;
        $c->app->log->debug("Found file: $name [$size B]");
        my $childmetadata = $metadata->{metadata}->{'json-ld'}->{$k};
        my $mt;
        for my $mtam (@{$childmetadata->{'ebucore:hasMimeType'}}){
          $mt = $mtam;
        }

        my $childcmodel = $mime_to_cmodel{$mt};
        unless($childcmodel){
          $childcmodel = 'cmodel:Asset';
        }
        $c->app->log->debug("ebucore:hasMimeType[$mt] maps to cmodel[$childcmodel]");
        if ($childcmodel){
          my $child_metadata = { metadata => { 'json-ld' => $childmetadata } };
          if (exists($metadata->{metadata}->{'rights'})) {
            $child_metadata->{metadata}->{rights} = $metadata->{metadata}->{'rights'};
          }
          #$c->app->log->debug("Creating child with metadata:".$c->app->dumper($child_metadata));
          my $r = $self->create_simple($c, $childcmodel, $child_metadata, $mt, $childupload, undef, undef, $username, $password);
          if($r->{status} ne 200){
            $res->{status} = 500;
            unshift @{$res->{alerts}}, @{$r->{alerts}};
            unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error creating child object'};
            return $res;
          }
          
          push @children, { pid => $r->{pid}, memberkey => $k };
        }
      }
    }
    for my $mk (keys %{$metadata->{metadata}}){
      if ($mk eq 'json-ld') {
        $container_metadata->{$mk} = $metadata->{metadata}->{'json-ld'}->{container};
      } else {
        if (lc($mk) ne 'rights') {
          $container_metadata->{$mk} = $metadata->{metadata}->{$mk};
        }
      }
    }
  } else {
    $container_metadata = $metadata->{metadata};
  }

  $c->app->log->debug("Creating container with metadata:".$c->app->dumper($container_metadata));
  # create parent object
  my $r = $self->create($c, 'cmodel:Container', $username, $password);
  if($r->{status} ne 200){
    $res->{status} = 500;
    unshift @{$res->{alerts}}, @{$r->{alerts}};
    unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error creating object'};
    return $res;
  }

  my $pid = $r->{pid};
  $res->{pid} = $pid;

  # save metadata	
  $r = $self->save_metadata($c, $pid, 'Container', $container_metadata, $username, $password, 1);
  if($r->{status} ne 200){
      $res->{status} = $r->{status};
  foreach my $a (@{$r->{alerts}}){
        unshift @{$res->{alerts}}, $a;
  }
      unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving metadata'};
      return $res;
  }

  #$c->app->log->info("XXX Metadata saved, adding relationships");

  # add members
  my $childrencount = scalar @children;
  if($childrencount > 0){
    my @relationships;
    for my $chpid (@children) {
      push @relationships, { predicate => "http://pcdm.org/models#hasMember", object => "info:fedora/".$chpid->{pid} };
    }
    $r = $self->add_relationships($c, $pid, \@relationships, $username, $password, 1);
    push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    $c->app->log->error("Error adding relationships[".$c->app->dumper(\@relationships)."] pid[$pid] res[".$c->app->dumper($res)."]");
      return $res;
    }
  }

  # add members rels (eg isthumbnailfor)
  if(exists($metadata->{metadata}->{'relationships'})){
    $c->app->log->debug("Found relationships: ".$c->app->dumper($metadata->{metadata}->{'relationships'}));
    foreach my $rel (@{$metadata->{metadata}->{'relationships'}}){
      if($rel->{'s'} eq "container"){
        $rel->{'s'} = $pid;
      }
      if($rel->{'o'} eq "container"){
        $rel->{'o'} = "info:fedora/".$pid;
      }
      
      if($rel->{'s'} =~ m/member_/g){
        for my $ch (@children) {
          if($ch->{memberkey} eq $rel->{'s'}){
            $rel->{'s'} = $ch->{pid};
          }
        }
      }
      
      if($rel->{'o'} =~ m/member_/g){
        for my $ch (@children) {
          if($ch->{memberkey} eq $rel->{'o'}){
            $rel->{'o'} = "info:fedora/".$ch->{pid};
          }
        }
      }
    }
    for my $rel (@{$metadata->{metadata}->{'relationships'}}){
      $c->app->log->debug("Adding relationship s[".$rel->{'s'}."] p[".$rel->{'s'}."] o[".$rel->{'o'}."]");
      $r = $self->add_relationship($c, $rel->{'s'}, $rel->{'p'}, $rel->{'o'}, $username, $password);
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      $res->{status} = $r->{status};
      if($r->{status} ne 200){
        $c->app->log->error("Error adding relationship[".$c->app->dumper($rel)."] res[".$c->app->dumper($res)."]");
        return $res;
      }
    }
  }

  # order members
  my @collectionorder;
  if(exists($metadata->{metadata}->{'membersorder'})){
    $c->app->log->debug("Found membersorder: ".$c->app->dumper($metadata->{metadata}->{'membersorder'}));
    foreach my $mem (@{$metadata->{metadata}->{'membersorder'}}){
      if($mem->{'member'} =~ m/member_/g){
        for my $ch (@children) {
          if($ch->{memberkey} eq $mem->{'member'}){
            push @collectionorder, { pid => $ch->{pid}, pos => $mem->{pos} }
          }
        }
      }
    }
    my $nrcolor = scalar @collectionorder;
    if ($nrcolor > 0) {
      my $membersorder_model = PhaidraAPI::Model::Membersorder->new;
      $c->app->log->debug("Saving collectionorder: ".$c->app->dumper(\@collectionorder));
      my $r = $membersorder_model->save_to_object($c, $pid, \@collectionorder, $username, $password);
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      $res->{status} = $r->{status};
      if($r->{status} ne 200){
        $c->app->log->error("Error ordering members collectionorder[".$c->app->dumper(\@collectionorder)."] res[".$c->app->dumper($res)."]");
        return $res;
      }
    }
  }

  # activate
  $r = $self->modify($c, $pid, 'A', undef, undef, undef, undef, $username, $password);
  if($r->{status} ne 200){
    $c->app->log->error("Error activating pid[$pid]");
    $res->{status} = $r->{status};
    foreach my $a (@{$r->{alerts}}){
      unshift @{$res->{alerts}}, $a;
    }
    unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error activating object'};
    return $res;
  }else{
    $c->app->log->info("Object successfully created pid[$pid]");
  }

   if (exists($metadata->{metadata}->{'ownerid'})) {
    $c->app->log->debug("Changing ownerid to ". $metadata->{metadata}->{'ownerid'});
    my $authorized = 0;
    if (
      ($username eq $c->app->config->{phaidra}->{intcallusername}) ||
      ($username eq $c->app->config->{phaidra}->{adminusername})
    ) {
      $authorized = 1;
    } else {
      if ($c->app->config->{authorization}) {
        if ($c->app->config->{authorization}->{canmodifyownerid}) {
          for my $user (@{$c->app->config->{authorization}->{canmodifyownerid}}) {
            if ($user eq $username) {
              $authorized = 1;
              last;
            }
          }
        }
      }
    }
    if ($authorized) {
      my $r = $self->modify($c, $pid, undef, undef, $metadata->{metadata}->{'ownerid'}, undef, undef, $username, $password, 1);
      if($r->{status} ne 200) {
        $res->{status} = $r->{status};
        foreach my $a (@{$r->{alerts}}) {
          unshift @{$res->{alerts}}, $a;
        }
        unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error modifying ownership'};
      }
    }
  }


  return $res;
}

sub add_octets {

  my $self = shift;
  my $c = shift;
  my $pid = shift;
  my $upload = shift;
  my $file = shift;
  my $mimetype = shift;
  my $checksumtype = shift;
  my $checksum = shift;

  my $res = { alerts => [], status => 200 };

  my $size = $file->size;
  my $name = $file->filename;

  $c->app->log->debug("Got file: $name [$size]");

  my %params;
  $params{controlGroup} = 'M';
  $params{dsLabel} = defined($name) ? $name : $c->app->config->{phaidra}->{defaultlabel};
  $params{mimeType} = $mimetype;
  if ($checksumtype) {
    $params{checksumType} = $checksumtype;
  }
  if ($checksum) {
    $params{checksum} = $checksum;
  }

  my $url = Mojo::URL->new;
  $url->scheme('https');
  $url->userinfo($c->stash->{basic_auth_credentials}->{username}.":".$c->stash->{basic_auth_credentials}->{password});
  $url->host($c->app->config->{phaidra}->{fedorabaseurl});
  $url->path("/fedora/objects/".$pid."/datastreams/OCTETS");
  $url->query(\%params);

  my $ua = Mojo::UserAgent->new;
  my %headers;
  $self->add_upstream_headers($c, \%headers);
  $headers{'Content-Type'} = $mimetype;

  my $postres = $ua->post($url => \%headers => form => { file => { file => $upload->asset }} )->result;
  unless($postres->is_success) {
    $c->app->log->error($postres->code . ": " . $postres->message);
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $postres->message };
	  $res->{status} =  $postres->code ? $postres->code : 500;
  }

  return $res;
}

sub save_metadata {

	my $self = shift;
	my $c = shift;
	my $pid = shift;
  my $cmodel = shift;
	my $metadata = shift;
	my $username = shift;
	my $password = shift;
	my $check_bib = shift;

	my $res = { alerts => [], status => 200 };
	$c->app->log->debug("Adding metadata");
	my $found = 0;
	my $found_bib = 0;
	foreach my $f (keys %{$metadata}){

		if(lc($f) eq "uwmetadata") {
			
			$c->app->log->debug("Adding uwmetadata");
			my $uwmetadata = $metadata->{uwmetadata};
			my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
			my $r = $metadata_model->save_to_object($c, $pid, $uwmetadata, $username, $password);
			if($r->{status} ne 200){
		   		$res->{status} = $r->{status};
					foreach my $a (@{$r->{alerts}}){
						unshift @{$res->{alerts}}, $a;
					}
					unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving uwmetadata'};
		  }
		  $found = 1;
		  $found_bib = 1;

		} elsif (lc($f) eq "mods"){
			
			$c->app->log->debug("Saving MODS for $pid");
			my $mods = $metadata->{mods};
			my $mods_model = PhaidraAPI::Model::Mods->new;
			my $xml = $mods_model->json_2_xml($c, $mods);
			my $r = $mods_model->save_to_object($c, $pid, $mods, $username, $password);
			if($r->{status} ne 200){
					$res->{status} = $r->{status};
					foreach my $a (@{$r->{alerts}}){
						unshift @{$res->{alerts}}, $a;
					}
					unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving MODS'};
			}
			$found = 1;
			$found_bib = 1;

		} elsif (lc($f) eq "rights"){

			$c->app->log->debug("Saving RIGHTS for $pid");
			my $rights = $metadata->{rights};
			my $rights_model = PhaidraAPI::Model::Rights->new;
			#my $xml = $rights_model->json_2_xml($c, $rights);
			#my $r = $self->add_datastream($c, $pid, "RIGHTS", "text/xml", undef, "Phaidra Permissions", $xml, "X", undef, undef, $username, $password);
			my $r = $rights_model->save_to_object($c, $pid, $rights, $username, $password);
		    if($r->{status} ne 200){
					$res->{status} = $r->{status};
					push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
			    unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving RGHTS datastream'};
		    }
			$found = 1;

		} elsif (lc($f) eq "geo"){

			$c->app->log->debug("Saving GEO for $pid");
			my $geo = $metadata->{geo};
			my $geo_model = PhaidraAPI::Model::Geo->new;
			#my $xml = $geo_model->json_2_xml($c, $geo);				
			#my $r = $self->add_datastream($c, $pid, "GEO", "text/xml", undef, "Georeferencing", $xml, "X", undef, undef, $username, $password);
			my $r = $geo_model->save_to_object($c, $pid, $geo, $username, $password);
			if($r->{status} ne 200){
				$res->{status} = $r->{status};
				push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
				unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving geo'};
			}
			$found = 1;

		} elsif (lc($f) eq "json-ld"){

			$c->app->log->debug("Saving JSON-LD for $pid");
      my $jsonld;
      if (defined($metadata->{'json-ld'})) {
        $jsonld = $metadata->{'json-ld'}
      } else {
        $jsonld = $metadata->{'JSON-LD'}
      }
			my $jsonld_model = PhaidraAPI::Model::Jsonld->new;
			my $r = $jsonld_model->save_to_object($c, $pid, $cmodel, $jsonld, $username, $password);
			if($r->{status} ne 200){
				$res->{status} = $r->{status};
				push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
				unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving json-ld'};
			}
			$found = 1;
			$found_bib = 1;

		} elsif (lc($f) eq "json-ld-private"){

			$c->app->log->debug("Saving JSON-LD-PRIVATE for $pid");
      my $jsonldprivate;
      if (defined($metadata->{'json-ld-private'})) {
        $jsonldprivate = $metadata->{'json-ld-private'}
      } else {
        $jsonldprivate = $metadata->{'JSON-LD-PRIVATE'}
      }
			my $jsonldprivate_model = PhaidraAPI::Model::Jsonldprivate->new;
			my $r = $jsonldprivate_model->save_to_object($c, $pid, $jsonldprivate, $username, $password);
			if ($r->{status} ne 200) {
				$res->{status} = $r->{status};
				push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
				unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving json-ld-private'};
			}
			$found = 1;
			$found_bib = 1;

    } elsif (lc($f) eq "members") {
      $found = 1;
      # noop - this was handled by coll model
    } elsif (lc($f) eq "membersorder") {
      $found = 1;
      # noop - this is handled by create_container
    } elsif (lc($f) eq "relationships") {
      $found = 1;
      # noop - this is handled elswhere
    } elsif (lc($f) eq "ownerid") {
      $found = 1;
      # noop - this is handled later because it's the last step (after activating object)
    } else {
			$c->app->log->error("Unknown or unsupported metadata format: $f");
			$found = 1;
			unshift @{$res->{alerts}}, { type => 'danger', msg => "Unknown or unsupported metadata format: $f" };
		}
		
	}

	unless($found){
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'No metadata provided' };
		$res->{status} = 400;
	}

	if(!$found_bib && $check_bib){
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'No bibliographical metadata provided' };
		$res->{status} = 400;
	}

	return $res;
}

sub get_dissemination {

	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $bdef = shift;
	my $disseminator = shift;
	my $username = shift;
	my $password = shift;

	my $res = { alerts => [], status => 200 };

	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/get/$pid/$bdef/$disseminator");

	my %headers;
  $self->add_upstream_headers($c, \%headers);

	my $get = Mojo::UserAgent->new->get($url => \%headers);

	if (my $r = $get->success) {
		$res->{status} = 200;
		$res->{content} = $r->body;
	}
	else
	{
		my ($err, $code) = $get->error;
		unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
		$res->{status} =  $code ? $code : 500;
	}

	return $res;
}


sub get_foxml {

	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $dsid = shift;

	my $res = { alerts => [], status => 200 };

	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo($c->app->config->{phaidra}->{adminusername}.':'.$c->app->config->{phaidra}->{adminpassword});
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid/objectXML");

  my %headers;
  $self->add_upstream_headers($c, \%headers);

	my $get = Mojo::UserAgent->new->get($url => \%headers);

  	if (my $r = $get->success) {
  		$res->{status} = 200;
  		$res->{foxml} = b($r->body)->decode('UTF-8');
  	}else{
	  $c->app->log->error("Error getting foxml: ". $get->error->{message});
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $get->error->{message} };
	  $res->{status} = $get->error->{code} ? $get->error->{code} : 500;
	}

	return $res;
}


# by using intcallauth it is possible to bypass the 'owner' policies
# this might be needed eg because fedora always requires authentication
# (api property, it's not because of policies)
# even for datastreams which are actually public, like DC, COLLECTIONORDER etc
sub get_datastream {

	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $dsid = shift;
	my $username = shift;
	my $password = shift;
	my $intcallauth = shift;

	my $res = { alerts => [], status => 200 };

	$c->app->log->debug("get_datastream pid[$pid] dsid[$dsid] username[$username] instcallauth[$intcallauth]");

	my $url = Mojo::URL->new;
	$url->scheme('https');

	if($intcallauth){
		$url->userinfo($c->app->config->{phaidra}->{intcallusername}.':'.$c->app->config->{phaidra}->{intcallpassword});
	}else{
		$url->userinfo("$username:$password");
	}
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid/datastreams/$dsid/content");

	my %headers;
	$self->add_upstream_headers($c, \%headers);

  my $get = Mojo::UserAgent->new->get($url => \%headers);

  if (my $r = $get->success) {
  	$res->{status} = 200;
  	$res->{$dsid} = $r->body;
  }
	else
	{
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $get->error->{message} };
	  $res->{status} = $get->error->{code} ? $get->error->{code} : 500;
	}

	return $res;
}

sub proxy_datastream {
  	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $dsid = shift;
	my $username = shift;
	my $password = shift;
	my $intcallauth = shift;

	my $res = { alerts => [], status => 200 };

	my $url = Mojo::URL->new;
	$url->scheme('https');

	if($intcallauth){
		$url->userinfo($c->app->config->{phaidra}->{intcallusername}.':'.$c->app->config->{phaidra}->{intcallpassword});
	}elsif($username){
		$url->userinfo("$username:$password");
	}

  	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
  	$url->path("/fedora/objects/$pid/datastreams/$dsid/content");

  	if (Mojo::IOLoop->is_running) {
	    $c->render_later;
	    $c->ua->get(
	      $url,
	      sub {
	        my ($self, $tx) = @_;
	        _proxy_tx($c, $tx);
	      }
	    );
  	}else {
    	my $tx = $c->ua->get($url);
    	_proxy_tx($c, $tx);
  	}
}

sub _proxy_tx {
  my ($c, $tx) = @_;
  if (my $res = $tx->success) {
    $c->tx->res($res);
    $c->tx->res->headers->content_type($tx->res->headers->content_type .'; charset=utf-8');
    $c->rendered;
  }
  else {
    my $error = $tx->error;
    $c->tx->res->headers->add('X-Remote-Status', $error->{code} . ': ' . $error->{message});
    $c->render(status => 500, text => 'Failed to fetch data from Fedora: '.$c->app->dumper($error));
  }
}

sub add_datastream {

	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $dsid = shift;
	my $mimetype = shift;
	my $location = shift;
	my $label = shift;
	my $dscontent = shift;
	my $controlgroup = shift;
  my $checksumtype = shift;
  my $checksum = shift;
	my $username = shift;
	my $password = shift;

	my $res = { alerts => [], status => 200 };

	my %params;
	unless(defined($label)){
		# the label is mandatory when adding datastream
		$label = $c->app->config->{phaidra}->{defaultlabel};
	}
  $params{controlGroup} = $controlgroup ? $controlgroup : "X";
  $params{dsLocation} = $location if $location;
  #$params{altIDs}
  $params{dsLabel} = $label;
  if(defined($datastream_versionable{$dsid})){
  	$params{versionable} = $datastream_versionable{$dsid};
  }
  $params{dsState} = 'A';
  #$params{formatURI}
  $params{checksumType} = $checksumtype ? $checksumtype : 'DISABLED';
  if ($checksum) {
    $params{checksum} = $checksum;
  }
  $params{mimeType} = $mimetype if $mimetype;
  $params{logMessage} = 'PhaidraAPI object/add_datastream';

  $c->app->log->debug("Add datastream $dsid: ".$c->app->dumper(\%params));

	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid/datastreams/$dsid");
	$url->query(\%params);

	my $ua = Mojo::UserAgent->new;

	my %headers;
  $self->add_upstream_headers($c, \%headers);
	
	my $post;
	if($dscontent){
	  if($mimetype eq 'text/xml'){
	    $dscontent = encode 'UTF-8', $dscontent;
	  }
  	  $post = $ua->post($url => \%headers =>  $dscontent)->result;
	}else{
	  $post = $ua->post($url => \%headers)->result;
	}
  if ($post->is_success) {
  	#unshift @{$res->{alerts}}, { type => 'success', msg => $r->body };
  }
	else {
		$c->app->log->error($post->code . ": " . $post->message);
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $post->message };
	  $res->{status} =  $post->code ? $post->code : 500;
	}

  return $res;
}

sub modify_datastream {

	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $dsid = shift;
	my $mimetype = shift;
	my $location = shift;
	my $label = shift;
	my $dscontent = shift;
  my $checksumtype = shift;
  my $checksum = shift;
	my $username = shift;
	my $password = shift;

	my $res = { alerts => [], status => 200 };

	my %params;
  $params{dsLocation} = $location if $location;
  #$params{altIDs}
  $params{dsLabel} = $label if $label;
	if(defined($datastream_versionable{$dsid})){
		$params{versionable} = $datastream_versionable{$dsid};
	}
  #$params{versionable} = 1;
  $params{dsState} = 'A';
  #$params{formatURI}
  $params{checksumType} = $checksumtype ? $checksumtype : 'DISABLED';
  if ($checksum) {
    $params{checksum} = $checksum;
  }
  $params{mimeType} = $mimetype if $mimetype;
  $params{logMessage} = 'PhaidraAPI object/modify_datastream';
  $params{force} = 0;

  #$c->app->log->debug("pid[$pid] dsid[$dsid] Modify datastream: ".$c->app->dumper(\%params));
  #$params{ignoreContent}
#$c->app->log->debug("XXXXXXXXXX ".$c->app->dumper(\%params));
#$username = $c->app->{config}->{phaidra}->{adminusername};
#$password = $c->app->{config}->{phaidra}->{adminpassword};

	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid/datastreams/$dsid");
	$url->query(\%params);

	my $ua = Mojo::UserAgent->new;

	my %headers;
  $self->add_upstream_headers($c, \%headers);

	my $put;
	if($dscontent){
		if($mimetype eq 'text/xml'){
		  $dscontent = encode 'UTF-8', $dscontent;
		}
  	$put = $ua->put($url => \%headers => $dscontent)->result;
	}else{
		$put = $ua->put($url => \%headers)->result;
	}

  if ($put->is_success) {
  	#unshift @{$res->{alerts}}, { type => 'success', msg => $r->body };
  } else {
	  $c->app->log->error($put->code . ": " . $put->message);
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $put->message };
	  $res->{status} =  $put->code ? $put->code : 500;
	}

  return $res;
}

sub add_or_modify_datastream {

	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $dsid = shift;
	my $mimetype = shift;
	my $location = shift;
	my $label = shift;
	my $dscontent = shift;
	my $controlgroup = shift;
  my $checksumtype = shift;
  my $checksum = shift;
	my $username = shift;
	my $password = shift;
	my $useadmin = shift;

	my $res = { alerts => [], status => 200 };

  #$c->app->log->debug("XXXXXXXXXX pid: ".$pid);
  #$c->app->log->debug("XXXXXXXXXX dsid: ".$dsid);
  #$c->app->log->debug("XXXXXXXXXX mimetype: ".$mimetype);
  #$c->app->log->debug("XXXXXXXXXX location: ".$location);
  #$c->app->log->debug("XXXXXXXXXX label: ".$label);
	#$c->app->log->debug("XXXXXXXXXX dscontent: ".$dscontent);
  #$c->app->log->debug("XXXXXXXXXX controlgroup: ".$controlgroup);
  #$c->app->log->debug("XXXXXXXXXX username: ".$username);
  #$c->app->log->debug("XXXXXXXXXX password: ".$password);
  #$c->app->log->debug("XXXXXXXXXX useadmin: ".$useadmin);

	my $search_model = PhaidraAPI::Model::Search->new;
	my $sr = $search_model->datastream_exists($c, $pid, $dsid);
	if($sr->{status} ne 200){
		unshift @{$res->{alerts}}, @{$sr->{alerts}};
		$res->{status} = $sr->{status};
		return $res;
	}

  #$c->app->log->debug("XXXXXXXXXX exists: ".$sr->{'exists'});

	if($useadmin){
		$username = $c->app->{config}->{phaidra}->{adminusername};
		$password = $c->app->{config}->{phaidra}->{adminpassword};
	}

	# save
	if($sr->{'exists'}){
		my $r = $self->modify_datastream($c, $pid, $dsid, $mimetype, $location, $label, $dscontent, $checksumtype, $checksum, $username, $password);
		push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
		$res->{status} = $r->{status};
		if($r->{status} ne 200){
			return $res;	
		}
		$c->app->log->debug("Modifying $dsid for $pid successful.");
	}else{
		my $r = $self->add_datastream($c, $pid, $dsid, $mimetype, $location, $label, $dscontent, $controlgroup, $checksumtype, $checksum, $username, $password);
		push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
		$res->{status} = $r->{status};
		if($r->{status} ne 200){
			return $res;
		}
		$c->app->log->debug("Adding $dsid for $pid successful.");
	}

	my $hooks_model = PhaidraAPI::Model::Hooks->new;
	my $hr = $hooks_model->add_or_modify_datastream_hooks($c, $pid, $dsid, $dscontent, $username, $password);
	push @{$res->{alerts}}, @{$hr->{alerts}} if scalar @{$hr->{alerts}} > 0;
	$res->{status} = $hr->{status};
	if($hr->{status} ne 200){
		return $res;
	}

	return $res
}

sub create_empty {

	my $self = shift;
    my $c = shift;
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };

    $username = xml_escape $username;

    my %params;
    my $label = $c->app->config->{phaidra}->{defaultlabel};
    $params{label} = $label;
    $params{format} = 'info:fedora/fedora-system:FOXML-1.1';
    $params{ownerId} = $username;
    $params{logMessage} = 'PhaidraAPI object/create_empty';

	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/new");
	$url->query(\%params);

	# have to sent xml, because without the foxml fedora creates a default empty object
	# but this is then automatically 'Active'!
	# http://www.fedora-commons.org/documentation/3.0/userdocs/server/webservices/apim/#methods.ingest
	my $foxml = qq|<?xml version="1.0" encoding="UTF-8"?>
<foxml:digitalObject VERSION="1.1" xmlns:foxml="info:fedora/fedora-system:def/foxml#" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="info:fedora/fedora-system:def/foxml# http://www.fedora.info/definitions/1/0/foxml1-1.xsd">
        <foxml:objectProperties>
                <foxml:property NAME="info:fedora/fedora-system:def/model#state" VALUE="Inactive"/>
                <foxml:property NAME="info:fedora/fedora-system:def/model#label" VALUE="$label"/>
                <foxml:property NAME="info:fedora/fedora-system:def/model#ownerId" VALUE="$username"/>
        </foxml:objectProperties>
</foxml:digitalObject>
|;

	my $pid;
	my $ua = Mojo::UserAgent->new;

	my %headers;
  $self->add_upstream_headers($c, \%headers);
  $headers{'Content-Type'} = 'text/xml';

  	my $put = $ua->post($url => \%headers => $foxml);
  	if (my $r = $put->success) {
  		$res->{pid} = $r->body;
  	}else {
	  my ($err, $code) = $put->error;
	  $c->app->log->error("Cannot create fedora object: code:".$err->{code}." message:".$err->{message});
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err->{message} };
	  $res->{status} =  $err->{code} ? $err->{code} : 500;
	  return $res;
	}



	return $res;
}

sub add_relationship {

	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $predicate = shift;
    my $object = shift;
    my $username = shift;
    my $password = shift;
    my $skiphook = shift;

    my $res = { alerts => [], status => 200 };

    # only allow if object's owner is subject's owner
    if ($predicate eq 'http://pcdm.org/models#hasMember') {
      my $objectPid = $object;
      $objectPid =~ s/info:fedora\///;
      my $search_model = PhaidraAPI::Model::Search->new;
      my $owr = $search_model->get_ownerid($c, $objectPid);
      if ($owr->{status} ne 200) {
        unshift @{$res->{alerts}}, @{$owr->{alerts}};
        $res->{status} =  500;
        return $res;
      }
      my $objectOwner = $owr->{ownerid};
      $objectOwner =~ s/"//g;
      $c->app->log->debug("adding hasMember check: memberOwner[$objectOwner] username[$username]");
      if (($username ne $c->app->config->{phaidra}->{adminusername}) && ($username ne $objectOwner)) {
        unshift @{$res->{alerts}}, { type => 'danger', msg => 'Forbidden' };
        $res->{status} =  403;
        return $res;
      }
    }

    if($c->app->config->{fedora}->{version} eq '3.8'){
    	my %params;
	    $params{subject} = 'info:fedora/'.$pid;
	    $params{predicate} = $predicate;
	    $params{object} = $object;

	    my $url = Mojo::URL->new;
      $url->scheme('https');
      $url->userinfo("$username:$password");
      $url->host($c->app->config->{phaidra}->{fedorabaseurl});
      $url->path("/fedora/objects/$pid/relationships/new");
      $url->query(\%params);

	    my $ua = Mojo::UserAgent->new;
	  	my $post = $ua->post($url);
	  	if (my $r = $post->success) {
	  		unshift @{$res->{alerts}}, { type => 'success', msg => $r->body };
	  	}else {
		  my ($err, $code) = $post->error;
		  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
		  $res->{status} =  $code ? $code : 500;
		}
	}else{

	  $c->app->log->debug("Connecting to ".$c->app->config->{phaidra}->{fedorabaseurl}."...");
		my $phaidra = Phaidra::API->new(
			$c->app->config->{phaidra}->{fedorabaseurl},
			$c->app->config->{phaidra}->{staticbaseurl},
			$c->app->config->{phaidra}->{fedorastylesheeturl},
			$c->app->config->{phaidra}->{proaiRepositoryIdentifier},
			$username,
			$password
		);

		my $soap = $phaidra->getSoap("apim");
		unless(defined($soap)){
			unshift @{$res->{alerts}}, { type => 'danger', msg => 'Cannot create SOAP connection to '.$c->app->config->{phaidra}->{fedorabaseurl}};
			$res->{status} = 500;
			return $res;
		}
		#$c->app->log->debug("Connected");
		my $soapres = $soap->addRelationship($pid, SOAP::Data->type(string => $predicate), SOAP::Data->type(string => $object), SOAP::Data->type(boolean => 0), undef);

		if($soapres->fault)
		{
			$c->app->log->error("Adding relationships for $pid failed: ".$soapres->faultcode.": ".$soapres->faultstring);
			$res->{status} = 500;
			unshift @{$res->{alerts}}, { type => 'danger', msg => "Adding relationships for $pid failed: ".$soapres->faultcode.": ".$soapres->faultstring};
			return $res;
		}
	}

	unless($skiphook){
		my $hooks_model = PhaidraAPI::Model::Hooks->new;
		my $hr = $hooks_model->add_or_modify_relationships_hooks($c, $pid, $username, $password);
		push @{$res->{alerts}}, @{$hr->{alerts}} if scalar @{$hr->{alerts}} > 0;
		$res->{status} = $hr->{status};
		if($hr->{status} ne 200){
			return $res;
		}
	}

  	return $res;
}

sub add_relationships {

	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $relationships = shift;
    my $username = shift;
    my $password = shift;
    my $skiphook = shift;

    my $res = { alerts => [], status => 200 };

    for my $rel (@$relationships){
    	my $rr = $self->add_relationship($c, $pid, $rel->{predicate}, $rel->{object}, $username, $password, 1);
    	if($rr->{status} ne 200){
			$res = $rr;
    		last;
    	}
    }
    
    unless($skiphook){
      my $hooks_model = PhaidraAPI::Model::Hooks->new;
      my $hr = $hooks_model->add_or_modify_relationships_hooks($c, $pid, $username, $password);
      push @{$res->{alerts}}, @{$hr->{alerts}} if scalar @{$hr->{alerts}} > 0;
      $res->{status} = $hr->{status};
      if($hr->{status} ne 200){
        return $res;
      }
	}

  	return $res;
}

sub purge_relationship {

	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $predicate = shift;
    my $object = shift;
    my $username = shift;
    my $password = shift;
    my $skiphook = shift;

    my $res = { alerts => [], status => 200 };
   
    if($c->app->config->{fedora}->{version} eq '3.8'){

      my %params;
      $params{subject} = 'info:fedora/'.$pid;
      $params{predicate} = $predicate;
      $params{object} = $object;

      my $url = Mojo::URL->new;
      $url->scheme('https');
      $url->userinfo("$username:$password");
      $url->host($c->app->config->{phaidra}->{fedorabaseurl});
      $url->path("/fedora/objects/$pid/relationships");
      $url->query(\%params);

	    my $ua = Mojo::UserAgent->new;
	  	my $postres = $ua->delete($url)->result;
	  	if ($postres->is_error) {
	  		unshift @{$res->{alerts}}, { type => 'danger', msg => $postres->message };
	      $res->{status} =  $postres->{code} ? $postres->{code} : 500;
	  	}

    }else{

	    $c->app->log->debug("Connecting to ".$c->app->config->{phaidra}->{fedorabaseurl}."...");
		my $phaidra = Phaidra::API->new(
			$c->app->config->{phaidra}->{fedorabaseurl},
			$c->app->config->{phaidra}->{staticbaseurl},
			$c->app->config->{phaidra}->{fedorastylesheeturl},
			$c->app->config->{phaidra}->{proaiRepositoryIdentifier},
			$username,
			$password
		);

		my $soap = $phaidra->getSoap("apim");
		unless(defined($soap)){
			unshift @{$res->{alerts}}, { type => 'danger', msg => 'Cannot create SOAP connection to '.$c->app->config->{phaidra}->{fedorabaseurl}};
			$res->{status} = 500;
			return $res;
		}
		#$c->app->log->debug("Connected");
		my $soapres = $soap->purgeRelationship($pid, SOAP::Data->type(string => $predicate), SOAP::Data->type(string => $object), SOAP::Data->type(boolean => 0), undef);

		if($soapres->fault)
		{
			$c->app->log->error("Removing relationships for $pid failed:".$soapres->faultcode.": ".$soapres->faultstring);
			$res->{status} = 500;
			unshift @{$res->{alerts}}, { type => 'danger', msg => "Removing relationship for $pid failed:".$soapres->faultcode.": ".$soapres->faultstring};
			return $res;
		}
	}

	unless($skiphook){
		my $hooks_model = PhaidraAPI::Model::Hooks->new;
		my $hr = $hooks_model->add_or_modify_relationships_hooks($c, $pid, $username, $password);
		push @{$res->{alerts}}, @{$hr->{alerts}} if scalar @{$hr->{alerts}} > 0;
		$res->{status} = $hr->{status};
		if($hr->{status} ne 200){
			return $res;
		}
	}

  	return $res;
}


# this method is our hack in 3.3
sub purge_relationships {

	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $relationships = shift;
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };

    for my $rel (@$relationships){
    	my $rr = $self->purge_relationship($c, $pid, $rel->{predicate}, $rel->{object}, $username, $password, 1);
    	if($rr->{status} ne 200){
			  $res = $rr;
    		last;
    	}
    }
    
    my $hooks_model = PhaidraAPI::Model::Hooks->new;
    my $hr = $hooks_model->add_or_modify_relationships_hooks($c, $pid, $username, $password);
    # only overwrite res if there was nothing interesting in it
    if(($res->{status} == 200) && ($hr->{status} ne 200)){
      push @{$res->{alerts}}, @{$hr->{alerts}} if scalar @{$hr->{alerts}} > 0;
      $res->{status} = $hr->{status};
    }

  	return $res;
}


sub set_rights {
	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $rights = shift;
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };

  	return $res;
}

1;
__END__
