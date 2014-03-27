package PhaidraAPI::Model::Search;

use strict;
use warnings;
use v5.10;
use XML::Parser::PerlSAX;
use Mojo::IOLoop;
use Mojo::IOLoop::Delay;
use base qw/Mojo::Base/;

sub search_simple_query {
	my $self = shift;
	my $c = shift;
	
	my $query = shift;
	my $from = shift;
	my $limit = shift;
	
	
}

sub search {
	
	my $self = shift;
	my $c = shift;
	my $query = shift;
	my $from = shift;
	my $limit = shift;
	my $cb = shift;
	
	my $res = { alerts => [], status => 200 };

	my $hitPageStart = $from;
	my $hitPageSize = $limit;
	my $snippetsMax = 0;
	my $fieldMaxLength = 200;
	my $restXslt = 'copyXml';
	my $sortFields = 'fgs.createdDate,STRING';
	my $fields = [ 'PID', 'uw.general.title', 'uw.general.title.de', 'uw.general.title.en', 'uw.general.description', 'uw.general.description.de', 'uw.general.description.'.$c->session->{language}, 'uw.digitalbook.name_magazine', 'uw.digitalbook.from_page', 'uw.digitalbook.to_page', 'uw.digitalbook.volume', 'uw.digitalbook.edition', 'uw.digitalbook.releaseyear', 'uw.digitalbook.booklet', 'dc.creator', 'uw.lifecycle.contribute.entity.firstname', 'uw.lifecycle.contribute.entity.institution' ];

	my $url = Mojo::URL->new;
	$url->scheme('https');		
	$url->userinfo($c->stash->{basic_auth_credentials}->{username}.":".$c->stash->{basic_auth_credentials}->{password});
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/gsearch/rest/");	
	$url->query({
		operation => 'gfindObjects',
		query => $query,
		hitPageStart => $hitPageStart,
		hitPageSize => $hitPageSize,
		snippetsMax => 200,
		fieldMaxLength => $fieldMaxLength,
		restXslt => $restXslt,
		sortFields => $sortFields
	});
	
	my @result;
	
	my $tx = $c->ua->get($url);

	if (my $reply = $tx->success) {
		my $xml = $reply->body;
		$xml =~ s/<\?xml version="1.0" encoding="UTF-16"\?>/<?xml version="1.0" encoding="UTF-8"?>/;
		
		my $saxhandler = PhaidraAPI::Model::Search::GSearchSAXHandler->new($fields, \@result);
		my $parser = XML::Parser::PerlSAX->new(Handler => $saxhandler);	  		
		  		
		$parser->parse($xml);
		$res->{hits} = $saxhandler->get_hitTotal();
		$res->{objects} = \@result;
		  		
	}else{
		my ($err, $code) = $tx->error;
		unshift @{$res->{alerts}}, { type => 'danger', msg => "$err"};			
		$res->{status} = 500;								
	}	  	
		
	return $self->$cb($res);	
}

1;
__END__
