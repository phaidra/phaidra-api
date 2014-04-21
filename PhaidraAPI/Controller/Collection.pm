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
	
	my $res = { alerts => [], status => 200 };
	
	# get members
	my $search_model = PhaidraAPI::Model::Search->new;
	my $sr = $search_model->triples($self, "<info:fedora/$pid> <info:fedora/fedora-system:def/relations-external#hasCollectionMember> *");
	push @{$res->{alerts}}, $sr->{alerts} if scalar @{$sr->{alerts}} > 0;
	$res->{status} = $sr->{status};
	if($sr->{status} ne 200){
		$self->render(json => $res, status => $res->{status}); 
	}	
	
	if($sr->{status} ne 200){
		$self->render(json => $sr, status => $sr->{status});
		return;
	}
	my @members;
	foreach my $statement (@{$sr->{result}}){
		@{$statement}[2] =~ m/^\<info:fedora\/([a-zA-Z\-]+:[0-9]+)\>$/g;
		push @members, $1;
	}
	
	# get order definition
	my $object_model = PhaidraAPI::Model::Object->new;
	my $ores = $object_model->get_datastream($self, $pid, 'COLLECTIONORDER', $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
	push @{$res->{alerts}}, $ores->{alerts} if scalar @{$ores->{alerts}} > 0;
	$res->{status} = $ores->{status};
	if($ores->{status} ne 200){
		$self->render(json => $res, status => $res->{status}); 
	}	
	
	# order members
	my $xml = Mojo::DOM->new($ores->{COLLECTIONORDER});	
	my @ordered_members;
	$xml->find('member[pos]')->each(sub { 
		my $m = shift;
		push @ordered_members, { pid => $m->text, 'pos' => $m->{'pos'} };		
	});	
	@ordered_members = sort { $a->{'pos'} <=> $b->{'pos'} } @ordered_members; 
	
	$self->render(json => { members => \@ordered_members }, status => $res->{status});
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

sub create {
	
	my $self = shift;

	my $label = $self->param('label');
	my $v = $self->param('mfv');
	
	my $payload = $self->req->json;
	my $uwmetadata = $payload->{uwmetadata};
	my $rights = $payload->{rights};
	my $members = $payload->{members};

	unless(defined($v)){		
		$self->stash( msg => 'Unknown metadata format version specified');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;
		return;
	}
	unless($v eq '1'){		
		$self->stash( msg => 'Unsupported metadata format version specified');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
		return;
	}		
	unless(defined($uwmetadata)){		
		$self->stash( msg => 'No metadata provided');
		$self->app->log->error($self->stash->{msg}); 	
		$self->render(json => { alerts => [{ type => 'danger', msg => $self->stash->{msg} }]} , status => 500) ;		
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
