package PhaidraAPI::Model::Object;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;

sub delete {
	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };
=cut 
	my $fedoraurl = $c->app->config->{phaidra}->{fedorabaseurl};
	my $url = "https://$username:$password"."@"."$fedoraurl/fedora/objects/$pid?state=D";
	
	$c->app->log->debug("XXX url:".$url);
	
	my $ua = Mojo::UserAgent->new;
  	my $put = $ua->put($url => {} => form => { state => 'D' } );
  	if (my $r = $put->success) {  
  		unshift @{$res->{alerts}}, { type => 'success', msg => $r->body };
  	}
	else {
	  my ($err, $code) = $put->error;
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	  $res->{status} =  $code;
	}
=cut  	
  	return $res;	
}

sub modify {
	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $state = shift;
    my $label = shift;
    my $ownerid = shift; 
    my $logmessage = shift; 
    my $lastmodifieddate = shift;
    my $username = shift;
    my $password = shift;
    
    my $params = {
		state => $state,
		label => $label, 
		ownerid => $ownerid,
		logmessage => $logmessage,
		lastmodifieddate => $lastmodifieddate
	};
    
    my $res = { alerts => [], status => 200 };
	
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid");
	$url->query($params);
	
	$c->app->log->debug("Params:\n".$c->app->dumper($params));

	my $ua = Mojo::UserAgent->new;
  	my $put = $ua->put($url);
  	if (my $r = $put->success) {  
  		unshift @{$res->{alerts}}, { type => 'success', msg => $r->body };
  	}
	else {
	  my ($err, $code) = $put->error;
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	  $res->{status} =  $code ? $code : 500;
	}
  	
  	return $res;	
}


1;
__END__
