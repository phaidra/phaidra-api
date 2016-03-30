package PhaidraAPI::Model::Hooks;

use strict;
use warnings;
use v5.10;
use utf8;
use base qw/Mojo::Base/;
use Mojo::ByteStream qw(b);
use PhaidraAPI::Model::Dc;
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Search;
 
sub add_or_modify_datastream_hooks {

  my ($self, $c, $pid, $dsid, $dscontent, $username, $password) = @_;

  my $res = { alerts => [], status => 200 };

  if ($dsid eq "UWMETADATA" ) {

      my $dc_model = PhaidraAPI::Model::Dc->new;      
      $res = $dc_model->generate_dc_from_uwmetadata($c, $pid, $dscontent, $username, $password);
  
  }elsif ( $dsid eq "MODS") {          
  
      my $dc_model = PhaidraAPI::Model::Dc->new;      
      $res = $dc_model->generate_dc_from_mods($c, $pid, $dscontent, $username, $password);
  
  }

  return $res;
}

sub add_or_modify_relationships_hooks {

  my ($self, $c, $pid, $username, $password) = @_;

  my $res = { alerts => [], status => 200 };

  my $dc_model = PhaidraAPI::Model::Dc->new;
  my $object_model = PhaidraAPI::Model::Object->new;
  my $search_model = PhaidraAPI::Model::Search->new;
  my $r = $search_model->datastreams_hash($c, $pid);
  if($r->{status} ne 200){
    return $r;
  }

  #$c->app->log->debug("XXXXXXXXXXXXXXXXXXXXX: ".$c->app->dumper($r->{dshash}));

  if(exists($r->{dshash}->{'UWMETADATA'})){
    $res = $object_model->get_datastream($c, $pid, 'UWMETADATA', $username, $password);
    if($res->{status} ne 200){
      return $res;
    }  
    $res->{UWMETADATA} = b($res->{UWMETADATA})->decode('UTF-8');
    return $dc_model->generate_dc_from_uwmetadata($c, $pid, $res->{UWMETADATA}, $username, $password);          
  }

  if(exists($r->{dshash}->{'MODS'})){
    $res = $object_model->get_datastream($c, $pid, 'MODS', $username, $password);
    if($res->{status} ne 200){
      return $res;
    }  
    $res->{MODS} = b($res->{MODS})->decode('UTF-8');
    return $dc_model->generate_dc_from_mods($c, $pid, $res->{MODS}, $username, $password);    
  }

  return $res;
}

1;
__END__
