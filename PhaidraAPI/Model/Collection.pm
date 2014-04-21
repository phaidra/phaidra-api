package PhaidraAPI::Model::Collection;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Object;

sub order {

	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $members = shift;
    my $username = shift;
    my $password = shift;
    
    my $res = { alerts => [], status => 200 };
    
    my $xml = "<co:collection_order xmlns:co=\"http://phaidra.univie.ac.at/XML/collection_order/V1.0\">";
	foreach my $m (@{$members}){
		$xml .= "<co:member pos=\"".$m->{'pos'}."\">".$m->{pid}."</co:member>"
	}
	$xml .= "</co:collection_order>";

	# does it already exists? we have to use modify instead of add method if it does
	my $search_model = PhaidraAPI::Model::Search->new;
	my $sr = $search_model->datastream_exists($c, $pid, 'COLLECTIONORDER');
	if($sr->{status} ne 200){
		unshift @{$res->{alerts}}, @{$sr->{alerts}};
		$res->{status} = $sr->{status}; 
		return $res;
	}
	
	if($sr->{'exists'}){
		
		my $object_model = PhaidraAPI::Model::Object->new;
		my $r = $object_model->modify_datastream($c, $pid, "COLLECTIONORDER", "text/xml", undef, $xml, "collection order", $username, $password);
	  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
	    $res->{status} = $r->{status};
	    if($r->{status} ne 200){
	    	return $res;
	    }
		
	}else{
		
		my $object_model = PhaidraAPI::Model::Object->new;
		my $r = $object_model->add_datastream($c, $pid, "COLLECTIONORDER", "text/xml", undef, $xml, "collection order", "X", $username, $password);
	  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
	    $res->{status} = $r->{status};
	    if($r->{status} ne 200){
	    	return $res;
	    }	
		
	}	
	
	return $res;
}

sub create {
	
	my $self = shift;
    my $c = shift;
    my $label = shift;
    my $metadata = shift;
    my $rights = shift;
    my $members = shift;
    my $username = shift;
    my $password = shift;
    #my $cb = shift;
    
    my $res = { alerts => [], status => 200 };
    
    # create object
    my $pid;
    my $object_model = PhaidraAPI::Model::Object->new;
    my $res_create = $object_model->create($c, 'cmodel:Collection', $label, $username, $password);    
    if($res_create->{status} ne 200){		
		return $res_create;
	}
	$pid = $res_create->{pid};
    
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
    
    # add members
    my $members_size = scalar @{$members};
    if($members_size > 0){
	    my @relationships;
	    foreach my $member (@{$members}){
			push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasCollectionMember", object => $member };
	    }  	  	    	
		my $r = $object_model->add_relationships($c, $pid, \@relationships, $username, $password);
	  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
	    $res->{status} = $r->{status};
	    if($r->{status} ne 200){
	    	return $res;
	    }
    }
    
	$res->{pid} = $pid;
	
	return $res;
  	#return $self->$cb($res);	

}



1;
__END__
