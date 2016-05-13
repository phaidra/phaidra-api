package PhaidraAPI::Controller::Imageserver;

use strict;
use warnings;
use v5.10;
use Mango 0.24;
use base 'Mojolicious::Controller';
use Mojo::JSON qw(encode_json decode_json);
use Mojo::ByteStream qw(b);
use Digest::SHA qw(hmac_sha1_hex);

sub process {

  my $self = shift;  

  my $pid = $self->stash('pid');

  my $hash = hmac_sha1_hex($pid, $self->app->config->{imageserver}->{hash_secret});

  $self->paf_mongo->db->collection('jobs')->insert({pid => $pid, agent => "pige", status => "new", idhash => $hash, created => time });      

  my $res = $self->paf_mongo->db->collection('jobs')->find({pid => $pid})->sort({ "created" => -1})->next;

  $self->render(json => $res, status => 200);

}

sub process_pids {

  my $self = shift;  

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

  my @results;
  for my $pid (@{$pids->{pids}}){
    my $hash = hmac_sha1_hex($pid, $self->app->config->{imageserver}->{hash_secret});
    $self->paf_mongo->db->collection('jobs')->insert({pid => $pid, agent => "pige", status => "new", idhash => $hash, created => time });
    push @results, { pid => $pid, idhash => $hash };
  }

  $self->render(json => \@results, status => 200);

}

sub status {

  my $self = shift;  

  my $pid = $self->stash('pid');

  my $res = $self->paf_mongo->db->collection('jobs')->find({pid => $pid})->sort({ "created" => -1})->next;

  $self->render(json => $res, status => 200);

}

1;
