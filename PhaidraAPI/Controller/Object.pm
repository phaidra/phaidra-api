package PhaidraAPI::Controller::Object;

use strict;
use warnings;
use v5.10;
use Switch;
use base 'Mojolicious::Controller';
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(encode decode);
use Mojo::ByteStream qw(b);
use Mojo::Upload;
use Mojo::Path;
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Collection;
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Rights;
use PhaidraAPI::Model::Octets;
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Geo;
use PhaidraAPI::Model::Mods;
use PhaidraAPI::Model::Imageserver;
use PhaidraAPI::Model::Util;
use PhaidraAPI::Model::Authorization;
use PhaidraAPI::Model::Languages;
use Digest::SHA qw(hmac_sha1_hex);
use Time::HiRes qw/tv_interval gettimeofday/;
use File::Find::utf8;

sub mint_pid {
  my $self = shift;

  my $res = {alerts => [], status => 200};
  my $dbh = $self->app->db_fedora->dbh;
  $dbh->do("UPDATE pidGen SET highestID = LAST_INSERT_ID(highestID) + 1 WHERE namespace = '" . $self->app->config->{fedora}->{pidnamespace} . "';");
  my $highestID = $dbh->last_insert_id(undef, undef, 'pidGen', 'highestID');
  $highestID++;
  my $pid = $self->app->config->{fedora}->{pidnamespace} . ':' . $highestID;
  if (my $msg = $dbh->errstr) {
    $self->app->log->error($msg);
    $res->{status} = 500;
    unshift @{$res->{alerts}}, {type => 'danger', msg => $msg};
    return $res;
  }

  $self->render(json => {pid => $pid}, status => $res->{status});
}

sub info {
  my $self = shift;

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $mode = $self->param('mode');

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r            = $object_model->info($self, $self->stash('pid'), $mode, $username, $password);

  $self->render(json => $r, status => $r->{status});
}

sub imageserver_job_status {
  my $self = shift;
  my $pid  = shift;

  if (exists($self->app->config->{paf_mongodb})) {
    my $jobs_coll = $self->paf_mongo->get_collection('jobs');
    if ($jobs_coll) {
      my $job_record = $jobs_coll->find_one({pid => $pid, agent => 'pige'}, {}, {"sort" => {"created" => -1}});
      return $job_record->{status};
    }
  }

  return 'job not found';
}

sub get_is_thumbnail_for {
  my $self = shift;
  my $pid  = shift;

  my $urlget = Mojo::URL->new;
  $urlget->scheme($self->app->config->{solr}->{scheme});
  $urlget->host($self->app->config->{solr}->{host});
  $urlget->port($self->app->config->{solr}->{port});
  if ($self->app->config->{solr}->{path}) {
    $urlget->path("/" . $self->app->config->{solr}->{path} . "/solr/" . $self->app->config->{solr}->{core} . "/select");
  }
  else {
    $urlget->path("/solr/" . $self->app->config->{solr}->{core} . "/select");
  }
  $urlget->query(q => "*:*", fq => "isthumbnailfor:\"$pid\"", rows => "1", wt => "json");
  my $ua     = Mojo::UserAgent->new;
  my $getres = $ua->get($urlget)->result;
  if ($getres->is_success) {
    for my $d (@{$getres->json->{response}->{docs}}) {
      $self->app->log->info($d->{pid} . " is thumbnail for $pid");
      return $d->{pid};
    }
  }
  else {
    $self->app->log->debug("error searching for isthumbnailfor: " . $getres->code . " " . $getres->message);
  }
}

