package PhaidraAPI::Controller::Utils;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::JSON qw(decode_json);
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Dc;
use PhaidraAPI::Model::Search;

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
