package PhaidraAPI::Controller::Collection;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(encode decode);
use Mojo::ByteStream qw(b);
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

	my $metadata = $self->param('metadata');
	unless(defined($metadata)){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent' }]} , status => 400) ;
		return;
	}
	$metadata = decode_json(b($metadata)->encode('UTF-8'));
	unless(defined($metadata->{metadata})){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata found' }]} , status => 400) ;
		return;
	}
	$metadata = $metadata->{metadata};
	unless(defined($metadata->{members})){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No members sent' }]} , status => 400) ;
		return;
	}
	my $members = $metadata->{members};

    my $members_size = scalar @{$members};
    if($members_size eq 0){
    	$self->render(json => { alerts => [{ type => 'danger', msg => 'No members provided' }]} , status => 400) ;
		return;
    }

	# add members
	my @relationships;
	foreach my $member (@{$members}){
		push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasCollectionMember", object => "info:fedora/".$member->{pid} };
	}
	my $object_model = PhaidraAPI::Model::Object->new;
	my $r = $object_model->add_relationships($self, $pid, \@relationships, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
	if(scalar @{$r->{alerts}} > 0){
			foreach $a (@{$r->{alerts}}){
					push @{$res->{alerts}}, $a;
			}
	}

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
	my $metadata = $self->param('metadata');
	unless(defined($metadata)){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent' }]} , status => 400) ;
		return;
	}
	$metadata = decode_json(b($metadata)->encode('UTF-8'));
	unless(defined($metadata->{metadata})){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata found' }]} , status => 400) ;
		return;
	}
	$metadata = $metadata->{metadata};
	unless(defined($metadata->{members})){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No members sent' }]} , status => 400) ;
		return;
	}
	my $members = $metadata->{members};

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

	# FIXME: remove from COLLECTIONORDER

	$self->render(json => $r, status => $r->{status});

}

sub get_collection_members {

	my $self = shift;

	my $pid = $self->stash('pid');

	my $coll_model = PhaidraAPI::Model::Collection->new;
	my $res = $coll_model->get_members($self, $pid);

	$self->render(json => { alerts => $res->{alerts}, metadata => { members => $res->{members} } }, status => $res->{status});
}


sub order_collection_members {
	my $self = shift;

	my $res = { alerts => [], status => 200 };

	unless(defined($self->stash('pid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

	my $pid = $self->stash('pid');
	my $metadata = $self->param('metadata');
	unless(defined($metadata)){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent' }]} , status => 400) ;
		return;
	}
	$metadata = decode_json(b($metadata)->encode('UTF-8'));
	unless(defined($metadata->{metadata})){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata found' }]} , status => 400) ;
		return;
	}
	$metadata = $metadata->{metadata};
	unless(defined($metadata->{members})){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No members sent' }]} , status => 400) ;
		return;
	}
	my $members = $metadata->{members};

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

	my $metadata = $self->param('metadata');
	unless(defined($metadata)){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent' }]} , status => 400) ;
		return;
	}
	$metadata = decode_json(b($metadata)->encode('UTF-8'));
	unless(defined($metadata->{metadata})){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata found' }]} , status => 400) ;
		return;
	}
	$metadata = $metadata->{metadata};
	unless(defined($metadata->{members})){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No members sent' }]} , status => 400) ;
		return;
	}
	my $members = $metadata->{members};


	my $coll_model = PhaidraAPI::Model::Collection->new;
	my $r = $coll_model->create($self, $metadata, $members, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

	$self->render(json => $r, status => $r->{status});
}





1;
