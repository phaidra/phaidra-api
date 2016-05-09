package PhaidraAPI::Controller::Imageserver;

use strict;
use warnings;
use v5.10;
use Mango 0.24;
use base 'Mojolicious::Controller';
use Digest::SHA qw(hmac_sha1_hex);

sub process {

  my $self = shift;  

  my $pid = $self->stash('pid');

  my $hash = hmac_sha1_hex($pid, $self->app->config->{imageserver}->{hash_secret});

  $self->paf_mongo->db->collection('jobs')->insert({pid => $pid, agent => "pige", status => "new", idhash => $hash, created => time });      

  my $res = $self->paf_mongo->db->collection('jobs')->find_one({pid => $pid});

  $self->render(json => $res, status => 200);

}

sub status {

  my $self = shift;  

  my $pid = $self->stash('pid');

  my $res = $self->paf_mongo->db->collection('jobs')->find_one({pid => $pid});

  $self->render(json => $res, status => 200);

}

1;