sub thumbnail {
  my $self = shift;

  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }
  my $pid = $self->stash('pid');

  my $w = $self->param('w');
  my $h = $self->param('h');
  if (!$w and !$h) {
    $w = 120;
  }

  my $thumbPid = $self->get_is_thumbnail_for($pid);
  if ($thumbPid) {
    $pid = $thumbPid;
  }

  my $authz_model = PhaidraAPI::Model::Authorization->new;
  my $res         = $authz_model->check_rights($self, $pid, 'ro');
  unless ($res->{status} eq '200') {
    $self->reply->static('images/locked.png');
    return;
  }

  my $search_model = PhaidraAPI::Model::Search->new;
  my $cmodelr      = $search_model->get_cmodel($self, $pid);
  if ($cmodelr->{status} ne 200) {
    $self->app->log->error("pid[$pid] could not get cmodel");
    $self->reply->static('images/error.png');
    return;
  }

  switch ($cmodelr->{cmodel}) {
    case ['Picture', 'Page', 'PDFDocument'] {
      if ($self->imageserver_job_status($pid) eq 'finished') {

        # use imageserver
        my $size       = "!$w,$h";
        my $isrv_model = PhaidraAPI::Model::Imageserver->new;
        my $res        = $isrv_model->get_url($self, Mojo::Parameters->new(IIIF => "$pid.tif/full/$size/0/default.jpg"), 0);
        if ($res->{status} ne 200) {
          $self->render(json => $res, status => $res->{status});
          return;
        }
        $self->render_later;
        $self->ua->get($res->{url} => sub {my ($ua, $tx) = @_; $self->tx->res($tx->res); $self->rendered;});
        return;
      }
      else {
        switch ($cmodelr->{cmodel}) {
          case 'Picture' {
            $self->reply->static('images/image.png');
            return;
          }
          case 'Page' {
            $self->reply->static('images/document.png');
            return;
          }
          case 'PDFDocument' {
            $self->reply->static('images/document.png');
            return;
          }
        }
      }
    }
    case 'Book' {
      my $index_model = PhaidraAPI::Model::Index->new;
      my $docres      = $index_model->get_doc($self, $pid);
      if ($docres->{status} ne 200) {
        $self->app->log->error("pid [$pid] error searching for firstpage: " . $self->app->dumper($docres));
        $self->reply->static('images/error.png');
        return;
      }
      my $firstpage;
      if (exists($docres->{doc}->{firstpage})) {
        $firstpage = $docres->{doc}->{firstpage};
      }
      if ($firstpage) {
        if ($self->imageserver_job_status($firstpage) eq 'finished') {
          my $size       = "!$w,$h";
          my $isrv_model = PhaidraAPI::Model::Imageserver->new;
          my $res        = $isrv_model->get_url($self, Mojo::Parameters->new(IIIF => "$firstpage.tif/full/$size/0/default.jpg"), 0);
          if ($res->{status} ne 200) {
            $self->render(json => $res, status => $res->{status});
            return;
          }
          $self->render_later;
          $self->ua->get($res->{url} => sub {my ($ua, $tx) = @_; $self->tx->res($tx->res); $self->rendered;});
          return;
        }
        else {
          $self->reply->static('images/book.png');
          return;
        }
      }
      else {
        $self->reply->static('images/book.png');
        return;
      }
    }
    case 'Video' {
      $self->reply->static('images/video.png');
      return;
    }
    case 'Audio' {
      $self->reply->static('images/audio.png');
      return;
    }
    case 'Container' {
      $self->reply->static('images/container.png');
      return;
    }
    case 'Collection' {
      $self->reply->static('images/collection.png');
      return;
    }
    case 'Resource' {
      $self->reply->static('images/resource.png');
      return;
    }
    case 'Asset' {
      $self->reply->static('images/asset.png');
      return;
    }
  }

  $self->app->log->error("pid[$pid] oops!");
  $self->reply->static('images/error.png');
}

