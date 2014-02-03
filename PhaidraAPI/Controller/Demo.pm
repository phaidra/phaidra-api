package PhaidraAPI::Controller::Demo;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Metadata;

sub submitform {
    my $self = shift;  	
    $self->render();	
}

sub metadataeditor_full {
    my $self = shift;  	       
    $self->render('demo/metadataeditor/full');	
}


1;
