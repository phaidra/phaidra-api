package PhaidraAPI::Controller::Uwmetadata;

use strict;
use warnings;
use v5.10;
use Mojo::UserAgent;
use Mojo::Util 'squish';
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Uwmetadata;
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
		$self->render(json => { alerts => $res->{alerts} }, $res->{status});
	}

	my $languages = $metadata_model->get_languages($self);

	my $t1 = tv_interval($t0);
	#$self->stash( msg => "backend load took $t1 s");

    $self->render(json => { uwmetadata => $res->{uwmetadata}, languages => $languages}); #, alerts => [{ type => 'success', msg => $self->stash->{msg}}]});
}

sub json2xml {
	my $self = shift;

	my $res = { alerts => [], status => 200 };

	#my $t0 = [gettimeofday];

	my $payload = $self->req->json;
	my $uwmetadatajson = $payload->{uwmetadata};

	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
	my $uwmetadataxml = $metadata_model->json_2_uwmetadata($self, $uwmetadatajson);

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

sub post {
	my $self = shift;

	my $t0 = [gettimeofday];

	my $pid = $self->stash('pid');

	my $payload = $self->req->json;
  
	my $uwmetadata = $payload->{uwmetadata};

	unless(defined($pid)){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
		return;
	}

	unless(defined($uwmetadata)){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'No data sent' }]} , status => 400) ;
		return;
	}

	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
	my $res = $metadata_model->save_to_object($self, $pid, $uwmetadata, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

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

	my $languages = $metadata_model->get_languages($self);

	my $res = $metadata_model->metadata_tree($self,$nocache);
	if($res->{status} ne 200){
		$self->render(json => { alerts => $res->{alerts} }, $res->{status});
	}

	my $t1 = tv_interval($t0);
	$self->stash( msg => "backend load took $t1 s");

    $self->render(json => { tree => $res->{metadata_tree}, languages => $languages, alerts => $res->{alerts} }, status => $res->{status});
}

sub languages {
	my $self = shift;

	# get metadata datastructure
	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
	my $languages = $metadata_model->get_languages($self);

    $self->render(json => { languages => $languages});
}

1;
