package PhaidraAPI::Model::Search;

use strict;
use warnings;
use v5.10;
use XML::Parser::PerlSAX;
use XML::XPath;
use Mojo::IOLoop;
use Mojo::IOLoop::Delay;
use PhaidraAPI::Model::Object;
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

sub related_objects_itql(){
	
	my ($self, $c, $subject, $relation, $right, $offset, $limit)=@_;
	
	my $res = { alerts => [], status => 200 };
	
	my $rel = '<info:fedora/'.$subject.'> <'.$relation.'> $item';
	if($right){
		$rel = '$item <'.$relation.'> <info:fedora/'.$subject.'>';
	}
	
	my $count;
	my $relcount = '
	select count(
		select $item 
		from <#ri> 
		where 
		$item <http://www.openarchives.org/OAI/2.0/itemID> $itemID and
		'.$rel.' and 
		$item <info:fedora/fedora-system:def/model#state> <info:fedora/fedora-system:def/model#Active>)
	from <#ri> 
	where 
	$item <http://www.openarchives.org/OAI/2.0/itemID> $itemID and
	'.$rel.' and 
	$item <info:fedora/fedora-system:def/model#state> <info:fedora/fedora-system:def/model#Active>';
	
	my $result = $self->risearch_tuple($c, $relcount);
	if($result->{status} ne 200){
		unshift @{$res->{alerts}}, $result->{alerts};			
		$res->{status} = $result->{status};
		return $res;			
	}
	my $xp = XML::XPath->new(xml => $res->{result});
	my $nodeset = $xp->findnodes('//result');
	foreach my $node ($nodeset->get_nodelist){				
		$count = int($node->findvalue('k0'));
		last; # should be only one
	}
	
	my $query = '
	select $itemID $title $cmodel	
	from <#ri> 
	where 
	$item <http://www.openarchives.org/OAI/2.0/itemID> $itemID and
	'.$rel.' and  
	$item <info:fedora/fedora-system:def/model#state> <info:fedora/fedora-system:def/model#Active> and 
	$item <http://purl.org/dc/elements/1.1/title> $title and
	$item <info:fedora/fedora-system:def/model#hasModel> $cmodel
	minus $cmodel <mulgara:is> <info:fedora/fedora-system:FedoraObject-3.0> 
	order by $itemID asc';
	
	if($limit){
		$query .= ' limit '.$limit;
	}
	if($offset){
		$query .= ' offset '.$offset;
	}

	$result = $self->risearch_tuple($c, $query, $offset, $limit);
	if($result->{status} ne 200){
		unshift @{$res->{alerts}}, $result->{alerts};			
		$res->{status} = $result->{status};
		return $res;			
	}
	
	my @objects;
	my $oaiid = $c->{config}->{phaidra}->{proaiRepositoryIdentifier};
	$xp = XML::XPath->new(xml => $res->{result});
	$nodeset = $xp->findnodes('//result');
	foreach my $node ($nodeset->get_nodelist){				

		my $cmodel = $node->findvalue('cmodel/@uri');
		
		if($cmodel =~ m/fedora-system/){
			next;
		}
				
		$cmodel =~ s/^info:fedora\/cmodel:(.*)$/$1/;				

		my $itemID = $node->findvalue('itemID/@uri');		
		$itemID =~ s/^info:fedora\/oai:$oaiid:(.*)$/$1/;
		$itemID =~ s/^oai:$oaiid:(.*)$/$1/; # the second format without info:fedora/, used by phaidraimporter
		
		push @objects, { 
			pid => $itemID, 
			title => $node->findvalue('title'), 
			cmodel => $cmodel
		};			
	}	
	
	$res->{objects} = \@objects;
	$res->{hits} = $count; 
	return $res;
}

sub risearch_tuple ($$$)
{
	my ($self, $c, $query, $offset, $limit) = @_;

	my $res = { alerts => [], status => 200 };
	
	my %params;
	$params{lang} = 'itql';
	$params{type} = 'tuples';
	$params{format} = 'Sparql';
	$params{limit} = $limit if $limit;
	$params{offset} = $offset if $offset;
	$params{query} = $query;
	
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/risearch");
	$url->query(\%params);
	
	my $tx = $c->ua->post($url);

	if (my $reply = $tx->success) {					
		$res->{result} = $reply->body;
					  		
	}else{
		my ($err, $code) = $tx->error;
		unshift @{$res->{alerts}}, { type => 'danger', msg => "$err"};			
		$res->{status} = 500;								
	}	
	
	return $res;

}

sub related_objects_mptmysql(){
	
	my ($self, $c, $subject, $relation, $right, $offset, $limit)=@_;

	my $res = { alerts => [], status => 200 };

	my $oaiid = $c->config->{phaidra}->{proaiRepositoryIdentifier};

	my $ss = qq/SELECT pKey, p FROM tMap/;

	my $sth = $c->app->db_triplestore->prepare($ss) or $c->app->log->error($c->app->db_triplestore->errstr);
	$sth->execute() or $c->app->log->error($c->app->db_triplestore->errstr);
	my ($num,$rel);
	$sth->bind_columns(undef, \$num, \$rel) or $c->app->log->error($c->app->db_triplestore->errstr);
	
	my %relmap;
	while($sth->fetch()){	
		$relmap{$rel} = $num; 					
	}
	$sth->finish();
	
	my $staterel = '<info:fedora/fedora-system:def/model#state>';	
	my $statetable = 't'.$relmap{$staterel};

	# if tripplestore does not know the relation or relation is no provided
	# then there are no related objects 
    unless (defined ($relation) && exists ($relmap{"<$relation>"}))
    {
    	unshift @{$res->{alerts}}, { type => 'danger', msg => "Unknown relation"};			
		$res->{status} = 400;
		return $res;
    }

	my $relationtable = 't'.$relmap{"<$relation>"};
	
	my $activestr = '<info:fedora/fedora-system:def/model#Active>';
	
	my $reljoin = "LEFT JOIN $relationtable ON $relationtable.o=$statetable.s";
	my $relwhere = "$relationtable.s=?";
	if($right){
		$reljoin = "LEFT JOIN $relationtable ON $relationtable.s=$statetable.s";
		$relwhere = "$relationtable.o=?";
	}
	
	# group by subject, because there might be multiple titles
	my $titsep = '#tit-sep#';
	$ss = "
		SELECT SQL_CALC_FOUND_ROWS $statetable.s AS subject
		FROM
		$statetable
		$reljoin
		WHERE $statetable.o = ? AND $relwhere
		GROUP BY subject
		ORDER BY $statetable.s DESC	
		";

	if($limit){
		$ss .= " LIMIT $limit";
	}
	if($offset){
		$ss .= " OFFSET $offset";
	}

	#$c->app->log->debug("Related objects query: ".$ss);
	
	$sth = $c->app->db_triplestore->prepare($ss) or $c->app->log->error($c->app->db_triplestore->errstr);
	$sth->execute($activestr, '<info:fedora/'.$subject.'>') or $c->app->log->error($c->app->db_triplestore->errstr);
	my ($pid);
	$sth->bind_columns(undef, \$pid) or $c->app->log->error($c->app->db_triplestore->errstr);

	my @objects;	
        while ($sth->fetch())
        {
          if (defined ($oaiid) && $pid =~ m#^<info:fedora/oai:$oaiid:(.*)>$#)
          {
            $pid= $1;
          }
          elsif ($pid =~ m#^<info:fedora/(.*)>$#)
          {
            $pid= $1;
          }
          else
          {
            next;
          }
				
          push @objects, { 
            pid => $pid,
            title => '',
            titles => [],
            cmodel => ''			
          };			
        }
        $sth->finish ();
	
	$ss = qq/SELECT FOUND_ROWS();/;
	$sth = $c->app->db_triplestore->prepare($ss) or $c->app->log->error($c->app->db_triplestore->errstr);
	$sth->execute() or $c->app->log->error($c->app->db_triplestore->errstr);
	my $count;
	$sth->bind_columns(undef, \$count) or $c->app->log->error($c->app->db_triplestore->errstr);	
	$sth->fetch();	
  	$sth->finish();

	# get title	 and cmodel
	my $titlerel = '<http://purl.org/dc/elements/1.1/title>';
	my $modelrel = '<info:fedora/fedora-system:def/model#hasModel>';
	#my $itemidrel = '<http://www.openarchives.org/OAI/2.0/itemID>';
	
	#my $itemidtable = 't'.$relmap{$itemidrel};
	my $titletable = 't'.$relmap{$titlerel};
	my $modeltable = 't'.$relmap{$modelrel}; 
	#
	my $fedoraobjstr = '<info:fedora/fedora-system:FedoraObject-3.0>';
	
        foreach my $o (@objects)
        {		
		$ss = qq/SELECT $titletable.o AS title, GROUP_CONCAT($titletable.o SEPARATOR '$titsep') AS titles, $modeltable.o AS cmodel FROM $titletable JOIN $modeltable ON $modeltable.s = $titletable.s WHERE $titletable.s = ? AND $modeltable.o != ?/;  #$titletable.o AS title, GROUP_CONCAT($titletable.o SEPARATOR '$titsep') AS titles, $modeltable.o AS cmodel
		$sth = $c->app->db_triplestore->prepare($ss) or $c->app->log->error($c->app->db_triplestore->errstr);
		$sth->execute('<info:fedora/'.$o->{pid}.'>', $fedoraobjstr) or $c->app->log->error($c->app->db_triplestore->errstr);

		my ($title, $titles, $cmodel);
		$sth->bind_columns(undef, \$title, \$titles, \$cmodel) or $c->app->log->error($c->app->db_triplestore->errstr);
		
		while($sth->fetch()){	
		
			my @titles = split($titsep, $titles);
			my @titles_out;
			my $session_lang = 'eng';
			my $pref_title = '';
			my $en_title = '';
			my $text = '';
			foreach my $t (@titles){
				my $lang = '';
				$text = $t;
				if($t =~ m/"@([^@]+)$/){
					$lang = $1;				
					$text =~ s/$lang$//g;
					$text =~ s/\@$//g;
					$text =~ s/^"|"$//g;
					# unicode escaped stuff to utf8					
					$text =~ s/\\u([0-9a-fA-F]{4})/pack('U', hex($1))/eg;
					
					if($lang eq $session_lang){
						$pref_title = $text;
					}
					if($lang eq 'eng'){
						$en_title = $text;
					}				
				}else{
					$text =~ s/^"|"$//g;
				}
				push @titles_out, {text => $text, lang=> $lang};
			}
			
			if($pref_title eq ''){
				if($en_title ne ''){
					$pref_title = $en_title;
				}else{
					$pref_title = $text;	
				}
			}
			
			$o->{title} = $pref_title;
			$o->{titles} = @titles_out;
			$cmodel =~ s/^<info:fedora\/(.*)>$/$1/;
			$o->{cmodel} = $cmodel; 

		}

        $sth->finish ();
    }

  	$res->{objects} = \@objects;
	$res->{hits} = $count;
	return $res;	
}

sub related {
	
	my($self, $c, $pid, $relation, $right, $from, $limit, $fields, $cb) = @_;
	
	# on frontend the first item is 1, but in triplestore its 0
	if($from > 0){
		$from--;	
	}
	
	my $from_orig;
	my $limit_orig;
	if($relation eq 'info:fedora/fedora-system:def/relations-external#hasCollectionMember'){
		# if we want to sort, we have to get them all, currently position is not in triplestore
		$from_orig = $from;
		$limit_orig = $limit;
		$from = 0;
		$limit = 0;
	}
	
	my $sr;
	if($c->config->{phaidra}->{triplestore} eq "localMysqlMPTTriplestore"){		
		$sr = $self->related_objects_mptmysql($c, $pid, $relation, $right, $from, $limit, $fields);
	}else{
		$sr = $self->related_objects_itql($c, $pid, $relation, $right, $from, $limit, $fields);
	}
	
	if($relation eq 'info:fedora/fedora-system:def/relations-external#hasCollectionMember'){
		
		my %members;
		foreach my $o (@{$sr->{objects}}){
			$o->{'pos'} = undef;	
			$members{$o->{pid}} = $o;			
		}
		
		# get order definition
		my $object_model = PhaidraAPI::Model::Object->new;		
		my $ores = $object_model->get_datastream($c, $pid, 'COLLECTIONORDER', $c->stash->{basic_auth_credentials}->{username}, $c->stash->{basic_auth_credentials}->{password});		
		if($ores->{status} ne 200){
			$c->app->log->error("Cannot get COLLECTIONORDER for pid: $pid and username: ".$c->stash->{basic_auth_credentials}->{username});
			$self->$cb($sr);
			return; 
		}	
		
		# order members
		my $xml = Mojo::DOM->new($ores->{COLLECTIONORDER});		
		$xml->find('member[pos]')->each(sub { 
			my $m = shift;
			my $pid = $m->text;
			$members{$pid}->{'pos'} = $m->{'pos'};		
		});		
				
		sub undef_sort {
		  return 1 unless(defined($a->{'pos'}));
		  return -1 unless(defined($b->{'pos'}));	
		  return $a->{'pos'} <=> $b->{'pos'};
		}
		@{$sr->{objects}} = sort undef_sort @{$sr->{objects}};

		# now use 'from' and 'limit' to return only the page		
		if($limit_orig > 0){
			@{$sr->{objects}} = splice(@{$sr->{objects}}, $from_orig, $limit_orig);
		}else{
			@{$sr->{objects}} = splice(@{$sr->{objects}}, $from_orig);
		}
		
	}

	$self->$cb($sr);	
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
	
	my($self, $c, $query, $from, $limit, $sort, $reverse, $fields, $cb) = @_;

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
	
	if(!defined($fields) || (scalar @$fields < 1)) {
		$fields = [ 'PID', 'fgs.contentModel', 'fgs.createdDate', 'fgs.lastModifiedDate', 'uw.general.title', 'uw.general.title.de', 'uw.general.title.en', 'uw.general.description', 'uw.general.description.de', 'uw.general.description.en', 'uw.digitalbook.name_magazine', 'uw.digitalbook.from_page', 'uw.digitalbook.to_page', 'uw.digitalbook.volume', 'uw.digitalbook.edition', 'uw.digitalbook.releaseyear', 'uw.digitalbook.booklet', 'dc.creator', 'uw.lifecycle.contribute.entity.firstname', 'uw.lifecycle.contribute.entity.institution' ];	
	}
	
	if($limit ne 0 && $limit < 50){
		my $res = $self->search_call($c, 'gfindObjects', $query, $hitPageStart, $hitPageSize, 200, $fieldMaxLength, $restXslt, $sortFields, $fields);
		return $self->$cb($res);	
	}else{
		# read in chunks	
		my $sr;
		my $res;
		my $from = 1;
		my $pagesize = 50; # default by gsearch anyway, so mostly it won't deliver more
		my $total = 0;
		my $read = 0;
		my $done = 1;
		my $i = 0;
		my @objects;
		while(!$done || $sr->{status} ne 200){
			$i++;			
			$done = 1;
			
			if(($read+$pagesize) > $limit && $limit ne 0){				
				$pagesize = $limit-$read;				
			}
			
			$sr = $self->search_call($c, 'gfindObjects', $query, $from, $pagesize, 200, $fieldMaxLength, $restXslt, $sortFields, $fields);
			$total = $sr->{hits};	
			
			if($sr->{status} eq 200){
				my $lenght = scalar @{$sr->{objects}};
				$read += $lenght;
				$from = $read+1; 
				
				push @objects, @{$sr->{objects}};
				if($limit eq 0){
					# we read everything
					if($read < $total){
						$done = 0;	
					}
				}else{
					# we read until limit
					if($read < $limit){
						$done = 0;	
					}
				}
			}
		}
		$res->{status} = $sr->{status};
		$res->{hits} = $sr->{hits};
		$res->{objects} = \@objects;
		
		return $self->$cb($res);
	}
		
}

sub search_call() {
	
	my ($self, $c, $operation, $query, $hitPageStart, $hitPageSize, $snippetsMax, $fieldMaxLength, $restXslt, $sortFields, $fields) = @_;
	
	my $res = { alerts => [], status => 200 };
	
	my $url = Mojo::URL->new;
	$url->scheme('https');			
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/gsearch/rest/");	
	$url->query({
		operation => $operation,
		query => $query,
		hitPageStart => $hitPageStart,
		hitPageSize => $hitPageSize,
		snippetsMax => $snippetsMax,
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
	
	return $res;
}

1;
__END__