sub preview {
  my $self = shift;

  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }
  my $pid = $self->stash('pid');

  my $force = $self->param('force');

  my $authz_model = PhaidraAPI::Model::Authorization->new;
  my $resro       = $authz_model->check_rights($self, $pid, 'ro');
  unless ($resro->{status} eq '200') {
    $self->reply->static('images/locked.png');
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r_oxml       = $object_model->get_foxml($self, $pid);
  if ($r_oxml->{status} ne 200) {
    $self->render(json => $r_oxml, status => $r_oxml->{status});
    return;
  }
  my $foxmldom = Mojo::DOM->new();
  $foxmldom->xml(1);
  $foxmldom->parse($r_oxml->{foxml});

  my $relsext;
  for my $e ($foxmldom->find('foxml\:datastream[ID="RELS-EXT"]')->each) {
    $relsext = $e->find('foxml\:datastreamVersion')->first;
    for my $e1 ($e->find('foxml\:datastreamVersion')->each) {
      if ($e1->attr('CREATED') gt $relsext->attr('CREATED')) {
        $relsext = $e1;
      }
    }
  }
  my $cmodel = $relsext->find('foxml\:xmlContent')->first->find('hasModel')->first->attr('rdf:resource');
  $cmodel =~ s/^info:fedora\/cmodel:(.*)$/$1/;

  # we need mimetype for the audio/viedo player and size (either octets or webversion) to know if to use load button
  my $octets_model = PhaidraAPI::Model::Octets->new;
  my ($filename, $mimetype, $size);

  my $trywebversion = 0;
  if ($foxmldom->find('foxml\:datastream[ID="WEBVERSION"]')->first) {
    $trywebversion = 1;
    ($filename, $mimetype, $size) = $octets_model->_get_ds_attributes($self, $pid, 'WEBVERSION', $foxmldom);
  }
  else {
    ($filename, $mimetype, $size) = $octets_model->_get_ds_attributes($self, $pid, 'OCTETS', $foxmldom);
  }

  my $showloadbutton = 0;
  unless ($force) {
    if ($size) {
      my $limit = 10000000;
      if (exists($self->config->{preview_size_limit})) {
        $limit = $self->config->{preview_size_limit};
      }
      if ($size > $limit) {
        $showloadbutton = 1;
      }
    }
  }

  $self->app->log->info("preview pid[$pid] force[$force] cmodel[$cmodel] mimetype[$mimetype] size[$size] showloadbutton[$showloadbutton]");

  switch ($cmodel) {
    case ['Picture', 'Page'] {
      my $imgsrvjobstatus = $self->imageserver_job_status($pid);
      if ($imgsrvjobstatus eq 'finished') {
        my $license     = '';
        my $index_model = PhaidraAPI::Model::Index->new;
        my $docres;
        if (($cmodel eq 'Page') and ($self->app->config->{solr}->{core_pages})) {
          $docres = $index_model->get_page_doc($self, $pid);
        }
        else {
          $docres = $index_model->get_doc($self, $pid);
        }
        if ($docres->{status} ne 200) {
          $self->app->log->error("pid[$pid] error searching for doc: " . $self->app->dumper($docres));
          $self->reply->static('images/error.png');
          return;
        }
        for my $l (@{$docres->{doc}->{dc_license}}) {
          $license = $l;
        }

        $self->stash(rights => '');
        if ($resro->{status} eq '200') {
          $self->stash(rights => 'ro');
        }
        my $resrw = $authz_model->check_rights($self, $pid, 'rw');
        if ($resrw->{status} eq '200') {
          $self->stash(rights => 'rw');
        }

        $self->stash(annotations_json => '');
        if ($docres->{doc}->{annotations_json} != '') {
          $self->stash(annotations_json => @{$docres->{doc}->{annotations_json}}[0]);
        }

        $self->stash(baseurl  => $self->config->{baseurl});
        $self->stash(basepath => $self->config->{basepath});
        $self->stash(pid      => $pid);
        $self->stash(license  => $license);
        $self->render(template => 'utils/imageviewer', format => 'html');
        return;
      }
      else {
        $self->render(text => "imageserver job status: " . $imgsrvjobstatus, status => 200);
        return;
      }
    }
    case ['Book'] {
      my $index_model = PhaidraAPI::Model::Index->new;
      my $docres      = $index_model->get_doc($self, $pid);
      if ($docres->{status} ne 200) {
        $self->app->log->error("pid[$pid] error searching for doc: " . $self->app->dumper($docres));
        $self->reply->static('images/error.png');
        return;
      }

      $self->stash(baseurl  => $self->config->{baseurl});
      $self->stash(basepath => $self->config->{basepath});
      $self->stash(pid      => $pid);
      $self->render(template => 'utils/bookviewer', format => 'html');
      return;
    }
    case 'PDFDocument' {
      if ($showloadbutton) {
        $self->render(template => 'utils/loadbutton', format => 'html');
        return;
      }
      $self->stash(baseurl       => $self->config->{baseurl});
      $self->stash(basepath      => $self->config->{basepath});
      $self->stash(trywebversion => $trywebversion);
      $self->stash(pid           => $pid);
      $self->render(template => 'utils/pdfviewer', format => 'html');
      return;
    }
    case 'Asset' {

      my $index_model = PhaidraAPI::Model::Index->new;
      my $docres      = $index_model->get_doc($self, $pid);
      if ($docres->{status} ne 200) {
        $self->app->log->error("pid[$pid] error searching for doc: " . $self->app->dumper($docres));
        $self->reply->static('images/error.png');
        return;
      }

      # the mimetype in index can be coming from metadata too
      my $index_mime;
      for my $mt (@{$docres->{doc}->{dc_format}}) {
        $index_mime = $mt if $mt =~ m/\//g;
      }
      $self->app->log->info("preview pid[$pid] metadata mimetype[$index_mime]");
      if (($index_mime eq 'model/ply') || ($index_mime eq 'model/nxz')) {
        if ($showloadbutton) {
          $self->render(template => 'utils/loadbutton', format => 'html');
          return;
        }
        $self->stash(baseurl  => $self->config->{baseurl});
        $self->stash(basepath => $self->config->{basepath});
        $self->stash(pid      => $pid);
        $self->stash(mType    => 'ply')   if $index_mime eq 'model/ply';
        $self->stash(mType    => 'nexus') if $index_mime eq 'model/nxz';
        $self->render(template => 'utils/3dviewer', format => 'html');
        return;
      }
      else {
        $self->reply->static('images/asset.png');
        return;
      }
    }
    case 'Video' {
      if ($self->config->{streaming}) {

        my $u_model = PhaidraAPI::Model::Util->new;
        my $r       = $u_model->get_video_key($self, $pid);
        if ($r->{status} eq 200) {
          my $trackpid;
          my $tracklabel;
          my $tracklanguage;

          # check if there isn't a track object
          my $index_model = PhaidraAPI::Model::Index->new;
          my $docres      = $index_model->get_doc($self, $pid);
          if ($docres->{status} ne 200) {
            $self->app->log->error("pid[$pid] error searching for doc: " . $self->app->dumper($docres));
          }
          else {
            for my $tpid (@{$docres->{doc}->{hastrack}}) {
              $self->app->log->info("pid[$pid] found track object: $tpid");
              $trackpid = $tpid;
              my $trackdocres = $index_model->get_doc($self, $trackpid);
              if ($trackdocres->{status} ne 200) {
                $self->app->log->error("pid[$pid] error searching for doc trackpid[$trackpid]: " . $self->app->dumper($docres));
              }
              else {
                for my $ttit (@{$trackdocres->{doc}->{dc_title}}) {
                  $tracklabel = $ttit;
                  last;
                }

                # pretend you don't see this
                my $lang_model   = PhaidraAPI::Model::Languages->new;
                my %iso6393ToBCP = reverse %{$lang_model->get_iso639map()};
                for my $lng3 (@{$trackdocres->{doc}->{dc_language}}) {
                  $tracklanguage = exists($iso6393ToBCP{$lng3}) ? $iso6393ToBCP{$lng3} : $lng3;
                  last;
                }
              }
            }
          }

          $self->stash(baseurl           => $self->config->{baseurl});
          $self->stash(basepath          => $self->config->{basepath});
          $self->stash(video_key         => $r->{video_key});
          $self->stash(errormsg          => $r->{errormsq});
          $self->stash(server            => $self->config->{streaming}->{server});
          $self->stash(server_rtmp       => $self->config->{streaming}->{server_rtmp});
          $self->stash(server_cd         => $self->config->{streaming}->{server_cd});
          $self->stash(streamingbasepath => $self->config->{streaming}->{basepath});
          $self->stash(trackpid          => $trackpid);
          $self->stash(tracklabel        => $tracklabel);
          $self->stash(tracklanguage     => $tracklanguage);

          $self->render(template => 'utils/streamingplayer', format => 'html');
          return;
        }
        else {
          $self->app->log->error("Video key not available: " . $self->app->dumper($r));
          $self->render(text => $self->app->dumper($r), status => $r->{status});
          return;
        }
      }
      else {
        if ($showloadbutton) {
          $self->render(template => 'utils/loadbutton', format => 'html');
          return;
        }
        $self->stash(baseurl       => $self->config->{baseurl});
        $self->stash(basepath      => $self->config->{basepath});
        $self->stash(trywebversion => $trywebversion);
        $self->stash(mimetype      => $mimetype);
        $self->stash(pid           => $pid);
        my $thumbPid = $self->get_is_thumbnail_for($pid);
        if ($thumbPid) {
          $self->stash(thumbpid => $pid);
        }
        $self->render(template => 'utils/videoplayer', format => 'html');
        return;
      }
      return;
    }
    case 'Audio' {
      if ($showloadbutton) {
        $self->render(template => 'utils/loadbutton', format => 'html');
        return;
      }
      $self->stash(baseurl       => $self->config->{baseurl});
      $self->stash(basepath      => $self->config->{basepath});
      $self->stash(trywebversion => $trywebversion);
      $self->stash(mimetype      => $mimetype);
      $self->stash(pid           => $pid);
      my $thumbPid = $self->get_is_thumbnail_for($pid);
      if ($thumbPid) {
        $self->stash(thumbpid => $pid);
      }
      $self->render(template => 'utils/audioplayer', format => 'html');
      return;
    }
    else {
      my $thumbPid = $self->get_is_thumbnail_for($pid);
      if ($thumbPid) {
        if ($self->imageserver_job_status($thumbPid) eq 'finished') {
          my $size       = "!480,480";
          my $isrv_model = PhaidraAPI::Model::Imageserver->new;
          my $resis      = $isrv_model->get_url($self, Mojo::Parameters->new(IIIF => "$thumbPid.tif/full/$size/0/default.jpg"), 0);
          if ($resis->{status} ne 200) {
            $self->render(json => $resis, status => $resis->{status});
            return;
          }
          $self->render_later;
          $self->ua->get($resis->{url} => sub {my ($ua, $tx) = @_; $self->tx->res($tx->res); $self->rendered;});
          return;
        }
      }
      else {
        switch ($cmodel) {
          case 'Container' {
            $self->reply->static('images/container.png');
            return;
          }
          case 'Collection' {
            $self->reply->static('images/collection.png');
            return;
          }
          case 'Resource' {
            $self->reply->static('images/resource.png');
            return;
          }
        }
      }
    }
  }
  $self->reply->exception("pid[$pid] internal error");
}

