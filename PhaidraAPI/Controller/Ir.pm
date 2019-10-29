package PhaidraAPI::Controller::Ir;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(encode decode);
use Mojo::ByteStream qw(b);
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Collection;
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Rights;
use Time::HiRes qw/tv_interval gettimeofday/;
use Storable qw(dclone);
use POSIX qw/strftime/;
use MIME::Lite;
use MIME::Lite::TT::HTML;

sub notifications {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  $self->app->log->debug("=== params ===");
  for my $pn (@{$self->req->params->names}){
    $self->app->log->debug($pn);
  }
  $self->app->log->debug("==============");

  my $pid = $self->param('pid');

  unless($pid){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No pid sent.' }]}, status => 400);
    return;
  }

  my @pids;

  push @pids, $pid;

  my $alternatives = $self->every_param('alternatives[]');

  if ($alternatives) {
    if(ref($alternatives) eq 'ARRAY'){
      for my $apid (@$alternatives) {
        push @pids, $apid;
      }
    }else{
      push @pids, $alternatives;
    }
  }

  my $notification = $self->param('notification');
  if ($notification) {
    $self->addAlert('mdcheck', \@pids, $username);
  }
  my $embargonotification = $self->param('embargonotification');
  if ($embargonotification) {
    $self->addAlert('embargo', \@pids, $username);
  }

  $self->render(json => $res, status => $res->{status});
}

sub addEvent
{
  my ($self, $eventtype, $pids, $username) = @_;

  my $time = strftime "%Y-%m-%dT%H:%M:%SZ", (gmtime);	

  foreach my $pid (@$pids){
    if($eventtype eq 'submit'){
      # do not add double 'submits'
      my $check_ss = qq/SELECT * FROM event WHERE user_id = ? AND event_type = 'submit' AND pid = ? LIMIT 1/;
      my $check_sth = $self->app->db_ir->prepare($check_ss) or $self->app->log->error($self->app->db_ir->errstr);
      $check_sth->execute($username, $pid) or $self->app->log->error($self->app->db_ir->errstr);
      if($check_sth->rows){
        $self->app->log->info("IR skipping addEvent (username=".$username.", alerttype=$eventtype, pids=$pid), already added.");
        next;
      }
    }
    $self->app->log->info("IR addEvent (username=".$username.", alerttype=$eventtype, pids=$pid)");
    my $ss = qq/INSERT INTO event (event_type, pid, user_id, gmtimestamp) VALUES (?,?,?,?)/;
    my $sth = $self->app->db_ir->prepare($ss) or $self->app->log->error($self->app->db_ir->errstr);
    $sth->execute($eventtype, $pid, $username, $time) or $self->app->log->error($self->app->db_ir->errstr);
  }
}

sub addAlert
{
  my ($self, $alerttype, $pidsArr, $username) = @_;

  my $pids = join(',', @{$pidsArr});

  if($self->hasAlerts($alerttype, $pids, $username))
  {
    $self->app->log->info("IR skipping addAlert (username=".$username.", alerttype=$alerttype, pids=$pids), already added.");
  }
  else
  {
    $self->app->log->info("IR addAlert (username=".$username.", alerttype=$alerttype, pids=$pids)");
    my $time = strftime "%Y-%m-%dT%H:%M:%SZ", (gmtime);	
    my $ss = qq/INSERT INTO alert (username,alert_type,pids,gmtimestamp,processed) VALUES (?,?,?,?,?)/;
    my $sth = $self->app->db_ir->prepare($ss) or $self->app->log->error($self->app->db_ir->errstr);
    $sth->execute($username, $alerttype, $pids, $time, 0) or $self->app->log->error($self->app->db_ir->errstr);
  }
}

sub hasAlerts
{
  my ($self, $alerttype, $pids, $username) = @_;

  my $ss = qq/SELECT * FROM alert WHERE username = ? AND alert_type = ? AND pids = ? LIMIT 1/;
  my $sth = $self->app->db_ir->prepare($ss) or $self->app->log->error($self->app->db_ir->errstr);
  $sth->execute($username, $alerttype, $pids) or $self->app->log->error($self->app->db_ir->errstr);

  return $sth->rows;
}

