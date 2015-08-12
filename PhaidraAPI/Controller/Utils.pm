package PhaidraAPI::Controller::Utils;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::JSON qw(decode_json);
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Dc;
use PhaidraAPI::Model::Search;

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

1;
