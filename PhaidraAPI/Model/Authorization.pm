package PhaidraAPI::Model::Authorization;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use PhaidraAPI::Model::Object;

sub check_rights {

  my ($self, $c, $pid, $op) = @_;

  my $res = { alerts => [], status => 200 };

  my $ds;
  if($op eq 'ro'){
    $ds = 'READONLY';
  }elsif($op eq 'rw'){
    $ds = 'READWRITE';
  }else{
    $res->{alerts} = [{ type => 'danger', msg => 'Unknown operation to check' }];
    $res->{status} = 400;
    return $res;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  my $getres = $object_model->get_datastream($c, $pid, $ds, $c->stash->{basic_auth_credentials}->{username}, $c->stash->{basic_auth_credentials}->{password});

  if($getres->{status} eq 404){
    $c->app->log->info("Authz op[$op] pid[$pid] username[".$c->stash->{basic_auth_credentials}->{username}."] successful");
    return $res;
  }else{
    $c->app->log->info("Authz op[$op] pid[$pid] username[".$c->stash->{basic_auth_credentials}->{username}."] failed");	
    $res->{status} = 403;
    $res->{json} = $getres;
    push @{$res->{alerts}}, @{$getres->{alerts}} if scalar @{$getres->{alerts}} > 0;
    return $res;
  }

}

1;
__END__
