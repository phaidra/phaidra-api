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
use PhaidraAPI::Model::Membersorder;

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

    eval {
      if(ref $metadata eq 'Mojo::Upload'){
        $self->app->log->debug("Metadata sent as file param");
        $metadata = $metadata->asset->slurp;
        $self->app->log->debug("parsing json");
        $metadata = decode_json($metadata);
      }else{
        # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
        $self->app->log->debug("parsing json");
        $metadata = decode_json(b($metadata)->encode('UTF-8'));
      }
    };

    if($@){
      $self->app->log->error("Error: $@");
      unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
      $res->{status} = 400;
      $self->render(json => $res , status => $res->{status});
      return;
    }

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
	push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;

    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	$self->render(json => $res, status => $res->{status});
    	return;
    }


	my $order_available = 0;
	for my $m_ord (@{$members}){
		if(exists($m_ord->{pos})){
			$order_available = 1;
			last;
		}
	}

	if($order_available){

		# this should now also contain the new members
		my $coll_model = PhaidraAPI::Model::Collection->new;
  		my $res = $coll_model->get_members($self, $pid);
  		for my $m (@{$res->{members}}){
  			for my $m_ord (@{$members}){
  				if($m->{pid} eq $m_ord->{pid}){
  					if(exists($m_ord->{pos})){
  						$m->{pos} = $m_ord->{pos};
  					}
  				}
  			}
  		}

		my $membersorder_model = PhaidraAPI::Model::Membersorder->new;
		my $r = $membersorder_model->save_to_object($self, $pid, $res->{members}, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
		push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
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

    eval {
      if(ref $metadata eq 'Mojo::Upload'){
        $self->app->log->debug("Metadata sent as file param");
        $metadata = $metadata->asset->slurp;
        $self->app->log->debug("parsing json");
        $metadata = decode_json($metadata);
      }else{
        # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
        $self->app->log->debug("parsing json");
        $metadata = decode_json(b($metadata)->encode('UTF-8'));
      }
    };

    if($@){
      $self->app->log->error("Error: $@");
      unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
      $res->{status} = 400;
      $self->render(json => $res , status => $res->{status});
      return;
    }

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
		push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasCollectionMember", object => "info:fedora/".$member->{pid} };
	}
	my $object_model = PhaidraAPI::Model::Object->new;
	my $r = $object_model->purge_relationships($self, $pid, \@relationships, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

	# FIXME: remove from COLLECTIONORDER
	my $search_model = PhaidraAPI::Model::Search->new;
	my $r2 = $search_model->datastreams_hash($self, $pid);
	if($r2->{status} ne 200){
	  return $r2;
	}

	if(exists($r2->{dshash}->{'COLLECTIONORDER'})){

		# this should not contain the deleted members anymore
		my $coll_model = PhaidraAPI::Model::Collection->new;
  	my $res = $coll_model->get_members($self, $pid);

		my $membersorder_model = PhaidraAPI::Model::Membersorder->new;
		my $r3 = $membersorder_model->save_to_object($self, $pid, $res->{members}, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
		push @{$res->{alerts}}, @{$r3->{alerts}} if scalar @{$r3->{alerts}} > 0;
	  $res->{status} = $r3->{status};
	  if($r3->{status} ne 200){
	    	$self->render(json => $res, status => $res->{status});
	  }
	}

	$self->render(json => $r, status => $r->{status});

}

sub get_collection_members {

	my $self = shift;

	my $pid = $self->stash('pid');
	my $nocache = $self->param('nocache');

	my $coll_model = PhaidraAPI::Model::Collection->new;
	my $res = $coll_model->get_members($self, $pid, $nocache);

	$self->render(json => { alerts => $res->{alerts}, metadata => { members => $res->{members} } }, status => $res->{status});
}

sub create {

	my $self = shift;

	my $res = { alerts => [], status => 200 };

	my $metadata = $self->param('metadata');
	unless(defined($metadata)){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent' }]} , status => 400) ;
		return;
	}

    eval {
      if(ref $metadata eq 'Mojo::Upload'){
        $self->app->log->debug("Metadata sent as file param");
        $metadata = $metadata->asset->slurp;
        $self->app->log->debug("parsing json");
        $metadata = decode_json($metadata);
      }else{
        # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
        $self->app->log->debug("parsing json");
        $metadata = decode_json(b($metadata)->encode('UTF-8'));
      }
    };

    if($@){
      $self->app->log->error("Error: $@");
      unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
      $res->{status} = 400;
      $self->render(json => $res , status => $res->{status});
      return;
    }

	unless(defined($metadata->{metadata})){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata found' }]} , status => 400) ;
		return;
	}
	$metadata = $metadata->{metadata};
	my $members;
	unless(defined($metadata->{members})){
		push @{$res->{alerts}}, { type => 'warning', msg => 'No members sent' };
	}else{
		$members = $metadata->{members};
	}

	my $coll_model = PhaidraAPI::Model::Collection->new;
	my $r = $coll_model->create($self, $metadata, $members, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

	push @{$r->{alerts}}, $res->{alerts} if scalar @{$res->{alerts}} > 0;

	$self->render(json => $r, status => $r->{status});
}





1;
