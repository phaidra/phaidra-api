package PhaidraAPI::Controller::Info;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Metadata;

sub metadata_format {
    my $self = shift;  	
	
	my $v = $self->param('v');
	
	unless(defined($v)){		
		$self->render(json => { message => 'Please specify the version (parameter v).'} , status => 500) ;
		return;
	}	
	
	my $metadata_model = PhaidraAPI::Model::Metadata->new;
	
	my $metadata_format = $metadata_model->metadata_format($self, $v);

	if($metadata_format == -1){
		$self->render(json => { message => $self->stash->{'message'} } , status => 500) ;
		return;
	}
	
    $self->render(json => $metadata_format);
	
}

1;
