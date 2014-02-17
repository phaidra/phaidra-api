package PhaidraAPI::Controller::Authentication;

use strict;
use warnings;
use v5.10;
use Mojo::ByteStream qw(b);
use base 'Mojolicious::Controller';

sub extract_basic_auth_credentials {
	
	my $self = shift;
	
	my $auth_header = $self->req->headers->authorization;
    
    # this should not happen, we are using this login method only on frontend
    # where we generate the request ourselves
    unless($auth_header)
    {
    	$self->res->headers->www_authenticate('Basic "'.$self->app->config->{authentication}->{realm}.'"');
    	$self->render(json => { alerts => [{ type => 'danger', msg => 'no authorization header' }]} , status => 401) ;
    	return 0;
    }
    
    my ($method, $str) = split(/ /,$auth_header);
    
    my ($username, $password) = split(/:/, b($str)->b64_decode);	
    
    unless(defined($username) && defined($password)){
    	$self->res->headers->www_authenticate('Basic "'.$self->app->config->{authentication}->{realm}.'"');
    	$self->render(json => { alerts => [{ type => 'danger', msg => 'no credentials found' }]} , status => 401) ;
    	return 0;
    }
    
    $self->stash->{basic_auth_credentials} = { username => $username, password => $password };
    return 1;
}



1;
