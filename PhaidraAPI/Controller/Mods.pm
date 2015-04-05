package PhaidraAPI::Controller::Mods;

use strict;
use warnings;
use v5.10;
use Mojo::UserAgent;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Mods;
use PhaidraAPI::Model::Uwmetadata;
use Time::HiRes qw/tv_interval gettimeofday/;

sub get {
  my $self = shift;

  #my $t0 = [gettimeofday];

  my $pid = $self->stash('pid');
  my $mode = $self->param('mode');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $mods_model = PhaidraAPI::Model::Mods->new;
  my $res= $mods_model->get_object_mods_json($self, $pid, $mode, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if($res->{status} ne 200){
    $self->render(json => { alerts => $res->{alerts} }, status => $res->{status});
    return;
  }

  #my $t1 = tv_interval($t0);
  #$self->stash( msg => "backend load took $t1 s");

  $self->render(json => $res, status => $res->{status});
}


sub tree {
    my $self = shift;

	my $t0 = [gettimeofday];

	my $nocache = $self->param('nocache');

	my $mods_model = PhaidraAPI::Model::Mods->new;
	my $uwmetadata_model = PhaidraAPI::Model::Uwmetadata->new;

	my $languages = $uwmetadata_model->get_languages($self);

	my $res = $mods_model->metadata_tree($self, $nocache);
	if($res->{status} ne 200){
		$self->render(json => { alerts => $res->{alerts} }, $res->{status});
	}

	my $t1 = tv_interval($t0);
	$self->stash( msg => "backend load took $t1 s");

    $self->render(json => { tree => $res->{mods}, vocabularies => $res->{vocabularies}, 'vocabularies_mapping' => $res->{vocabularies_mapping}, languages => $languages, alerts => $res->{alerts} }, status => $res->{status});
}

sub languages {
	my $self = shift;

	# get metadata datastructure
	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;
	my $languages = $metadata_model->get_languages($self);

    $self->render(json => { languages => $languages});
}

sub json2xml {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  #my $t0 = [gettimeofday];

  my $payload = $self->req->json;
  my $metadata = $payload->{metadata};

  my $metadata_model = PhaidraAPI::Model::Mods->new;
  my $modsxml = $metadata_model->json_2_xml($self, $metadata->{mods});

  #my $t1 = tv_interval($t0);
  #$self->app->log->debug("json2xml took $t1 s");
  #$self->app->log->debug("XXXXXXXXXXX: \n".$modsxml);
  $self->render(json => { alerts => $res->{alerts}, mods => $modsxml } , status => $res->{status});
}

sub xml2json {
  my $self = shift;

  #my $t0 = [gettimeofday];
  my $json;

  my $mode = $self->param('mode');
  my $xml = $self->req->body;

  my $mods_model = PhaidraAPI::Model::Mods->new;
  my $res = $mods_model->xml_2_json($self, $xml, $mode);

  #my $t1 = tv_interval($t0);
  #$self->app->log->debug("xml2json took $t1 s");
  #$self->app->log->debug("XXXXXXXXXXX: \n".$self->app->dumper($res));
  $self->render(json => { mods => $res->{mods}, alerts => $res->{alerts}}  , status => $res->{status});

}

sub validate {
  my $self = shift;

  my $modsxml = $self->req->body;

  my $mods_model = PhaidraAPI::Model::Mods->new;
  my $res = $mods_model->validate_mods($self, $modsxml);

  #$self->app->log->debug("XXXXXXXXXXX: ".$self->app->dumper($res));
  $self->render(json => $res , status => $res->{status});

}

sub json2xml_validate {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $payload = $self->req->json;
  my $metadata = $payload->{metadata};

  my $mods_model = PhaidraAPI::Model::Mods->new;
  my $modsxml = $mods_model->json_2_xml($self, $metadata->{mods});
  $res = $mods_model->validate_mods($self, $modsxml);

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

  unless(defined($metadata->{mods})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No MODS sent' }]} , status => 400) ;
    return;
  }

  my $metadata_model = PhaidraAPI::Model::Mods->new;
  my $res = $metadata_model->save_to_object($self, $pid, $metadata->{mods}, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  my $t1 = tv_interval($t0);
  if($res->{status} eq 200){
    unshift @{$res->{alerts}}, { type => 'success', msg => "MODS for $pid saved successfuly"};
  }

  $self->render(json => { alerts => $res->{alerts} } , status => $res->{status});
}


1;
