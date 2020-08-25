package PhaidraAPI::Model::Octets;

use strict;
use warnings;
use v5.10;
use XML::LibXML;
use base qw/Mojo::Base/;

sub _get_octets_path(){
  my $self = shift;
  my $c = shift;
  my $pid = shift;

  my $res = { alerts => [], status => 200 };

  my $ss = "SELECT token, path FROM datastreamPaths WHERE token like '$pid+OCTETS%';";
  my $sth = $c->app->db_fedora->prepare($ss);
  unless ($sth) {
    my $msg = $c->app->db_fedora->errstr;
    $c->app->log->error($msg);
    $res->{status} = 500;
    unshift @{$res->{alerts}}, { type => 'danger', msg => $msg};
    return $res
  }
  my $ex = $sth->execute();
  unless($ex){
    my $msg = $c->app->db_fedora->errstr;
    $c->app->log->error($msg);
    $res->{status} = 500;
    unshift @{$res->{alerts}}, { type => 'danger', msg => $msg};
    return $res
  }

  my $token; # o:9+OCTETS+OCTETS.0
  my $path; # /usr/local/fedora/data/datastreams/2018/0201/15/07/o_9+OCTETS+OCTETS.0
  my $latestVersion = -1;
  my $latestPath;
  $sth->bind_columns(undef, \$token, \$path);
  while($sth->fetch) {
    $token =~ /OCTETS\.(\d+)/;
    if ($1 gt $latestVersion) {
      $latestVersion = $1;
      $latestPath = $path
    }
  }

  if ($latestPath) {
    $res->{path} = $latestPath;
  } else {
    $res->{status} = 404;
    unshift @{$res->{alerts}}, { type => 'danger', msg => 'OCTETS datastream path not found'};
  }

  return $res;
}

1;
__END__
