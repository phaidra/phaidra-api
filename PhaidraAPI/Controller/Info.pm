package PhaidraAPI::Controller::Info;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Metadata;

sub metadata_format {
    my $self = shift;  	
	
	my $v = $self->param('mfv');
	
	unless(defined($v)){		
		$self->stash( 'message' => 'Unknown metadata format version requested.');
		$self->app->log->error($self->stash->{'message'}); 	
		$self->render(json => { message => $self->stash->{'message'}} , status => 500) ;		
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


sub languages {
	my $self = shift;
	
	# get metadata datastructure
	my $metadata_model = PhaidraAPI::Model::Metadata->new;	
	my $metadata = $metadata_model->get_languages($self);
			
    $self->render(json => $metadata);	
}


1;
