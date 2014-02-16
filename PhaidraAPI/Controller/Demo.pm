package PhaidraAPI::Controller::Demo;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';

sub submitform {
    my $self = shift;  	
    $self->render();	
}

sub uwmetadataeditor_full {
    my $self = shift;  	       
    $self->render('demo/uwmetadataeditor/full');	
}

sub portal {
    my $self = shift;  	 
    my $cu = $self->current_user();
    
    unless($self->flash('redirect_to')){
    	# if no redirect was set, reload the current url (portal)
    	$self->flash({redirect_to => $self->req->url});
    }      
        
    $self->render('demo/portal');	
}


1;
