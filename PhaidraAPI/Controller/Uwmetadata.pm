package PhaidraAPI::Controller::Uwmetadata;

use strict;
use warnings;
use v5.10;
use Mojo::UserAgent;
use Mojo::Util 'squish';
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Uwmetadata;
use PhaidraAPI::Model::Util;
use Time::HiRes qw/tv_interval gettimeofday/;

sub get {
    my $self = shift;

	my $t0 = [gettimeofday];

	my $pid = $self->stash('pid');

	unless(defined($pid)){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

	# get metadata datastructure
	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
	my $res= $metadata_model->get_object_metadata($self, $pid, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
	if($res->{status} ne 200){
		$self->render(json => { alerts => $res->{alerts} }, status => $res->{status});
    return;
	}

  my $lres = $metadata_model->get_languages($self);
  if($lres->{status} ne 200){
    $self->render(json => { alerts => $lres->{alerts} }, $lres->{status});
    return;
  }

	my $t1 = tv_interval($t0);
	#$self->stash( msg => "backend load took $t1 s");

    $self->render(json => { uwmetadata => $res->{uwmetadata}, languages => $lres->{languages}}, status => $res->{status}); #, alerts => [{ type => 'success', msg => $self->stash->{msg}}]});
}

sub json2xml {
	my $self = shift;

	my $res = { alerts => [], status => 200 };

	#my $t0 = [gettimeofday];

	my $payload = $self->req->json;
	my $metadata = $payload->{metadata};

	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
	my $uwmetadataxml = $metadata_model->json_2_uwmetadata($self, $metadata->{uwmetadata});

	#my $t1 = tv_interval($t0);
	#$self->app->log->debug("json2xml took $t1 s");

	$self->render(json => { alerts => $res->{alerts}, uwmetadata => $uwmetadataxml } , status => $res->{status});
}

sub xml2json {
	my $self = shift;

	#my $t0 = [gettimeofday];

	my $uwmetadataxml = $self->req->body;

	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
	my $res = $metadata_model->uwmetadata_2_json($self, $uwmetadataxml);

	#my $t1 = tv_interval($t0);
	#$self->app->log->debug("xml2json took $t1 s");
#$self->app->log->debug("XXXXXXXXXXX: ".$self->app->dumper($res));
	$self->render(json => { uwmetadata => $res->{uwmetadata}, alerts => $res->{alerts}}  , status => $res->{status});

}

sub validate {
	my $self = shift;

	my $uwmetadataxml = $self->req->body;

  my $util_model = PhaidraAPI::Model::Util->new;
  my $res = $util_model->validate_xml($self, $uwmetadataxml, $self->app->config->{validate_uwmetadata});

	$self->render(json => $res , status => $res->{status});
}

sub json2xml_validate {
	my $self = shift;

	my $payload = $self->req->json;
	my $metadata = $payload->{metadata};

	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
	my $uwmetadataxml = $metadata_model->json_2_uwmetadata($self, $metadata->{uwmetadata});
  my $util_model = PhaidraAPI::Model::Util->new;
  my $res = $util_model->validate_xml($self, $uwmetadataxml, $self->app->config->{validate_uwmetadata});

	$self->render(json => $res , status => $res->{status});
}

sub post {
	my $self = shift;

	my $t0 = [gettimeofday];

	my $pid = $self->stash('pid');

	my $payload = $self->req->json;
	my $metadata = $payload->{metadata};

	unless(defined($pid)){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

	unless(defined($metadata->{uwmetadata})){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No uwmetadata sent' }]} , status => 400) ;
		return;
	}

	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
	my $res = $metadata_model->save_to_object($self, $pid, $metadata->{uwmetadata}, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

	my $t1 = tv_interval($t0);
	if($res->{status} eq 200){
		unshift @{$res->{alerts}}, { type => 'success', msg => "UWMETADATA for $pid saved successfuly"};
	}

	$self->render(json => { alerts => $res->{alerts} } , status => $res->{status});
}

sub tree {
    my $self = shift;

	my $t0 = [gettimeofday];

	my $nocache = $self->param('nocache');

	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
  my $languages_model = PhaidraAPI::Model::Languages->new;

  my $lres = $languages_model->get_languages($self);
  if($lres->{status} ne 200){
    $self->render(json => { alerts => $lres->{alerts} }, $lres->{status});
    return;
  }

	my $res = $metadata_model->metadata_tree($self,$nocache);
	if($res->{status} ne 200){
		$self->render(json => { alerts => $res->{alerts} }, $res->{status});
    return;
	}

	my $t1 = tv_interval($t0);
	$self->stash( msg => "backend load took $t1 s");

  $self->render(json => { tree => $res->{metadata_tree}, languages => $lres->{languages}, alerts => $res->{alerts} }, status => $res->{status});
}

1;
