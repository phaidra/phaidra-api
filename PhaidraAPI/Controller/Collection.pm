package PhaidraAPI::Controller::Collection;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Collection;
use PhaidraAPI::Model::Object;

sub add_collection_members {
	
	my $self = shift;
	
	my $res = { alerts => [], status => 200 };
	
	unless(defined($self->stash('pid'))){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;		
		return;
	}	
	
	my $pid = $self->stash('pid');
	my $payload = $self->req->json;
	my $members = $payload->{members};
		
    my $members_size = scalar @{$members};
    if($members_size eq 0){
    	$self->render(json => { alerts => [{ type => 'danger', msg => 'No members provided' }]} , status => 400) ;		
		return;
    }
	
	# add members
	my @relationships;
	foreach my $member (@{$members}){
		push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasCollectionMember", object => $member->{pid} };
	}  	  	  
	my $object_model = PhaidraAPI::Model::Object->new;	  	
	my $r = $object_model->add_relationships($self, $pid, \@relationships, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	$self->render(json => $res, status => $res->{status}); 
    }
    
    # order members, if any positions are defined
    my @ordered_members;
    foreach my $member (@{$members}){
    	if(exists($member->{'pos'})){
    		push @ordered_members, $member;
    	}
	} 
	my $ordered_members_size = scalar @ordered_members;
	if($ordered_members_size > 0){		
		my $coll_model = PhaidraAPI::Model::Collection->new;
		my $r = $coll_model->order($self, $pid, \@ordered_members, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
		push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
	    $res->{status} = $r->{status};
	    if($r->{status} ne 200){
	    	$self->render(json => $res, status => $res->{status}); 
	    }			
	}
	
	$self->render(json => $res, status => $res->{status});        
}

sub remove_collection_members {
	
	my $self = shift;
	
	my $res = { alerts => [], status => 200 };
	
	unless(defined($self->stash('pid'))){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;		
		return;
	}	
	
	my $pid = $self->stash('pid');
	my $payload = $self->req->json;
	my $members = $payload->{members};
		
    my $members_size = scalar @{$members};
    if($members_size eq 0){
    	$self->render(json => { alerts => [{ type => 'danger', msg => 'No members provided' }]} , status => 400) ;		
		return;
    }
	
	# remove members
	my @relationships;
	foreach my $member (@{$members}){
		push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasCollectionMember", object => $member->{pid} };
	}  	  	  
	my $object_model = PhaidraAPI::Model::Object->new;	  	
	my $r = $object_model->purge_relationships($self, $pid, \@relationships, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
	$self->render(json => $r, status => $r->{status});
   	
}

sub set_collection_members {
	
	my $self = shift;
	
	$self->render(json => { alerts => [{ type => 'danger', msg => 'Not implemented' }]} , status => 501) ;		
	return;	
	
	unless(defined($self->stash('pid'))){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;		
		return;
	}	
	
	my $pid = $self->stash('pid');
	my $payload = $self->req->json;
	my $members = $payload->{members};
		
    my $members_size = scalar @{$members};
    if($members_size eq 0){
    	$self->render(json => { alerts => [{ type => 'danger', msg => 'No members provided' }]} , status => 400) ;		
		return;
    }
	
}

sub get_collection_members {
	my $self = shift;
	
	my $pid = $self->stash('pid');
	
	my $coll_model = PhaidraAPI::Model::Collection->new;
	my $res = $coll_model->get_members($self, $pid);
	
	$self->render(json => { alerts => $res->{alerts}, members => $res->{members} }, status => $res->{status});
}


sub order_collection_members {
	my $self = shift;
	
	my $res = { alerts => [], status => 200 };
	
	unless(defined($self->stash('pid'))){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;		
		return;
	}	
	
	my $pid = $self->stash('pid');
	my $payload = $self->req->json;
	my $members = $payload->{members};
		
    my $members_size = scalar @{$members};
    if($members_size eq 0){
    	$self->render(json => { alerts => [{ type => 'danger', msg => 'No members provided' }]} , status => 400) ;		
		return;
    }	
    
    # order members, if any positions are defined
    my @ordered_members;
    foreach my $member (@{$members}){
    	if(exists($member->{'pos'})){
    		push @ordered_members, $member;
    	}
	} 
	my $ordered_members_size = scalar @ordered_members;
	if($ordered_members_size > 0){		
		my $coll_model = PhaidraAPI::Model::Collection->new;
		my $r = $coll_model->order($self, $pid, \@ordered_members, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
		push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
	    $res->{status} = $r->{status};
	    if($r->{status} ne 200){
	    	$self->render(json => $res, status => $res->{status}); 
	    }			
	}
			
	$self->render(json => $res, status => $res->{status});   
}

sub order_collection_member {
	my $self = shift;
	
	my $res = { alerts => [], status => 200 };
	
	unless(defined($self->stash('pid'))){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined collection pid' }]} , status => 400) ;		
		return;
	}
	
	unless(defined($self->stash('itempid'))){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined item pid' }]} , status => 400) ;		
		return;
	}		
	
	unless(defined($self->stash('position'))){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined position' }]} , status => 400) ;		
		return;
	}
	
	unless($self->stash('position') =~ m/\d+/){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Position must be a numeric value' }]} , status => 400) ;		
		return;
	}			
	
	my $pid = $self->stash('pid');
	my $itempid = $self->stash('itempid');
	my $position = $self->stash('position');				
	
	my $coll_model = PhaidraAPI::Model::Collection->new;
		
	my $r = $coll_model->get_members($self, $pid);
	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
	$res->{status} = $r->{status};
	if($r->{status} ne 200){
	   	$self->render(json => $res, status => $res->{status}); 
	}
	
	my @ordered_members = @{$r->{members}};

	my $i = 0;
	my $update_index = 1;

	my @new_order;
	# insert item to new position
	$new_order[$position] = { pid => $itempid, 'pos' => $position };
	foreach my $m (@ordered_members){
		
		if ($i eq $position){
			# skip the place in new_order where we already inserted the new item
			$i++;
		}	
		if($m->{pid} eq $itempid){			
			# skip the item in ordered_members we already inserted			
			next;
		}		
		if($m->{pid}){	
			$new_order[$i] = { pid => $m->{pid}, 'pos' => $i };
			$i++;			
		}
		
	}
		
	$r = $coll_model->order($self, $pid, \@new_order, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
	$res->{status} = $r->{status};
	if($r->{status} ne 200){
	   	$self->render(json => $res, status => $res->{status}); 
	}				
			
	$self->render(json => $res, status => $res->{status});   
}

sub create {
	
	my $self = shift;

	my $label = $self->param('label');
	my $v = $self->param('mfv');
	
	my $payload = $self->req->json;
	my $uwmetadata = $payload->{uwmetadata};
	my $rights = $payload->{rights};
	my $members = $payload->{members};
	
	# default
	unless(defined($v)){
		$v = '1';	
	}

	unless(defined($v)){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Unknown metadata format version specified' }]} , status => 500) ;
		return;
	}
	unless($v eq '1'){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Unsupported metadata format version specified' }]} , status => 500) ;		
		return;
	}		
	unless(defined($uwmetadata)){		
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata provided' }]} , status => 500) ;		
		return;
	}

	my $coll_model = PhaidraAPI::Model::Collection->new;
	
=cut	
	$self->render_later;
	my $delay = Mojo::IOLoop->delay( 
	
		sub {
			my $delay = shift;
			my $r = $coll_model->create($self, $label, $uwmetadata, $rights, $members, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password}, $delay->begin);		
			$self->render(json => $r, status => $r->{status});					
		},
		
		sub { 	
	  		my ($delay, $r) = @_;	
			$self->app->log->debug($self->app->dumper($r));			
			$self->render(json => $r, status => $r->{status});	
  		}
	
	);
	$delay->wait unless $delay->ioloop->is_running;
=cut	
	
	my $r = $coll_model->create($self, $label, $uwmetadata, $rights, $members, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});		
	$self->render(json => $r, status => $r->{status});
}





1;
