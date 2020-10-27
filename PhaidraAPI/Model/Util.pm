package PhaidraAPI::Model::Util;

use strict;
use warnings;
use v5.10;
use XML::LibXML;
use base qw/Mojo::Base/;

sub validate_xml() {

  my $self    = shift;
  my $c       = shift;
  my $xml     = shift;
  my $xsdpath = shift;

  my $res = {alerts => [], status => 200};

  unless (-f $xsdpath) {
    unshift @{$res->{alerts}}, {type => 'danger', msg => "Cannot find XSD files: $xsdpath"};
    $res->{status} = 500;
  }

  my $schema = XML::LibXML::Schema->new(location => $xsdpath);
  my $parser = XML::LibXML->new;

  eval {

    $c->app->log->debug("Validating: " . $xml);

    my $document = $parser->parse_string($xml);

    #$c->app->log->debug("Validating: ".$document->toString(1));

    $schema->validate($document);
  };

  if ($@) {
    $c->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, {type => 'danger', msg => $@};
    $res->{status} = 400;
  }
  else {
    $c->app->log->info("Validation passed.");
  }

  return $res;
}

sub get_video_key {
  my $self = shift;
  my $c    = shift;
  my $pid  = shift;
  my $map_record;

  my $res = {alerts => [], status => 200};

  if (exists($c->app->config->{paf_mongodb})) {
    my $video_coll = $c->paf_mongo->db->collection('video.map');
    if ($video_coll) {
      $map_record = $video_coll->find({pid => $pid})->sort({"_updated" => -1})->next;
    }
  }
  my $video_key;
  my $errormsg;
  if (defined($map_record) && !exists($map_record->{error})) {
    if ($map_record->{state} eq 'Active') {
      if ($map_record->{acc_code} eq 'public') {
        if (exists($map_record->{video0_status})) {
          if ($map_record->{video0_status} eq 'ok') {
            if (exists($map_record->{job_action})) {
              if ($map_record->{job_action} eq 'erledigt') {
                $res->{video_key} = $map_record->{key};
              }
              elsif ($map_record->{job_action} eq 'erstellt') {
                $errormsg = 'currently processed:' . $map_record->{job_id};
                $res->{status} = 503;
              }
              else {
                $errormsg = 'not yet available: ' . $map_record->{job_action};
                $res->{status} = 503;
              }
            }
            else {
              $res->{video_key} = $map_record->{key};
            }
          }
          elsif ($map_record->{video0_status} eq 'tbq') {
            $errormsg = 'tbq';
            $res->{status} = 503;
          }
          else {
            $errormsg = 'video not ok: ' . $map_record->{video0_status};
            $res->{status} = 500;
          }
        }
      }
      else {
        $errormsg = 'restricted';
        $res->{status} = 403;
      }
    }
    else {
      $errormsg = 'Inactive';
      $res->{status} = 400;
    }
  }
  else {
    $errormsg = 'unavaliable';
    $res->{status} = 404;
  }
  if ($errormsg) {
    push @{$res->{alerts}}, {type => 'danger', msg => $errormsg};
  }
  return $res;
}

1;
__END__
