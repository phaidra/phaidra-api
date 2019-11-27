package PhaidraAPI::Controller::Utils;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Search;

sub get_video_key {
      my $self = shift;
      my $pid = shift;
  	  my $map_record;

      my $res = { alerts => [], status => 200 };

      if(exists($self->app->config->{paf_mongodb})){
        my $video_coll = $self->paf_mongo->db->collection('video.map');
        if($video_coll){
          $map_record = $video_coll->find({pid => $pid})->sort({ "_updated" => -1})->next;
        }
      }
      my $video_key;
	    my $errormsg;
	    if (defined ($map_record) && !exists ($map_record->{error})) {
				if ($map_record->{state} eq 'Active') {
				  if ($map_record->{acc_code} eq 'public') {
				    if (exists ($map_record->{video0_status})) {
						  if ($map_record->{video0_status} eq 'ok') {
				        if (exists ($map_record->{job_action})) {
							    if ($map_record->{job_action} eq 'erledigt') {
							      $res->{video_key} = $map_record->{key};
								  } elsif ($map_record->{job_action} eq 'erstellt') {
                    $errormsg = 'currently processed:'. $map_record->{job_id};
                    $res->{status} = 503;
						      } else { 
                    $errormsg = 'not yet available: '. $map_record->{job_action};
                    $res->{status} = 503;
                  }
					      } else {
							    $res->{video_key} = $map_record->{key};
				        }
						  } elsif ($map_record->{video0_status} eq 'tbq') {
							  $errormsg = 'tbq';
                $res->{status} = 503;
							} else {
				        $errormsg = 'video not ok: '. $map_record->{video0_status};
                $res->{status} = 500;
						  }
					  }
				  } else {
            $errormsg = 'restricted';
            $res->{status} = 403;
          }
			  } else { 
          $errormsg = 'Inactive';
          $res->{status} = 400;
        }
	    } else {
        $errormsg = 'unavaliable';
        $res->{status} = 404;
      }
      if ($errormsg) {
        push @{$res->{alerts}}, { type => 'danger', msg => $errormsg };
      }
      
			return $res;
}

sub streamingplayer {
  my $self = shift;
  my $pid = $self->stash('pid');
  if($self->config->{streaming}){
    my $r = $self->get_video_key($pid);
    if ($r->{status} eq 200) {
      $self->stash( video_key => $r->{video_key} );
      $self->stash( errormsg => $r->{errormsq} );
      $self->stash( server => $self->config->{streaming}->{server} );
      $self->stash( server_rtmp => $self->config->{streaming}->{server_rtmp} );
      $self->stash( server_cd => $self->config->{streaming}->{server_cd} );
      $self->stash( basepath => $self->config->{streaming}->{basepath} );
    } else {
      $self->app->log->error("Video key not available: ".$self->app->dumper($r));
      $self->render(text => $self->app->dumper($r), status => $r->{status});
    }
  }else{
    $self->render(text => "stremaing not configured", status => 503);
  }
}

sub streamingplayer_key {
  my $self = shift;
  my $pid = $self->stash('pid');
  if($self->config->{streaming}){
    my $r = $self->get_video_key($pid);
    if ($r->{status} eq 200) {
      $self->render(text => $r->{video_key}, status => 200);
    } else {
      $self->app->log->error("Video key not available: ".$self->app->dumper($r));
      $self->render(text => $self->app->dumper($r), status => $r->{status});
    }
  }else{
    $self->render(text => "stremaing not configured", status => 503);
  }
}

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
    # skip handles
    next if(@{$statement}[2] =~ m/hdl/);

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

1;
