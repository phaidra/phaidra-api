package PhaidraAPI::Model::Hooks;

use strict;
use warnings;
use v5.10;
use utf8;
use Switch;
use base qw/Mojo::Base/;
use PhaidraAPI::Model::Dc;
 
sub add_or_modify_datastream_hooks {

  my ($self, $c, $pid, $dsid, $dscontent, $username, $password) = @_;

  my $res = { alerts => [], status => 200 };

  switch ($dsid) {

    case "UWMETADATA"	{      
      my $dc_model = PhaidraAPI::Model::Dc->new;      
      $dc_model->generate_dc_from_uwmetadata($c, $pid, $dscontent, $username, $password);
    }

    case "MODS" {          
      my $dc_model = PhaidraAPI::Model::Dc->new;      
      $dc_model->generate_dc_from_mods($c, $pid, $dscontent, $username, $password);
    }
  }
}


1;
__END__