sub delete {
  my $self = shift;

  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r            = $object_model->delete($self, $self->stash('pid'), $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  $self->render(json => $r, status => $r->{status});
}

sub modify {
  my $self = shift;

  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $state            = $self->param('state');
  my $label            = $self->param('label');
  my $ownerid          = $self->param('ownerid');
  my $logmessage       = $self->param('logmessage');
  my $lastmodifieddate = $self->param('lastmodifieddate');

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r            = $object_model->modify($self, $self->stash('pid'), $state, $label, $ownerid, $logmessage, $lastmodifieddate, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  $self->render(json => $r, status => $r->{status});
}

sub get_state {
  my $self = shift;

  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $r;
  if ($self->param('foxml')) {
    my $object_model = PhaidraAPI::Model::Object->new;
    $r = $object_model->get_state($self, $self->stash('pid'));
  }
  else {
    my $search_model = PhaidraAPI::Model::Search->new;
    $r = $search_model->get_state($self, $self->stash('pid'));
  }

  $self->render(json => $r, status => $r->{status});
}

sub get_cmodel {
  my $self = shift;

  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $search_model = PhaidraAPI::Model::Search->new;
  my $r            = $search_model->get_cmodel($self, $self->stash('pid'));

  $self->render(json => $r, status => $r->{status});
}

sub create {
  my $self = shift;

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r            = $object_model->create($self, $self->stash('cmodel'), $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  $self->render(json => $r, status => $r->{status});
}

sub create_empty {
  my $self = shift;

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r            = $object_model->create_empty($self, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  $self->render(json => $r, status => $r->{status});
}

sub create_simple {

  my $self = shift;

  my $res = {alerts => [], status => 200};

  my $object_model = PhaidraAPI::Model::Object->new;

  if ($self->req->is_limit_exceeded) {
    $self->app->log->debug("Size limit exceeded. Current max_message_size:" . $self->req->max_message_size);
    $self->render(json => {alerts => [{type => 'danger', msg => 'File is too big'}]}, status => 400);
    return;
  }

  # $self->app->log->debug("XXXXXXXXXXXXXXXXXXXXXXXXX ".$self->app->dumper($self->req));

  my $metadata = $self->param('metadata');
  unless ($metadata) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'No metadata sent.'}]}, status => 400);
    return;
  }

  eval {
    if (ref $metadata eq 'Mojo::Upload') {
      $self->app->log->debug("Metadata sent as file param");
      $metadata = $metadata->asset->slurp;
      $self->app->log->debug("parsing json");
      $metadata = decode_json($metadata);
    }
    else {
      # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
      $self->app->log->debug("parsing json");
      $metadata = decode_json(b($metadata)->encode('UTF-8'));
    }
  };

  if ($@) {
    $self->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, {type => 'danger', msg => $@};
    $res->{status} = 400;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my $mimetype = $self->param('mimetype');
  my $upload   = $self->req->upload('file');
  unless ($upload) {
    my $pullupload = $self->param('pullupload');
    if ($pullupload) {
      if (!$self->app->config->{'pullupload'}) {
        $self->app->log->error("Error: pullupload sent [$pullupload] but pullupload [" . $self->app->config->{'pullupload'} . "] was not configured.");
        unshift @{$res->{alerts}}, {type => 'danger', msg => $@};
        $res->{status} = 400;
        $self->render(json => $res, status => $res->{status});
        return;
      }

      for my $rule (@{$self->app->config->{'pullupload'}}) {
        if ($rule->{username} eq $self->stash->{basic_auth_credentials}->{username}) {
          $self->directory->authenticate($self, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
          my $res = $self->stash('phaidra_auth_result');
          unless (($res->{status} eq 200)) {
            $self->app->log->info("User " . $self->stash->{basic_auth_credentials}->{username} . " not authenticated (pullupload)");
            $self->render(json => {status => $res->{status}, alerts => $res->{alerts}}, status => $res->{status});
            return;
          }
          $self->app->log->info("User " . $self->stash->{basic_auth_credentials}->{username} . " successfully authenticated (pullupload)");

          $pullupload = $rule->{folder} . '/' . $pullupload;

          my @files;
          my $start_dir = $rule->{folder};
          find(sub {push @files, $File::Find::name unless -d;}, $start_dir);
          my $foundfile;
          for my $file (@files) {
            if ($pullupload eq $file) {
              $foundfile = $file;
            }
          }
          if ($foundfile) {
            if (-r $pullupload) {
              my $fileAssset = Mojo::Asset::File->new(path => $pullupload);
              $upload = Mojo::Upload->new;
              $upload->asset($fileAssset);
              my $pulluploadPath = Mojo::Path->new($pullupload);
              my @parts          = @{$pulluploadPath->parts};
              my $filename       = $parts[-1];
              $upload->filename($filename);
            }
            else {
              $self->app->log->error("Error: pullupload [$pullupload] not readable.");
              unshift @{$res->{alerts}}, {type => 'danger', msg => $@};
              $res->{status} = 400;
              $self->render(json => $res, status => $res->{status});
              return;
            }
            unless ($mimetype) {
              $mimetype = $object_model->get_mimetype($self, $upload->asset);
              $self->app->log->info("Undefined mimetype, using magic: $mimetype");
            }
          }
          else {
            $self->app->log->error("Error: pullupload [$pullupload] not found.");
            unshift @{$res->{alerts}}, {type => 'danger', msg => $@};
            $res->{status} = 400;
            $self->render(json => $res, status => $res->{status});
            return;
          }
        }
      }
    }
  }
  my $checksumtype = $self->param('checksumtype');
  my $checksum     = $self->param('checksum');

  my $r = $object_model->create_simple($self, $self->stash('cmodel'), $metadata, $mimetype, $upload, $checksumtype, $checksum, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if ($r->{status} ne 200) {
    $res->{status} = $r->{status};
    foreach my $a (@{$r->{alerts}}) {
      unshift @{$res->{alerts}}, $a;
    }

    unshift @{$res->{alerts}}, {type => 'danger', msg => 'Error creating ' . $self->stash('cmodel') . ' object'};
    $self->render(json => $res, status => $res->{status});
    return;
  }

  foreach my $a (@{$r->{alerts}}) {
    unshift @{$res->{alerts}}, $a;
  }
  $res->{status} = $r->{status};
  $res->{pid}    = $r->{pid};

  $self->render(json => $res, status => $res->{status});
}

sub create_container {

  my $self = shift;

  my $res = {alerts => [], status => 200};

  $self->app->log->debug("=== params ===");
  for my $pn (@{$self->req->params->names}) {
    $self->app->log->debug($pn);
  }
  for my $up (@{$self->req->uploads}) {
    $self->app->log->debug($up->{name} . ": " . $up->{filename});
  }
  $self->app->log->debug("==============");

  if ($self->req->is_limit_exceeded) {
    $self->app->log->debug("Size limit exceeded. Current max_message_size:" . $self->req->max_message_size);
    $self->render(json => {alerts => [{type => 'danger', msg => 'File is too big'}]}, status => 400);
    return;
  }

  my $metadata = $self->param('metadata');
  unless ($metadata) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'No metadata sent.'}]}, status => 400);
    return;
  }

  eval {
    if (ref $metadata eq 'Mojo::Upload') {
      $self->app->log->debug("Metadata sent as file param");
      $metadata = $metadata->asset->slurp;
      $self->app->log->debug("parsing json");
      $metadata = decode_json($metadata);
    }
    else {
      # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
      $self->app->log->debug("parsing json");
      $metadata = decode_json(b($metadata)->encode('UTF-8'));
    }
  };

  if ($@) {
    $self->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, {type => 'danger', msg => $@};
    $res->{status} = 400;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r            = $object_model->create_container($self, $metadata, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if ($r->{status} ne 200) {
    $res->{status} = $r->{status};
    foreach my $a (@{$r->{alerts}}) {
      unshift @{$res->{alerts}}, $a;
    }
    unshift @{$res->{alerts}}, {type => 'danger', msg => 'Error creating ' . $self->stash('cmodel') . ' object'};
    $self->render(json => $res, status => $res->{status});
    return;
  }

  foreach my $a (@{$r->{alerts}}) {
    unshift @{$res->{alerts}}, $a;
  }
  $res->{status} = $r->{status};
  $res->{pid}    = $r->{pid};

  $self->render(json => $res, status => $res->{status});
}

sub add_relationship {

  my $self = shift;

  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $predicate = $self->param('predicate');
  my $object    = $self->param('object');

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r            = $object_model->add_relationship($self, $self->stash('pid'), $predicate, $object, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  $self->render(json => $r, status => $r->{status});

}

sub purge_relationship {

  my $self = shift;
  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $predicate = $self->param('predicate');
  my $object    = $self->param('object');

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r            = $object_model->purge_relationship($self, $self->stash('pid'), $predicate, $object, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  $self->render(json => $r, status => $r->{status});

}

sub add_or_remove_identifier {

  my $self = shift;

  my $pid = $self->stash('pid');
  unless (defined($pid)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $operation = $self->stash('operation');
  unless ($operation) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Unknown operation'}]}, status => 400);
    return;
  }

  my @ids;
  if ($self->param('hdl')) {
    push @ids, "hdl:" . $self->param('hdl');
  }
  if ($self->param('doi')) {
    push @ids, "doi:" . $self->param('doi');
  }
  if ($self->param('urn')) {
    push @ids, $self->param('urn');
  }

  unless (scalar @ids > 0) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'No known identifier sent (param should be [hdl|doi|urn])'}]}, status => 400);
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r;
  for my $id (@ids) {
    if ($operation eq 'add') {
      $r = $object_model->add_relationship($self, $pid, 'http://purl.org/dc/terms/identifier', $id, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
    }
    elsif ($operation eq 'remove') {
      $r = $object_model->purge_relationship($self, $pid, 'http://purl.org/dc/terms/identifier', $id, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
    }
  }

  $self->render(json => $r, status => $r->{status});

}

sub add_octets {
  my $self = shift;

  my $res = {alerts => [], status => 200};

  my $object_model = PhaidraAPI::Model::Object->new;

  my $upload = $self->req->upload('file');

  if ($self->req->is_limit_exceeded) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'File is too big'}]}, status => 400);
    return;
  }

  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $mimetype;
  if (defined($self->param('mimetype'))) {
    $mimetype = $self->param('mimetype');
  }
  else {
    $mimetype = $object_model->get_mimetype($self, $upload->asset);
    unshift @{$res->{alerts}}, {type => 'info', msg => "Undefined mimetype, using magic: $mimetype"};
  }

  my $file         = $self->param('file');
  my $pid          = $self->stash('pid');
  my $checksumtype = $self->param('checksumtype');
  my $checksum     = $self->param('checksum');

  # $object_model->add_octets will re-index, so keep inventory cleanup above it to avoid indexing old data
  # delete inventory info
  $self->app->paf_mongo->get_collection('foxml.ds')->remove({'pid' => $pid});

  # delete imagemanipulator record
  $self->app->db_imagemanipulator->dbh->do('DELETE FROM image WHERE url = "' . $pid . '";') or $self->app->log->error("Error deleting from imagemanipulator db:" . $self->app->db_imagemanipulator->dbh->errstr);

  my $addres = $object_model->add_octets($self, $pid, $upload, $file, $mimetype, $checksumtype, $checksum);
  push @{$res->{alerts}}, @{$addres->{alerts}} if scalar @{$addres->{alerts}} > 0;
  $res->{status} = $addres->{status};

  # insert new imageserver job
  my $search_model = PhaidraAPI::Model::Search->new;
  my $cmodelr      = $search_model->get_cmodel($self, $pid);
  if ($cmodelr->{status} eq 200) {
    my $cmodel = $cmodelr->{cmodel};
    my $hash   = hmac_sha1_hex($pid, $self->app->config->{imageserver}->{hash_secret});
    $self->paf_mongo->get_collection('jobs')->insert_one({pid => $pid, cmodel => $cmodel, agent => "pige", status => "new", idhash => $hash, created => time});
  }
  else {
    $self->app->log->error("Error finding cmodel when creating imageserver job:" . $self->app->dumper($cmodelr));
  }

  $self->render(json => $res, status => $res->{status});
}

