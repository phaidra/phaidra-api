package PhaidraAPI::Controller::Info;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Metadata;

sub metadata_format {
    my $self = shift;

  	my $metadata = { abc => 'xx' };
	
	my $metadata_model = PhaidraAPI::Model::Metadata->new;
	
    $self->render(json => $metadata_model->metadata_format($self));
}

1;
