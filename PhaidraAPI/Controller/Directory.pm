package PhaidraAPI::Controller::Directory;

use strict;
use warnings;
use v5.10;

use base 'Mojolicious::Controller';

sub get_org_units {
    my $self = shift;  	

	my $parent_id = $self->param('parent_id');
	
	my $res = $self->app->directory->get_org_units($self, $parent_id);
	
	if(exists($res->{alerts})){
		if($res->{status} != 200){
			# there are only alerts
			$self->render(json => { alerts => $res->{alerts} }, status => $res->{status} ); 
		}else{
			# there are results and alerts
			$self->render(json => { org_units => $res->{org_units}, alerts => $res->{alerts}}, status => 200 );	
		}
	}
	
	# there are only results
    $self->render(json => { org_units => $res->{org_units} }, status => 200 );
}

1;