sub add_or_modify_datastream {

  my $self = shift;

  unless (defined($self->stash('pid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  unless (defined($self->stash('dsid'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined dsid'}]}, status => 400);
    return;
  }

  unless (defined($self->param('mimetype'))) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined mimetype'}]}, status => 400);
    return;
  }

  my $mimetype     = $self->param('mimetype');
  my $location     = $self->param('location');
  my $checksumtype = $self->param('checksumtype');
  my $checksum     = $self->param('checksum');
  my $label        = undef;
  if ($self->param('dslabel')) {
    $label = $self->param('dslabel');
  }
  my $dscontent = undef;
  if ($self->param('dscontent')) {
    $dscontent = $self->param('dscontent');
    if (ref $dscontent eq 'Mojo::Upload') {

      # this is a file upload
      $self->app->log->debug("Parameter dscontent is a file parameter file=[" . $dscontent->filename . "] size=[" . $dscontent->size . "]");
      $dscontent = $dscontent->asset->slurp;
    }
    else {
      # $self->app->log->debug("Parameter dscontent is a text parameter");
    }
  }

  my $controlgroup = $self->param('controlgroup');

  my $object_model = PhaidraAPI::Model::Object->new;

  my $r = $object_model->add_or_modify_datastream($self, $self->stash('pid'), $self->stash('dsid'), $mimetype, $location, $label, $dscontent, $controlgroup, $checksumtype, $checksum, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  $self->render(json => $r, status => $r->{status});
}

