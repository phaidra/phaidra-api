package PhaidraAPI::Controller::Mods;

use strict;
use warnings;
use v5.10;
use Mojo::UserAgent;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Mods;
use PhaidraAPI::Model::Uwmetadata;
use Time::HiRes qw/tv_interval gettimeofday/;

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
