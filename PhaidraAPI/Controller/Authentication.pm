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
	my $upstream_auth_success = 0;
	if($self->app->config->{authentication}->{upstream}->{enabled}){

		$self->app->log->debug("Trying to extract upstream authentication");

		my $remoteuser = $self->req->headers->header($self->app->config->{authentication}->{upstream}->{principalheader});
		
		if($remoteuser){
			$self->app->log->debug("remote user: ".$remoteuser);

			my $upstreamusername;
			my $upstreampassword; 
			($upstreamusername, $upstreampassword) = $self->extract_basic_auth_credentials();

			my $configupstreamusername = $self->app->config->{authentication}->{upstream}->{upstreamusername};
			my $configupstreampassword = $self->app->config->{authentication}->{upstream}->{upstreampassword};

			if(
					defined($upstreamusername) && 
					defined($upstreampassword) &&
					defined($configupstreamusername) &&
					defined($configupstreampassword) &&
					($upstreamusername eq $configupstreamusername) && 
					($upstreampassword eq $configupstreampassword)
			){
				$self->app->log->debug("upstream credentials OK");
				$self->stash->{basic_auth_credentials} = { username => $self->app->config->{authentication}->{upstream}->{fedorausername}, password => $self->app->config->{authentication}->{upstream}->{fedorapassword} };
				$self->stash->{remote_user} = $remoteuser;
				my $remoteaffiliation = $self->req->headers->header($self->app->config->{authentication}->{upstream}->{affiliationheader});
				if($remoteaffiliation){
					$self->stash->{remote_affiliation} = $remoteaffiliation;
					$self->app->log->debug("remote affiliation: ".$remoteaffiliation);
				}
				$upstream_auth_success = 1;
			}else{
				# the request contains the principal header with a remote user definition but it has wrong upstream auth credentials
				$self->render(json => { status => 500, alerts => [{ type => 'danger', msg => 'upstream authentication failed' }]} , status => 500) ;
		    return 0;
			}

		}else{
		
			# this is ok, even if upstream auth is enabled, someone can send a non-upstream-auth request
			$self->app->log->debug("upstream authentication failed: missing principal header");
		}

	}

	unless($upstream_auth_success){
		
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
				my $t = $self->tx->req->headers->header($self->app->config->{authentication}->{token_header});
				my $errmsg;
				if($t){
					$errmsg = 'session invalid or expired'
				}else{
					$errmsg = 'no credentials found'
				}
		    	$self->app->log->error($errmsg);
		    	# If I use the realm the browser does not want to show the prompt!
		    	# $self->res->headers->www_authenticate('Basic "'.$self->app->config->{authentication}->{realm}.'"');
		    	$self->res->headers->www_authenticate('Basic');
		    	$self->render(json => { status => 401, alerts => [{ type => 'danger', msg => $errmsg }]} , status => 401) ;
		    	return 0;
		    }
		}else{
			return 1;
		}

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
	if($session->sid){
		$self->render(json => { expires => $session->expires, sid => $session->sid, status => 200  } , status => 200 ) ;
	} else {		
		$self->res->headers->www_authenticate('Basic');
		$self->render(json => { status => 401, alerts => [{ type => 'danger', msg => 'session invalid or expired' }]} , status => 401) ;	
	}	
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
    	$self->render(json => { status => $res->{status}, alerts => $res->{alerts} } , status => $res->{status}) ;
    	return 0;    		
    }    
    $self->app->log->info("User $username successfully authenticated");
    return 1;
}

sub authenticate_admin {

	my $self = shift;

	my $username = $self->stash->{basic_auth_credentials}->{username};
	my $password = $self->stash->{basic_auth_credentials}->{password};
	
    unless( ($username eq $self->app->config->{phaidra}->{adminusername}) && ($password eq $self->app->config->{phaidra}->{adminpassword})){    
    	$self->app->log->info("Not authenticated");	
    	$self->render(json => { status => 403, alerts => [{ type => 'danger', msg => "Not authenticated" }]}, status => 403 );
    	return 0;    		
    }    
    $self->app->log->info("Admin successfully authenticated");
    return 1;
}

sub signin {
	
	my $self = shift;
		
	# get credentials
	my $auth_header = $self->req->headers->authorization;    
    unless($auth_header)
    {
    	$self->res->headers->www_authenticate('Basic "'.$self->app->config->{authentication}->{realm}.'"');
    	$self->render(json => { status => 401, alerts => [{ type => 'danger', msg => 'please authenticate' }]} , status => 401);
    	return;
    }    
    my ($method, $str) = split(/ /,$auth_header);
    my ($username, $password) = split(/:/, b($str)->b64_decode);
    # authenticate, return 401 if authentication failed
    $self->directory->authenticate($self, $username, $password);
    my $res = $self->stash('phaidra_auth_result');
    unless(($res->{status} eq 200)){    
    	$self->app->log->info("User $username not authenticated");	
    	$self->render(json => { status => $res->{status}, alerts => $res->{alerts}} , status => $res->{status});
    	return;    		
    }    
    $self->app->log->info("User $username successfully authenticated");
    
	# init session, save credentials
	$self->save_cred($username, $password);
	my $session = $self->stash('mojox-session');

	# sent token cookie	
	my $cookie = Mojo::Cookie::Response->new;
    $cookie->name($self->app->config->{authentication}->{token_cookie})->value($session->sid);
    $cookie->secure(1);
    $self->tx->res->cookies($cookie);
    
    $self->render(json => { status => $res->{status}, alerts => [], $self->app->config->{authentication}->{token_cookie} => $session->sid} , status => $res->{status}) ;    
}

sub signout {
	my $self = shift;
	
	# destroy session
	my $session = $self->stash('mojox-session');
	$session->load;
	if($session->sid){	
		$session->expire;							
		$session->flush;	
		$self->render(json => { status => 200, alerts => [{ type => 'success', msg => 'You have been signed out' }], sid => $session->sid }, status => 200);
	}else{
		$self->render(json => { status => 200, alerts => [{ type => 'info', msg => 'No session found' }]}, status => 200);
	}
	
}

1;