sub get_metadata {
  my $self = shift;

  my $res = {alerts => [], status => 200};

  my $pid = $self->stash('pid');

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  my $mode = $self->param('mode');

  unless (defined($mode)) {
    $mode = 'basic';
  }

  my $search_model = PhaidraAPI::Model::Search->new;
  my $r            = $search_model->datastreams_hash($self, $pid);
  if ($r->{status} ne 200) {
    return $r;
  }

  if ($r->{dshash}->{'JSON-LD'}) {
    my $jsonld_model = PhaidraAPI::Model::Jsonld->new;
    my $r_jsonld     = $jsonld_model->get_object_jsonld_parsed($self, $pid, $username, $password);
    if ($r_jsonld->{status} ne 200) {
      push @{$res->{alerts}}, @{$r_jsonld->{alerts}} if scalar @{$r_jsonld->{alerts}} > 0;
      push @{$res->{alerts}}, {type => 'danger', msg => 'Error getting JSON-LD'};
    }
    else {
      $res->{metadata}->{'JSON-LD'} = $r_jsonld->{'JSON-LD'};
    }
  }

  if ($r->{dshash}->{'JSON-LD-PRIVATE'}) {
    my $jsonldprivate_model = PhaidraAPI::Model::Jsonldprivate->new;
    my $r_jsonldprivate     = $jsonldprivate_model->get_object_jsonldprivate_parsed($self, $pid, $username, $password);
    if ($r_jsonldprivate->{status} ne 200) {
      if (($r->{status} eq 401) || ($r->{status} eq 403)) {

        # unauthorized users should not see that JSON-LD-PRIVATE exists
      }
      else {
        push @{$res->{alerts}}, @{$r_jsonldprivate->{alerts}} if scalar @{$r_jsonldprivate->{alerts}} > 0;
        push @{$res->{alerts}}, {type => 'danger', msg => 'Error getting JSON-LD-PRIVATE'};
      }
    }
    else {
      $res->{metadata}->{'JSON-LD-PRIVATE'} = $r_jsonldprivate->{'JSON-LD-PRIVATE'};
    }
  }

  if ($r->{dshash}->{'MODS'}) {
    my $mods_model = PhaidraAPI::Model::Mods->new;
    my $r          = $mods_model->get_object_mods_json($self, $pid, $mode, $username, $password);
    if ($r->{status} ne 200) {
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      push @{$res->{alerts}}, {type => 'danger', msg => 'Error getting MODS'};
    }
    else {
      $res->{metadata}->{mods} = $r->{mods};
    }
  }

  if ($r->{dshash}->{'UWMETADATA'}) {
    my $uwmetadata_model = PhaidraAPI::Model::Uwmetadata->new;
    my $r                = $uwmetadata_model->get_object_metadata($self, $pid, $mode, $username, $password);
    if ($r->{status} ne 200) {
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      push @{$res->{alerts}}, {type => 'danger', msg => 'Error getting UWMETADATA'};
    }
    else {
      $res->{metadata}->{uwmetadata} = $r->{uwmetadata};
    }
  }

  if ($r->{dshash}->{'GEO'}) {
    my $geo_model = PhaidraAPI::Model::Geo->new;
    my $r         = $geo_model->get_object_geo_json($self, $pid, $username, $password);
    if ($r->{status} ne 200) {
      push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      push @{$res->{alerts}}, {type => 'danger', msg => 'Error getting GEO'};
    }
    else {
      $res->{metadata}->{geo} = $r->{geo};
    }
  }

  if ($r->{dshash}->{'RIGHTS'}) {
    my $rights_model = PhaidraAPI::Model::Rights->new;
    my $r            = $rights_model->get_object_rights_json($self, $pid, $username, $password);
    if ($r->{status} ne 200) {
      if (($r->{status} eq 401) || ($r->{status} eq 403)) {

        # unauthorized users should not see that RIGHTS exists
      }
      else {
        push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
        push @{$res->{alerts}}, {type => 'danger', msg => 'Error getting RIGHTS'};
      }
    }
    else {
      $res->{metadata}->{rights} = $r->{rights};
    }
  }

  $self->render(json => $res, status => $res->{status});
}

