package PhaidraAPI::Model::Search;

use strict;
use warnings;
use v5.10;
use XML::Parser::PerlSAX;
use Mojo::IOLoop;
use Mojo::IOLoop::Delay;
use base qw/Mojo::Base/;

sub triples {
	my $self = shift;
	my $c = shift;
	my $query = shift;
	my $limit = shift;
	
	my $res = { alerts => [], status => 200 };
	
	my %params;
	$params{dt} = 'on';
	$params{lang} = 'spo';
	$params{format} = 'N-Triples';
	$params{limit} = $limit if $limit;
	$params{query} = $query;
	$params{type} = 'triples';	
	
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/risearch");
	$url->query(\%params);
	
	my $tx = $c->ua->post($url);

	if (my $reply = $tx->success) {
		
		my @a;
		my $str = $reply->body;		
		while($str =~ /([^\n]+)\n?/g){
			my @spo = split(' ', $1);
        	push @a, [$spo[0], $spo[1], $spo[2]];
		};
		 
		$res->{result} = \@a;
					  		
	}else{
		my ($err, $code) = $tx->error;
		unshift @{$res->{alerts}}, { type => 'danger', msg => "$err"};			
		$res->{status} = 500;								
	}	
	
	return $res;
}

sub datastream_exists {
	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $dsid = shift;
	
	my $res = { alerts => [], status => 200 };
	
	my $triplequery = "<info:fedora/$pid> <info:fedora/fedora-system:def/view#disseminates> <info:fedora/$pid/$dsid>";
	
	my %params;
	$params{dt} = 'on';
	$params{format} = 'count';
	$params{lang} = 'spo';
	$params{limit} = '1';
	$params{query} = $triplequery;
	$params{type} = 'triples';	
	
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/risearch");
	$url->query(\%params);
	
	my $tx = $c->ua->post($url);

	if (my $reply = $tx->success) {
		$res->{'exists'} = scalar ($reply->body);			  		
	}else{
		my ($err, $code) = $tx->error;
		unshift @{$res->{alerts}}, { type => 'danger', msg => "$err"};			
		$res->{status} = 500;								
	}	
	
	return $res;
}

# org.apache.lucene.analysis.core.StopAnalyzer
my @english_stopwords = (
 "a", "an", "and", "are", "as", "at", "be", "but", "by",
 "for", "if", "in", "into", "is", "it",
 "no", "not", "of", "on", "or", "such",
 "that", "the", "their", "then", "there", "these",
 "they", "this", "to", "was", "will", "with"
);

my %english_stopwords_hash = map { $_ => 1 } @english_stopwords;

sub build_query {
	my($self, $c, $query) = @_;
	my $q;
	
	my @words = split(' ', $query);
	
	# currently only title
	$q = "(((uw.general.title:("; 
	foreach my $w (@words){
		next if(exists($english_stopwords_hash{$w}));
		$w = $self->check_word($c, $w);
		$q .= "+$w~0.8";
	}
	$q .= ")^4)))";	
	
	return $q;
}

sub check_word() {
	my($self, $c, $w) = @_;
	
	$w =~ s/\\/\\\\/g;
	$w =~ s/\:/\\\:/g;
	$w =~ s/\"/\\\"/g;
	$w =~ s/\+/\\\+/g;
	$w =~ s/\-/\\\-/g;
	$w =~ s/\&\&/\\\&\\\&/g;
	$w =~ s/\|\|/\\\|\\\|/g;
	$w =~ s/\!/\\\!/g;
	$w =~ s/\(/\\\(/g;
	$w =~ s/\)/\\\)/g;
	$w =~ s/\{/\\\{/g;
	$w =~ s/\}/\\\}/g;
	$w =~ s/\[/\\\[/g;
	$w =~ s/\]/\\\]/g;
	$w =~ s/\^/\\\^/g;
	$w =~ s/\~/\\\~/g;

	# wildchards not allowed as first char
	# see: http://lucene.apache.org/
	$w =~ s/^\*|^\?//g;
	# delete special chars
	$w =~ s/\,|\.|\;|\_|\=|\!|\N{U+00B0}|\$|\%|\&|\/|\|\N{U+2032}|\N{U+00A7}/ /g;
		
	return $w;
}

sub search {
	
	my($self, $c, $query, $from, $limit, $sort, $reverse, $cb) = @_;
	
	my $res = { alerts => [], status => 200 };

	# never reverse relevance
	$reverse = 1 if (defined ($sort) && $sort =~ m/SCORE/);	

	if($sort){
		$sort = "$sort,".($reverse ? 'true' : 'false');
	}

	my $hitPageStart = $from;
	my $hitPageSize = $limit;
	my $snippetsMax = 0;
	my $fieldMaxLength = 200;
	my $restXslt = 'copyXml';
	my $sortFields = defined($sort) ? $sort : 'fgs.lastModifiedDate,STRING,false';
	my $fields = [ 'PID', 'fgs.contentModel', 'fgs.createdDate', 'fgs.lastModifiedDate', 'uw.general.title', 'uw.general.title.de', 'uw.general.title.en', 'uw.general.description', 'uw.general.description.de', 'uw.general.description.en', 'uw.digitalbook.name_magazine', 'uw.digitalbook.from_page', 'uw.digitalbook.to_page', 'uw.digitalbook.volume', 'uw.digitalbook.edition', 'uw.digitalbook.releaseyear', 'uw.digitalbook.booklet', 'dc.creator', 'uw.lifecycle.contribute.entity.firstname', 'uw.lifecycle.contribute.entity.institution' ];

	my $url = Mojo::URL->new;
	$url->scheme('https');			
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
