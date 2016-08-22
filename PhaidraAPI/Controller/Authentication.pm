package PhaidraAPI::Controller::Authentication;

use strict;
use warnings;
use v5.10;
use Mojo::ByteStream qw(b);
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Object;

sub extract_credentials {
	my $self = shift;
	
	my $username;
	my $password; 
	
	# try to find basic authentication
	$self->app->log->debug("Trying to extract basic authentication");
	($username, $password) = $self->extract_basic_auth_credentials();
	if(defined($username) && defined($password)){
		$self->app->log->info("User $username, basic authentication provided");
	    $self->stash->{basic_auth_credentials} = { username => $username, password => $password };
	    return 1;
	}
    
    # try to find token session
    $self->app->log->debug("Trying to extract token authentication");
    my $cred = $self->load_cred;	
	$username = $cred->{username};
	$password = $cred->{password};
	if(defined($username) && defined($password)){
		$self->app->log->info("User $username, token authentication provided");
	    $self->stash->{basic_auth_credentials} = { username => $username, password => $password };
	    return 1;
	}	
	
	if($self->stash('must_be_present')){  
	    unless(defined($username) && defined($password)){
	    	$self->app->log->info("No authentication provided");
	    	$self->res->headers->www_authenticate('Basic "'.$self->app->config->{authentication}->{realm}.'"');
	    	$self->render(json => { alerts => [{ type => 'danger', msg => 'no credentials found' }]} , status => 401) ;
	    	return 0;
	    }
	}else{
		return 1;
	}
}

sub extract_basic_auth_credentials {
	
	my $self = shift;
	
	my $auth_header = $self->req->headers->authorization;

    return unless($auth_header);    
    
    my ($method, $str) = split(/ /,$auth_header);
    
    return split(/:/, b($str)->b64_decode);	    
}

sub keepalive {
	my $self = shift;
	my $session = $self->stash('mojox-session');
	$session->load;
	unless($session->sid){		
		$session->create;		
	}	
	$self->render(json => { expires => $session->expires } , status => 200 ) ;
}

sub cors_preflight {
	my $self = shift;
	# headers are set in after_dispatch, 
	# because these are needed for the actual request as well
	# not just for preflight		
	$self->render(text => '', status => 200) ;	
}

sub authenticate {

	my $self = shift;

	my $username = $self->stash->{basic_auth_credentials}->{username};
	my $password = $self->stash->{basic_auth_credentials}->{password};
	
	$self->directory->authenticate($self, $username, $password);
    my $res = $self->stash('phaidra_auth_result');
    unless(($res->{status} eq 200)){    
    	$self->app->log->info("User $username not authenticated");	
    	$self->render(json => { alerts => $res->{alerts}} , status => $res->{status}) ;
    	return 0;    		
    }    
    $self->app->log->info("User $username successfuly authenticated");
    return 1;
}

sub authenticate_admin {

	my $self = shift;

	my $username = $self->stash->{basic_auth_credentials}->{username};
	my $password = $self->stash->{basic_auth_credentials}->{password};
	
    unless( ($username eq $self->app->config->{phaidra}->{adminusername}) && ($password eq $self->app->config->{phaidra}->{adminpassword})){    
    	$self->app->log->info("Not authenticated");	
    	$self->render(json => { alerts => [{ type => 'danger', msg => "Not authenticated" }]}, status => 403 );
    	return 0;    		
    }    
    $self->app->log->info("Admin successfuly authenticated");
    return 1;
}

sub signin {
	
	my $self = shift;
		
	# get credentials
	my $auth_header = $self->req->headers->authorization;    
    unless($auth_header)
    {
    	$self->res->headers->www_authenticate('Basic "'.$self->app->config->{authentication}->{realm}.'"');
    	$self->render(json => { alerts => [{ type => 'danger', msg => 'please authenticate' }]} , status => 401);
    	return;
    }    
    my ($method, $str) = split(/ /,$auth_header);
    my ($username, $password) = split(/:/, b($str)->b64_decode);
    # authenticate, return 401 if authentication failed
    $self->directory->authenticate($self, $username, $password);
    my $res = $self->stash('phaidra_auth_result');
    unless(($res->{status} eq 200)){    
    	$self->app->log->info("User $username not authenticated");	
    	$self->render(json => { alerts => $res->{alerts}} , status => $res->{status});
    	return;    		
    }    
    $self->app->log->info("User $username successfuly authenticated");
    
	# init session, save credentials
	my $session = $self->stash('mojox-session');
	$session->load;
	unless($session->sid){		
		$session->create;		
	}	
	$self->save_cred($username, $password);

	# sent token cookie	
	my $cookie = Mojo::Cookie::Response->new;
    $cookie->name($self->app->config->{authentication}->{token_cookie})->value($session->sid);
    $cookie->secure(1);
    $self->tx->res->cookies($cookie);
    
    $self->render(json => { alerts => [], $self->app->config->{authentication}->{token_cookie} => $session->sid} , status => $res->{status}) ;    
}

sub signout {
	my $self = shift;
	
	# destroy session
	my $session = $self->stash('mojox-session');
	$session->load;
	if($session->sid){	
		$session->expire;							
		$session->flush;	

		$self->render(json => { alerts => [{ type => 'success', msg => 'You have been signed out' }]}, status => 200);
	}else{
		$self->render(json => { alerts => [{ type => 'info', msg => 'No session found' }]}, status => 200);
	}
	
}

sub check_rights {

	my $self = shift;
	my $op = $self->stash('op');
	my $pid = $self->stash('pid');

	my $ds;
	if($op eq 'ro'){
		$ds = 'READONLY';
	}elsif($op eq 'rw'){
		$ds = 'READWRITE';
	}else{
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Unknown operation to check' }]} , status => 400);
		return;
	}

	my $object_model = PhaidraAPI::Model::Object->new;
    my $res = $object_model->get_datastream($self, $pid, $ds, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

    if($res->{status} eq '404'){
    	$self->render(json => { status => '200' },status => 200);   
    }else{
    	$res->{status} = '403';
    	$self->render(json => $res, status => 403);
    }    

}

1;