sub metadata {
  my $self = shift;

  my $res = {alerts => [], status => 200};

  my $t0 = [gettimeofday];

  my $pid = $self->stash('pid');

  my $metadata = $self->param('metadata');
  unless (defined($metadata)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'No metadata sent'}]}, status => 400);
    return;
  }

  eval {
    if (ref $metadata eq 'Mojo::Upload') {
      $self->app->log->debug("Metadata sent as file param");
      $metadata = $metadata->asset->slurp;
      $self->app->log->debug("parsing json");
      $metadata = decode_json($metadata);
    }
    else {
      # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
      $self->app->log->debug("parsing json");
      $metadata = decode_json(b($metadata)->encode('UTF-8'));
    }
  };

  if ($@) {
    $self->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, {type => 'danger', msg => $@};
    $res->{status} = 400;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  unless (defined($metadata->{metadata})) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'No metadata found'}]}, status => 400);
    return;
  }
  $metadata = $metadata->{metadata};

  unless (defined($pid)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $cmodel;
  my $search_model = PhaidraAPI::Model::Search->new;
  my $res_cmodel   = $search_model->get_cmodel($self, $pid);
  if ($res_cmodel->{status} ne 200) {
    my $err = "ERROR saving metadata for object $pid, could not get cmodel:" . $self->app->dumper($res_cmodel);
    $self->app->log->error($err);
    $self->render(json => {alerts => [{type => 'danger', msg => $err}]}, status => 500);
    return;
  }
  else {
    $cmodel = $res_cmodel->{cmodel};
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r            = $object_model->save_metadata($self, $pid, $cmodel, $metadata, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if ($r->{status} ne 200) {
    $res->{status} = $r->{status};
    foreach my $a (@{$r->{alerts}}) {
      unshift @{$res->{alerts}}, $a;
    }
    unshift @{$res->{alerts}}, {type => 'danger', msg => 'Error saving metadata'};

  }
  else {
    my $t1 = tv_interval($t0);
    unshift @{$res->{alerts}}, {type => 'success', msg => "Metadata for $pid saved successfully ($t1 s)"};

  }

  $self->render(json => $res, status => $res->{status});

}

sub get_iiif_manifest {
  my $self = shift;

  my $pid = $self->stash('pid');

  unless (defined($pid)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}], status => 404}, status => 404);
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  $object_model->proxy_datastream($self, $pid, 'IIIF-MANIFEST', $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password}, 1);
}

