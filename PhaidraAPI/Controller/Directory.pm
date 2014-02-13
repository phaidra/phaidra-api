package PhaidraAPI::Controller::Directory;

use strict;
use warnings;
use v5.10;
use PhaidraAPI::Model::Uwmetadata;

use base 'Mojolicious::Controller';

sub get_org_units {
    my $self = shift;  	

	my $parent_id = $self->param('parent_id');
	my $values_namespace = $self->param('values_namespace');
	
	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;	
	my $terms = $metadata_model->get_org_units_terms($self, $parent_id, $values_namespace);
	
	# there are only results
    $self->render(json => { terms => $terms }, status => 200 );
}

sub get_study {
    my $self = shift;  	

	my $spl = $self->param('spl');
	my @ids = $self->param('ids');
	my $values_namespace = $self->param('values_namespace');
	
	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;	
	my $terms = $metadata_model->get_study_terms($self, $spl, \@ids, $values_namespace);
	
    $self->render(json => { terms => $terms }, status => 200 );
}

sub get_study_name {
    my $self = shift;  	

	my $spl = $self->param('spl');
	my @ids = $self->param('ids');

	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;	
	my $names = $metadata_model->get_study_name($self, $spl, \@ids);
	
    $self->render(json => { study_name => $names }, status => 200 );
}

1;
