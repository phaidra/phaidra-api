package PhaidraAPI::Model::Collection;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Object;

sub create {
	
	my $self = shift;
    my $c = shift;
    my $label = shift;
    my $metadata = shift;
    my $rights = shift;
    my $members = shift;
    my $username = shift;
    my $password = shift;
    my $cb = shift;
    
    my $res = { alerts => [], status => 200 };
    
    # create object
    my $pid;
    my $object_model = PhaidraAPI::Model::Object->new;
    my $res_create = $object_model->create($c, 'cmodel:Collection', $label, $username, $password);    
    if($res_create->{status} ne 200){		
		return $res_create;
	}
	$pid = $res->{pid};
    
    # set rights
    #if($rights){
    #	my $res_rights = $object_model->set_rights($pid, $rights, $username, $password);
    #	if($res_rights->{status} ne 200){		
	#		return $res_rights;
	#	}
    #}		
    
    # add metadata (just uwmetadata now)
    my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;	
	my $res_md = $metadata_model->save_to_object($c, $pid, $metadata, $username, $password);	
	if($res_md->{status} ne 200){		
		return $res_md;
	}
     
    # activate
    my $res_act = $object_model->modify($c, $pid, 'A', undef, undef, undef, undef, $username, $password);
    
	$res->{pid} = $pid;
	
  	return $self->$cb($res);	

}


1;
__END__