# Diss method is for calling the disseminator which is api-a access, so it can also be called without credentials.
# However, if the credentials are necessary, we want to send 401 so that the browser creates login prompt. Fedora sends 403
# in such case which won't create login prompt, so user cannot access locked object even if he should be able to login.
sub diss {
  my $self = shift;

  my $pid    = $self->stash('pid');
  my $bdef   = $self->stash('bdef');
  my $method = $self->stash('method');

  unless (defined($pid)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'Undefined pid'}]}, status => 400);
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;

  # do we have access without credentials?
  unless ($self->stash->{basic_auth_credentials}->{username}) {
    my $res = $object_model->get_datastream($self, $pid, 'READONLY', undef, undef);
    $self->app->log->info("pid[$pid] read rights: " . $res->{status});
    unless ($res->{status} eq '404') {
      $self->res->headers->www_authenticate('Basic');
      $self->render(json => {alerts => [{type => 'danger', msg => 'authentication needed'}]}, status => 401);
      return;
    }
  }

  my $url = Mojo::URL->new;
  $url->scheme('https');
  $url->host($self->app->config->{phaidra}->{fedorabaseurl});
  $url->userinfo($self->stash->{basic_auth_credentials}->{username} . ":" . $self->stash->{basic_auth_credentials}->{password}) if $self->stash->{basic_auth_credentials}->{username};
  $url->path("/fedora/get/$pid/bdef:$bdef/$method");

  if (($bdef eq 'Resource') && ($method eq 'get')) {
    my $redres = $self->ua->get($url)->result;
    $self->app->log->info("fedora resource get result code[" . $redres->code . "] message[" . $redres->message . "] location[" . $redres->headers->location . "]");
    if ($redres->code == 302) {

      $self->res->headers->location($redres->headers->location);
      $self->rendered(302);
      return;
    }
    else {
      $self->render(json => {alerts => [{type => 'danger', msg => $redres->message}]}, status => $redres->code);
      return;
    }
  }
  else {
    $self->app->log->info("user[" . $self->stash->{basic_auth_credentials}->{username} . "] proxying $url");
    if (Mojo::IOLoop->is_running) {
      $self->render_later;
      $self->ua->get(
        $url,
        sub {
          my ($c, $tx) = @_;
          _proxy_tx($self, $tx);
        }
      );
    }
    else {
      my $tx = $self->ua->get($url);
      _proxy_tx($self, $tx);
    }
  }
}

sub _proxy_tx {
  my ($c, $tx) = @_;
  if (my $res = $tx->success) {
    $c->tx->res($res);
    $c->rendered;
  }
  else {
    my $error = $tx->error;
    $c->tx->res->headers->add('X-Remote-Status', $error->{code} . ': ' . $error->{message});
    $c->render(status => 500, text => 'Failed to fetch data from Fedora: ' . $c->app->dumper($tx->error));
  }
}

1;