sub getAlertForPid
{
  my ($self, $alerttype, $pids) = @_;

  my $ss = qq/SELECT id, username, pids FROM alert WHERE alert_type = ? AND processed = 0 AND alert.pids LIKE ?;/;
  my $sth = $self->app->db_ir->prepare($ss) or $self->app->log->error($self->app->db_ir->errstr);
  $sth->execute($alerttype, $pids) or $self->app->log->error($self->app->db_ir->errstr);
  my ($id, $username, $pids);
  $sth->bind_columns(\$id, \$username, \$pids) or $self->app->log->error($self->app->db_ir->errstr);
  while($sth->fetch()){
    return { id => $id, username => $username, pids => $pids };
  }
}

sub setAlertProcessed
{
  my ($self, $id) = @_;

  $self->app->log->info("Ir::setAlertProcessed id[$id]");
  my $ss = qq/UPDATE alert SET processed = 1 WHERE id = ?;/;
  my $sth = $self->app->db_ir->prepare($ss) or $self->app->log->error($self->app->db_ir->errstr);
  $sth->execute($id) or $self->app->log->error($self->app->db_ir->errstr);
}

sub accept
{
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  if($username ne $self->config->{ir}->{iraccount}){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Not authorized.' }]} , status => 403) ;
    return;
  }

  my $pid = $self->stash('pid');

  unless($pid){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No pid sent.' }]}, status => 400);
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;

  my $r = $object_model->modify($self, $pid, undef, undef, $self->config->{ir}->{iraccount}, 'ir accept', undef, $username, $password);
  if($r->{status} ne 200){
    $res->{status} = 500;
    unshift @{$res->{alerts}}, @{$r->{alerts}};
    unshift @{$res->{alerts}}, { type => 'danger', msg => "Error accepting object $pid"};
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my @pids = ($pid);
  $self->addEvent('accept', \@pids, $username);

  $self->render(json => $res, status => $res->{status});
}

sub reject
{
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  if($username ne $self->config->{ir}->{iraccount}){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Not authorized.' }]} , status => 403) ;
    return;
  }

  my $pid = $self->stash('pid');

  unless($pid){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No pid sent.' }]}, status => 400);
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;

  my $r = $object_model->purge_relationship($self, $pid, "http://phaidra.org/ontology/isInAdminSet", $self->config->{ir}->{adminset}, $self->config->{phaidra}->{adminusername}, $self->config->{phaidra}->{adminpassword}, 0);
  push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
  if($r->{status} ne 200){
    $res->{status} = 500;
    unshift @{$res->{alerts}}, @{$r->{alerts}};
    unshift @{$res->{alerts}}, { type => 'danger', msg => "Error rejecting object $pid"};
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my @pids = ($pid);
  $self->addEvent('reject', \@pids, $username);

  $self->render(json => $res, status => $res->{status});
}

sub approve
{
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  if($username ne $self->config->{ir}->{iraccount}){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Not authorized.' }]} , status => 403) ;
    return;
  }

  my $pid = $self->stash('pid');

  unless($pid){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No pid sent.' }]}, status => 400);
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $r = $object_model->add_relationship($self, $self->config->{ir}->{ircollection}, "info:fedora/fedora-system:def/relations-external#hasCollectionMember", "info:fedora/".$pid, $username, $password, 0);
  if($r->{status} ne 200){
    $res->{status} = 500;
    unshift @{$res->{alerts}}, @{$r->{alerts}};
    unshift @{$res->{alerts}}, { type => 'danger', msg => "Error approving object $pid"};
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my @pids = ($pid);
  $self->addEvent('approve', \@pids, $username);

  my $alert = $self->getAlertForPid('mdcheck', $pid);
  unless ($alert->{username}) {
    $self->app->log->debug("approve pid[$pid]: no alerts found");
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my $owner = $alert->{username};

  my $email = $self->app->directory->get_email($self, $owner);

 	my %emaildata;
 	$emaildata{pid} = $pid;
 	$emaildata{baseurl} = $self->config->{ir}->{baseurl};

  my $subject = $self->config->{ir}->{name}." - Redaktionelle Bearbeitung abgeschlossen / Submission process completed";
  my $templatefolder = $self->config->{ir}->{templatefolder};

  my %options;
  $options{INCLUDE_PATH} = $templatefolder;	
  eval
  {
    my $msg = MIME::Lite::TT::HTML->new(
      From        => $self->config->{ir}->{supportemail},
      To          => $email,
      Subject     => $subject,
      Charset		=> 'utf8',
      Encoding    => 'quoted-printable',
      Template    => { html => 'mdcheck.html.tt', text => 'mdcheck.txt.tt'},
      TmplParams  => \%emaildata,
      TmplOptions => \%options
    );
    $msg->send;
  };
  if($@)
  {
    $self->addEvent('approval_notification_failed', \@pids, $username);
    my $err = "[$pid] sending notification email failed: ".$@;
    $self->app->log->error($err);
    # 200 - the object was approved, notification failure goes to alerts
    $res->{status} = 200;
    unshift @{$res->{alerts}}, { type => 'danger', msg => $err};
    $self->render(json => $res, status => $res->{status});
    return;
  }

  # update history
  $self->setAlertProcessed($alert->{id});
  $self->addEvent('approval_notification_sent', \@pids, $username);

  $self->render(json => $res, status => $res->{status});
}

sub events {

  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  if($username ne $self->config->{ir}->{iraccount}){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Not authorized.' }]} , status => 403) ;
    return;
  }

  my $pid = $self->stash('pid');

  unless($pid){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No pid sent.' }]}, status => 400);
    return;
  }

  my @events;
  my $ss = qq/SELECT event_type, user_id, gmtimestamp FROM event WHERE pid = ?;/;
  my $sth = $self->app->db_ir->prepare($ss) or $self->app->log->error($self->app->db_ir->errstr);
  $sth->execute($pid) or $self->app->log->error($self->app->db_ir->errstr);
  my ($event, $username, $ts);
  $sth->bind_columns(\$event, \$username, \$ts) or $self->app->log->error($self->app->db_ir->errstr);
  while($sth->fetch()){	
    push @events, { event => $event, username => $username, ts => $ts};
  }

  $res->{events} = \@events;

  $self->render(json => $res, status => $res->{status});
}

sub requestedlicenses {

  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  $self->app->log->debug("=== params ===");
  for my $pn (@{$self->req->params->names}){
    $self->app->log->debug($pn);
  }
  $self->app->log->debug("==============");

  if($username ne $self->config->{ir}->{iraccount}){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Not authorized.' }]} , status => 403) ;
    return;
  }

  my @pids;
  my $pids = $self->every_param('pids[]');

  if ($pids) {
    if(ref($pids) eq 'ARRAY'){
      for my $apid (@$pids) {
        push @pids, $apid;
      }
    }else{
      push @pids, $pids;
    }
  }

  my @pidsquoted;
  for my $p (@pids) {
    push @pidsquoted, "'".$p."'";
  }
  my $pidsparam = join ',', @pidsquoted;

  my @licenses;
  my $ss = "SELECT pid, license FROM requested_license WHERE pid IN ($pidsparam)";
  my $sth = $self->app->db_ir->prepare($ss) or $self->app->log->error($self->app->db_ir->errstr);
  $sth->execute() or $self->app->log->error($self->app->db_ir->errstr);
  my ($pid,$license);
  $sth->bind_columns(undef, \$pid, \$license) or $self->app->log->error($self->app->db_ir->errstr);
  while($sth->fetch())
  {
    push @licenses, {pid => $pid, requestedlicense => $license};
  }

  $res->{requestedlicenses} = \@licenses;

  $self->render(json => $res, status => $res->{status});
}

sub addrequestedlicense {
  my $self = shift;
  my $pid = shift;
  my $username = shift;
  my $license = shift;

  my $time = strftime "%Y-%m-%dT%H:%M:%SZ", (gmtime);	

  my $ss = qq/INSERT INTO requested_license (pid, license, user_id, gmtimestamp) VALUES (?,?,?,?)/;
  my $sth = $self->app->db_ir->prepare($ss) or $self->app->log->error($self->app->db_ir->errstr);
  $sth->execute($pid, $license, $username, $time) or $self->app->log->error($self->app->db_ir->errstr);
}

sub allowsubmit {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  $res->{allowsubmit} = 0;
  $res->{candobulkupload} = 0;

  my $username = $self->stash->{basic_auth_credentials}->{username};

  if($self->config->{ir}->{bulkuploadlimit}->{nruploads} && $self->config->{ir}->{bulkuploadlimit}->{nrdays}){
    my $nruploads =$self->config->{ir}->{bulkuploadlimit}->{nruploads};
    my $nrdays = $self->config->{ir}->{bulkuploadlimit}->{nrdays};
    $res->{nruploads} = $nruploads;
    $res->{nrdays} = $nrdays;
    $self->app->log->info("Bulk upload check configured: nruploads[$nruploads] within days[$nrdays]");
    my $candobulkupload = 0;
    if($self->config->{ir}->{candobulkupload}){
      for my $acc (@{$self->config->{ir}->{candobulkupload}}){
        if($username eq $acc){
          $res->{candobulkupload} = 1;
          $candobulkupload = 1;
        }
      }
    }

    unless($candobulkupload){
      $self->app->log->info("User[$username] CAN NOT do bulk uploads. Checking if this is bulk upload...");
      my $nr = $self->getNrUnapprovedUploads($username, $nrdays);
      $res->{nrunapproveduploads} = $nr;
      if($nr >= $nruploads){
        $self->app->log->info("User[$username] deny submitform, user has [$nr] unapproved uploads within ".$nrdays." days.");
        $res->{allowsubmit} = 0;
      } else {
        $self->app->log->info("User[$username] - not a bulk upload, user has [$nr] unapproved uploads within ".$nrdays." days.");
        $res->{allowsubmit} = 1;
      }
    }else{
      $self->app->log->info("User[$username] CAN do bulk uploads.");
      $res->{allowsubmit} = 1;
    }
  }

  $self->render(json => $res, status => $res->{status});
}

sub getNrUnapprovedUploads {
  my ($self, $username, $nrdays) = @_;

  my $ss = 'SELECT COUNT(*) AS nrunapproveduploads FROM (SELECT INSTR(GROUP_CONCAT(event_type),"approve") as approvedstrpos, pid, INSTR(GROUP_CONCAT(user_id),?) as userstrpos, gmtimestamp FROM event as e, (SELECT MAX(STR_TO_DATE(gmtimestamp,"%Y-%m-%dT%TZ")) as maxd FROM event WHERE user_id = ? AND event_type = "submit") subq1 WHERE user_id = ? OR user_id = ? AND STR_TO_DATE(e.gmtimestamp,"%Y-%m-%dT%TZ") >= SUBDATE(subq1.maxd, ?) GROUP BY pid) uploads WHERE approvedstrpos = 0 AND userstrpos > 0;';
  my $res = $self->app->db_ir->selectrow_hashref($ss, undef, ($username, $username, $self->config->{ir}->{iraccount}, $username, $nrdays)) or $self->app->log->error($self->app->db_ir->errstr);
  return $res->{nrunapproveduploads};
}

sub submit {

  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  $self->app->log->debug("=== params ===");
  for my $pn (@{$self->req->params->names}){
    $self->app->log->debug($pn);
  }
  for my $up (@{$self->req->uploads}){
    $self->app->log->debug($up->{name}.": ".$up->{filename});
  }
  $self->app->log->debug("==============");

  if($self->req->is_limit_exceeded){
    $self->app->log->debug("Size limit exceeded. Current max_message_size:".$self->req->max_message_size);
    $self->render(json => { alerts => [{ type => 'danger', msg => 'File is too big' }]}, status => 400);
    return;
  }

  my $metadata = $self->param('metadata');
  unless($metadata){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent.' }]}, status => 400);
    return;
  }

  eval {
    if(ref $metadata eq 'Mojo::Upload'){
      $self->app->log->debug("Metadata sent as file param");
      $metadata = $metadata->asset->slurp;
      $self->app->log->debug("parsing json");
      $metadata = decode_json($metadata);
    }else{
      $self->app->log->debug("parsing json");
      $metadata = decode_json(b($metadata)->encode('UTF-8'));
    }
  };

  if($@){
    $self->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
    $res->{status} = 400;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  unless(exists($metadata->{metadata}->{'json-ld'}->{'ebucore:filename'})){
    unshift @{$res->{alerts}}, { type => 'danger', msg => "Missing ebucore:filename"};
    $res->{status} = 400;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  unless(exists($metadata->{metadata}->{'json-ld'}->{'ebucore:hasMimeType'})){
    unshift @{$res->{alerts}}, { type => 'danger', msg => "Missing ebucore:hasMimeType"};
    $res->{status} = 400;
    $self->render(json => $res, status => $res->{status});
    return;
  }

  my %rights;
  if(exists($metadata->{metadata}->{'json-ld'}->{'dcterms:accessRights'})){
    for my $ar (@{$metadata->{metadata}->{'json-ld'}->{'dcterms:accessRights'}}){
      if(exists($ar->{'skos:exactMatch'})){
        for my $arId (@{$ar->{'skos:exactMatch'}}) {
          # embargoed
          if ($arId eq 'https://vocab.phaidra.org/vocabulary/AVFC-ZZSZ') {
            if(exists($metadata->{metadata}->{'json-ld'}->{'dcterms:available'})){
              for my $embargoDate (@{$metadata->{metadata}->{'json-ld'}->{'dcterms:available'}}) {
                $rights{'username'} = (
                  {
                    value => $username,
                    expires => $embargoDate."T00:00:00Z"
                  }
                );
                last;
              }
            }
          }
          # closed
          if ($arId eq 'https://vocab.phaidra.org/vocabulary/QNGE-V02H') {
            $rights{'username'} = $username;
          }
          # restricted
          if ($arId eq 'https://vocab.phaidra.org/vocabulary/KC3K-CCGM') {
            $rights{'username'} = $username;
          }
        }
      }
    }
  }

  my @filenames = @{$metadata->{metadata}->{'json-ld'}->{'ebucore:filename'}};
  my @mimetypes = @{$metadata->{metadata}->{'json-ld'}->{'ebucore:hasMimeType'}};

  my $object_model = PhaidraAPI::Model::Object->new;

  my $cnt = scalar @filenames;
  my $mainObjectPid;
  my @alternativeFormatPids;
  for (my $i = 0; $i < $cnt; $i++) {
    my $filename = $filenames[$i];
    my $mimetype = $mimetypes[$i];

    my $fileupload;
    for my $up (@{$self->req->uploads}){
      if ($filename eq $up->{filename}) {
        $fileupload = $up;
      }
    }
    unless(defined($fileupload)){
      unshift @{$res->{alerts}}, { type => 'danger', msg => "Missing file [$filename]"};
      $res->{status} = 400;
      $self->render(json => $res, status => $res->{status});
      return;
    }

    my $size = $fileupload->size;
    my $name = $fileupload->filename;
    $self->app->log->debug("Found file: $name [$size B]");

    my $jsonld = dclone($metadata->{metadata}->{'json-ld'});

    my $title;
    my $titles = $jsonld->{'dce:title'};
    for my $o (@{$titles}) {
      $title = $o->{'bf:mainTitle'}[0]->{'@value'};
      last;
    }

    my @filenameArr = ($filename);
    $jsonld->{'ebucore:filename'} = \@filenameArr;
    my @mimetypeArr = ($mimetype);
    $jsonld->{'ebucore:hasMimeType'} = \@mimetypeArr;

    $self->app->log->debug('Requested license:'.$self->app->dumper($jsonld->{'edm:rights'}));
    my $requestedLicense = @{$jsonld->{'edm:rights'}}[0];
    if ($username ne $self->config->{ir}->{iraccount}) {
      my @lic;
      push @lic, 'http://rightsstatements.org/vocab/InC/1.0/';
      $jsonld->{'edm:rights'} = \@lic;
    }

    my $isAlternativeFormat = 0;
    my $cmodel;
    if ($mimetype eq 'application/pdf' || $mimetype eq 'application/x-pdf') {
      $cmodel = 'cmodel:PDFDocument';
    } else {
      $cmodel = 'cmodel:Asset';
      $isAlternativeFormat = 1;
    }

    my $md = {
      metadata => {
        'json-ld' => $jsonld
      }
    };

    if(exists($rights{'username'})){
      $self->app->log->debug("Setting rights: \n".$self->app->dumper(\%rights));
      $md->{metadata}->{rights} = \%rights;
    }

    my $r = $object_model->create_simple($self, $cmodel, $md, $mimetype, $fileupload, undef, undef, $username, $password);
    if($r->{status} ne 200){
      $res->{status} = 500;
      unshift @{$res->{alerts}}, @{$r->{alerts}};
      unshift @{$res->{alerts}}, { type => 'danger', msg => "Error creating object [filename=$filename]"};
      $self->render(json => $res, status => $res->{status});
      return;
    }

    if ($isAlternativeFormat) {
      push @alternativeFormatPids, $r->{pid};
    } else {
      $mainObjectPid = $r->{pid};
    }

    $self->addrequestedlicense($r->{pid}, $username, $requestedLicense);

    $self->sendEmail($title, $username, $r->{pid}, $requestedLicense);
  }

  my @mainObjectRelationships = (
    {
      predicate => "http://phaidra.org/ontology/isInAdminSet", 
      object => $self->config->{ir}->{adminset}
    }
  );

  my $alternativeVersionPid = $self->param('isAlternativeVersionOf');
  if ($alternativeVersionPid) {
    push @mainObjectRelationships, {
      predicate => "http://phaidra.org/XML/V1.0/relations#isAlternativeVersionOf", 
      object => "info:fedora/".$alternativeVersionPid
    };
  }

  $self->app->log->debug("Adding relationships[".$self->app->dumper(\@mainObjectRelationships)."] to pid[$mainObjectPid]");

  my $r = $object_model->add_relationships($self, $mainObjectPid, \@mainObjectRelationships, $username, $password);
  push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
  if($r->{status} ne 200){
    $self->app->log->error("Error adding relationships[".$self->app->dumper(\@mainObjectRelationships)."] pid[$mainObjectPid] res[".$self->app->dumper($res)."]");
    # continue, this isn't fatal
  }

  for my $alternativeFromatPid (@alternativeFormatPids) {

    my @alternativeFormatsRelationships = (
      {
        predicate => "http://phaidra.org/XML/V1.0/relations#isAlternativeFormatOf", 
        object => "info:fedora/".$mainObjectPid
      },
      {
        predicate => "http://phaidra.org/ontology/isInAdminSet", 
        object => $self->config->{ir}->{adminset}
      }
    );

    $self->app->log->debug("Adding relationships[".$self->app->dumper(\@alternativeFormatsRelationships)."] to pid[$alternativeFromatPid]");

    my $r = $object_model->add_relationships($self, $alternativeFromatPid, \@alternativeFormatsRelationships, $username, $password);
    push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
    if($r->{status} ne 200){
      $self->app->log->error("Error adding relationships[".$self->app->dumper(\@alternativeFormatsRelationships)."] pid[$alternativeFromatPid] res[".$self->app->dumper($res)."]");
      # continue, this isn't fatal
    }
  }

  if ($username eq $self->config->{ir}->{iraccount}) {
    my $r = $object_model->add_relationship($self, $self->config->{ir}->{ircollection}, "info:fedora/fedora-system:def/relations-external#hasCollectionMember", "info:fedora/".$mainObjectPid, $username, $password, 0);
    push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
    if($r->{status} ne 200){
      $self->app->log->error("Error adding object to IR collection collpid[" . $self->config->{ir}->{ircollection} . "] relationship[info:fedora/fedora-system:def/relations-external#hasCollectionMember] pid[$mainObjectPid] res[".$self->app->dumper($res)."]");
    }
  }

  my @pids;
  push @pids, $mainObjectPid;
  for my $p (@alternativeFormatPids) {
    push @pids, $p;
  }
  $self->addEvent('submit', \@pids, $username);

  $res->{pid} = $mainObjectPid;
  $res->{alternatives} = \@alternativeFormatPids;

  $self->render(json => $res, status => $res->{status});
}

sub sendEmail {
  my ($self, $title, $owner, $pid, $license) = @_;

  my $phaidrabaseurl = $self->config->{phaidra}->{baseurl};
  my $irbaseur = $self->config->{ir}->{baseurl};

  my $email = "
  <html>
    <body>
      <p>Title: $title</p>
      <p>Owner: $owner</p>
      <p>IR: <a href=\"https://$irbaseur/detail/$pid\" target=\"_blank\">https://$irbaseur/detail/$pid</a></p>
      <p>Phaidra: <a href=\"https://$phaidrabaseurl/detail_object/$pid\" target=\"_blank\">https://$phaidrabaseurl/detail_object/$pid</a></p>		
      <p>Requested license: $license</p>
    </body>
  </html>	
  ";

  $self->app->log->info("Sending email for pid[$pid]: \n$email"); 

  my $msg = MIME::Lite->new(
    From     => $self->config->{ir}->{supportemail},
    To       => $self->config->{ir}->{supportemail},	  
    Type     => 'text/html; charset=UTF-8',
    Subject  => "New upload: $pid",
    Data     => encode('UTF-8', $email)
  );

  $msg->send;
}

sub stats {
  my $self = shift; 

  my $pid = $self->stash('pid');
  my $irsiteid = $self->param('siteid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'info', msg => 'Undefined pid' }]}, status => 400);
    return;
  }

  my $key = $self->stash('stats_param_key');

  my $fr = undef;
  if(exists($self->app->config->{frontends})){
    for my $f (@{$self->app->config->{frontends}}){
      if(defined($f->{frontend_id}) && $f->{frontend_id} eq 'ir'){
        $fr = $f;
      }
    }
  }

  unless(defined($fr)){
    # return 200, this is just ok
    $self->render(json => { alerts => [{ type => 'info', msg => 'Frontend is not configured' }]}, status => 200);
    return;
  }
  unless($fr->{frontend_id} eq 'ir'){
    # return 200, this is just ok
    $self->render(json => { alerts => [{ type => 'info', msg => 'Frontend ['.$fr->{frontend_id}.'] is not supported' }]}, status => 200);
    return;
  }
  unless(defined($fr->{stats})){
    # return 200, this is just ok
    $self->render(json => { alerts => [{ type => 'info', msg => 'Statistics source is not configured' }]}, status => 200);
    return;
  }
  # only piwik now
  unless($fr->{stats}->{type} eq 'piwik'){
    # return 200, this is just ok
    $self->render(json => { alerts => [{ type => 'info', msg => 'Statistics source ['.$fr->{stats}->{type}.'] is not supported.' }]}, status => 200);
    return;
  }
  unless($irsiteid){
    unless(defined($fr->{stats}->{siteid})){
      $self->render(json => { alerts => [{ type => 'info', msg => 'Piwik siteid is not configured' }]}, status => 500);
      return;
    }
    $irsiteid = $fr->{stats}->{siteid};
  }

  my $cachekey = 'stats_'.$irsiteid.'_'.$pid;
  my $cacheval = $self->app->chi->get($cachekey);

  unless($cacheval){

    $self->app->log->debug("[cache miss] $cachekey");

    my $pidnum = $pid;
    $pidnum =~ s/://g;

    my $sth = $self->app->db_stats_phaidra_catalyst->prepare("CREATE TEMPORARY TABLE pid_visits_idsite_downloads_$pidnum AS (SELECT piwik_log_link_visit_action.idsite FROM piwik_log_link_visit_action INNER JOIN piwik_log_action on piwik_log_action.idaction = piwik_log_link_visit_action.idaction_url WHERE piwik_log_action.name like '%download/$pid%');");
    $sth->execute();
    my $downloads = $self->app->db_stats_phaidra_catalyst->selectrow_array("SELECT count(*) FROM pid_visits_idsite_downloads_$pidnum WHERE idsite = $irsiteid;");

    unless(defined($downloads)){
      $self->app->log->error("Error querying piwik database for download stats:".$self->app->db_stats_phaidra_catalyst->errstr);
    }

    # this counts *any* page with pid in URL. But that kind of makes sense anyways...
    my $sth = $self->app->db_stats_phaidra_catalyst->prepare("CREATE TEMPORARY TABLE pid_visits_idsite_detail_$pidnum AS (SELECT piwik_log_link_visit_action.idsite FROM piwik_log_link_visit_action INNER JOIN piwik_log_action on piwik_log_action.idaction = piwik_log_link_visit_action.idaction_url WHERE piwik_log_action.name like '%detail/$pid%');");
    $sth->execute();
    my $detail_page = $self->app->db_stats_phaidra_catalyst->selectrow_array("SELECT count(*) FROM pid_visits_idsite_detail_$pidnum WHERE idsite = $irsiteid;");
  
    unless(defined($detail_page)){
      $self->app->log->error("Error querying piwik database for detail stats:".$self->app->db_stats_phaidra_catalyst->errstr);
    }

    if(defined($detail_page) || defined($downloads)){
      $cacheval = { downloads => $downloads, detail_page => $detail_page };
      $self->app->chi->set($cachekey, $cacheval, '1 day');
    }
  }else{
    $self->app->log->debug("[cache hit] $cachekey");
  }

  if(defined($key)){
    $self->render(text => $cacheval->{$key}, status => 200);
  }else{
    $self->render(json => { stats => $cacheval }, status => 200);
  }
}

sub stats_chart {
  my $self = shift;

  my $pid = $self->stash('pid');
  my $irsiteid = $self->param('siteid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'info', msg => 'Undefined pid' }]}, status => 400);
    return;
  }

  my $key = $self->stash('stats_param_key');

  my $fr = undef;
  if(exists($self->app->config->{frontends})){
    for my $f (@{$self->app->config->{frontends}}){
      if(defined($f->{frontend_id}) && $f->{frontend_id} eq 'ir'){
        $fr = $f;
      }
    }
  }

  unless(defined($fr)){
    # return 200, this is just ok
    $self->render(json => { alerts => [{ type => 'info', msg => 'Frontend is not configured' }]}, status => 200);
    return;
  }
  unless($fr->{frontend_id} eq 'ir'){
    # return 200, this is just ok
    $self->render(json => { alerts => [{ type => 'info', msg => 'Frontend ['.$fr->{frontend_id}.'] is not supported' }]}, status => 200);
    return;
  }
  unless(defined($fr->{stats})){
    # return 200, this is just ok
    $self->render(json => { alerts => [{ type => 'info', msg => 'Statistics source is not configured' }]}, status => 200);
    return;
  }
  # only piwik now
  unless($fr->{stats}->{type} eq 'piwik'){
    # return 200, this is just ok
    $self->render(json => { alerts => [{ type => 'info', msg => 'Statistics source ['.$fr->{stats}->{type}.'] is not supported.' }]}, status => 200);
    return;
  }
  unless($irsiteid){
    unless(defined($fr->{stats}->{siteid})){
      $self->render(json => { alerts => [{ type => 'info', msg => 'Piwik siteid is not configured' }]}, status => 500);
      return;
    }
    $irsiteid = $fr->{stats}->{siteid};
  }

  my $cachekey = 'statschart_'.$irsiteid.'_'.$pid;
  my $cacheval = $self->app->chi->get($cachekey);

  unless($cacheval){

    $self->app->log->debug("[cache miss] $cachekey");

    my $pidnum = $pid;
    $pidnum =~ s/://g;

    my $downloads;
    my $sth = $self->app->db_stats_phaidra_catalyst->prepare("SELECT DATE_FORMAT(server_time,'%Y-%m-%d') FROM piwik_log_link_visit_action INNER JOIN piwik_log_action on piwik_log_action.idaction = piwik_log_link_visit_action.idaction_url WHERE idsite = $irsiteid AND (piwik_log_action.name like '%download/$pid%')") or $self->app->log->error("Error querying piwik database for download stats chart:".$self->app->db_stats_phaidra_catalyst->errstr);
    $sth->execute() or $self->app->log->error("Error querying piwik database for download stats chart:".$self->app->db_stats_phaidra_catalyst->errstr);
    my $date;
    $sth->bind_columns(undef, \$date);
    while($sth->fetch) {
      $downloads->{$date}++;
    }

    my $detail_page;
    $sth = $self->app->db_stats_phaidra_catalyst->prepare("SELECT DATE_FORMAT(server_time,'%Y-%m-%d') FROM piwik_log_link_visit_action INNER JOIN piwik_log_action on piwik_log_action.idaction = piwik_log_link_visit_action.idaction_url WHERE idsite = $irsiteid AND (piwik_log_action.name like '%download/$pid%')") or $self->app->log->error("Error querying piwik database for detail stats chart:".$self->app->db_stats_phaidra_catalyst->errstr);
    $sth->execute() or $self->app->log->error("Error querying piwik database for detail stats chart:".$self->app->db_stats_phaidra_catalyst->errstr);
    $sth->bind_columns(undef, \$date);
    while($sth->fetch) {
      $detail_page->{$date}++;
    }

    if(defined($detail_page) || defined($downloads)){
      $cacheval = { downloads => $downloads, detail_page => $detail_page };
      $self->app->chi->set($cachekey, $cacheval, '1 day');
    }
  }else{
    $self->app->log->debug("[cache hit] $cachekey");
  }

  if(defined($key)){
    $self->render(text => $cacheval->{$key}, status => 200);
  }else{
    $self->render(json => { stats => $cacheval }, status => 200);
  }
}

1;
