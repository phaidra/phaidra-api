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
    $self->render('demo/portal');	
}


1;
