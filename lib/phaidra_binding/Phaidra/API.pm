#!/usr/bin/perl -w
#
# Phaidra API main class.
#
# $Id: API.pm 1926 2013-09-12 12:25:12Z univie $
# $URL: https://svn.phaidra.univie.ac.at/phaidra/trunk/api/perl/Phaidra/API.pm $
#

use strict;
use warnings;

package Phaidra::API;

use Phaidra::API::SOAP::Determined;
use URI::Escape;
use Data::Dumper;
use XML::Parser::PerlSAX;
use Phaidra::API::Objekt::Book;
use Phaidra::API::Objekt::Picture;
use Phaidra::API::Objekt::Document;
use Phaidra::API::Objekt::Collection;
use Phaidra::API::Objekt::Page;
use Phaidra::API::Objekt::Audio;
use Phaidra::API::Objekt::Video;
use Phaidra::API::Objekt::Paper;
use Phaidra::API::Objekt::Container;
use Phaidra::API::Objekt::Other;
use Phaidra::API::PfindObjectsSAXHandler;
use LWP::UserAgent;
use HTTP::Request::Common 'POST';
use XML::XPath;
use XML::XPath::XMLParser;
use Log::Log4perl qw(get_logger);
use MIME::Base64;
use Time::HiRes qw/tv_interval gettimeofday/;

# Phaidra constructor
#
sub new
{
	my ($class, $fedorabaseurl, $staticbaseurl, $fedorastylesheeturl, $oaiidentifier, $username, $password) = @_;
	die("API-ERROR: undefined fedorabaseurl") if(!defined($fedorabaseurl));
	die("API-ERROR: undefiend staticbaseurl") if(!defined($staticbaseurl));
	die("API-ERROR: undefined stylesheeturl") if(!defined($fedorastylesheeturl));
	die("API-ERROR: undefined OAI identifier") if(!defined($oaiidentifier));

	my $self = {};
        my $cred = "";

	#Config Values
	$self->{config}->{staticbaseurl} = $staticbaseurl;
	$self->{config}->{fedorabaseurl} = $fedorabaseurl;
	$self->{config}->{fedorastylesheeturl} = $fedorastylesheeturl;
	$self->{config}->{proaiRepositoryIdentifier} = $oaiidentifier;

	#Default Values
	$self->{config}->{uwmetadatalabel} = "University of Vienna metadata";
	$self->{config}->{fedoraurlgetinternal} = "https://$fedorabaseurl/fedora/get";
	$self->{uploadurl} = "https://$fedorabaseurl/fedora/management/upload";

	if(defined($password))
	{
		$self->{username} = $username;
		$self->{password} = $password;
		$username = uri_escape($username);
		$password = uri_escape($password);
		$cred = "$username:$password\@";
	}
	else
	{
		# Anonym is also ok
		$cred = "";
	}

	# SOAP- and REST-Endpoints of Fedora
        $self->{config}->{fedorafindobject} = "https://$fedorabaseurl/fedora/search?";
        $self->{config}->{fedorarisearch} = "https://$fedorabaseurl/fedora/risearch?";	
	$self->{apim}->{uri} = "https://$cred".$self->{config}->{fedorabaseurl}."/fedora/services/management";
        $self->{apim}->{proxy} = "https://$cred".$self->{config}->{fedorabaseurl}."/fedora/services/management";
        $self->{apia}->{uri} = "https://$cred".$self->{config}->{fedorabaseurl}."/fedora/services/access";
        $self->{apia}->{proxy} = "https://$cred".$self->{config}->{fedorabaseurl}."/fedora/services/access";
	bless($self, $class);
	return $self;
}

# ======================================================================
# various methods for different object models
# ======================================================================

# createPicture
#
# Create a picture object (ingest!) and return it
sub createPicture
{
	my ($self, $label) = @_;

	my $object = Phaidra::API::Objekt::Picture->new($self);
	$object->ingest($label);

	return $object;
}

# loadPicture
#
# load existing picture
sub loadPicture
{
	my ($self, $pid) = @_;
	my $object = Phaidra::API::Objekt::Picture->new($self);
	$object->load($pid);

	return $object;
}

# createBook
#
# Create a book object (ingest!) and return it
sub createBook
{
	my ($self, $label) = @_;

	my $object = Phaidra::API::Objekt::Book->new($self);
	$object->ingest($label);

	return $object;
}

# createPage
#
# Create a page object (ingest!) and return it
sub createPage
{
	my ($self, $label, $book, $abspagenum, $pagenum, $structure, $startpage) = @_;

	my $object = Phaidra::API::Objekt::Page->new($self);
	$object->ingest($label, $book->{PID}, $abspagenum, $pagenum, $structure, $startpage);

	return $object;
}

# createDocument
#
#Create a document object (ingest!) and return it
sub createDocument
{
	my ($self, $label) = @_;

	my $object = Phaidra::API::Objekt::Document->new($self);
	$object->ingest($label);

	return $object;
}

# loadDocument
#
# load existing document
sub loadDocument
{
	my ($self, $pid) = @_;
	my $object = Phaidra::API::Objekt::Document->new($self);
	$object->load($pid);

	return $object;
}

# Create a paper object (ingest!) and return it
sub createPaper
{
        my ($self, $label) = @_;

        my $object = Phaidra::API::Objekt::Paper->new($self);
        $object->ingest($label);

        return $object;
}

# Load Paper object
sub loadPaper
{
        my ($self, $pid) = @_;
        my $object = Phaidra::API::Objekt::Paper->new($self);
        $object->load($pid);
        return $object;
}


# Create a container object (ingest!) and return it
sub createContainer
{
        my ($self, $label) = @_;

        my $object = Phaidra::API::Objekt::Container->new($self);
        $object->ingest($label);

        return $object;
}

# Load Container object
sub loadContainer
{
        my ($self, $pid) = @_;
        my $object = Phaidra::API::Objekt::Container->new($self);
        $object->load($pid);
        return $object;
}

# Create a general object (ingest!) and return it
sub createOther
{
        my ($self, $label) = @_;

        my $object = Phaidra::API::Objekt::Other->new($self);
        $object->ingest($label);

        return $object;
}

# loadOther
#
# load existing general object
sub loadOther
{
        my ($self, $pid) = @_;
        my $object = Phaidra::API::Objekt::Other->new($self);
        $object->load($pid);

        return $object;
}

#Create an audio object (ingest!) and return it
sub createAudio
{
        my ($self, $label) = @_;

        my $object = Phaidra::API::Objekt::Audio->new($self);
        $object->ingest($label);

        return $object;
}

# loadAudio
#
# load existing audio
sub loadAudio
{
        my ($self, $pid) = @_;
        my $object = Phaidra::API::Objekt::Audio->new($self);
        $object->load($pid);

        return $object;
}

#Create a video object (ingest!) and return it
sub createVideo
{
        my ($self, $label) = @_;

        my $object = Phaidra::API::Objekt::Video->new($self);
        $object->ingest($label);

        return $object;
}

# loadVideo
#
# load existing video
sub loadVideo
{
        my ($self, $pid) = @_;
        my $object = Phaidra::API::Objekt::Video->new($self);
        $object->load($pid);

        return $object;
}


# createCollection
#
# Create a collection object (ingest!) and return it
sub createCollection
{
	my ($self, $label) = @_;

	my $object = Phaidra::API::Objekt::Collection->new($self);
	$object->ingest($label);

	return $object;
}

# loadCollection
#
# load existing collection
sub loadCollection
{
	my ($self, $pid) = @_;
	my $object = Phaidra::API::Objekt::Collection->new($self);
	$object->load($pid);

	return $object;
}

# loadObject
#
# load generic object
sub loadObject
{
	my ($self, $pid) = @_;
	my $object = Phaidra::API::Objekt->new($self);
	$object->load($pid);

	return $object;
}

# ======================================================================
# various methods for different object models
# ======================================================================

# search
#
# Search objects using pfindObjects. Returns an array of hashes
sub search
{
	my ($self, $query, $fieldlist,$p_from,$p_chunksize) = @_;

	my $log = get_logger();

	if(!defined($fieldlist))
	{
		$fieldlist = ['PID'];
	}
	if(defined($p_from))
	{
		$log->logdie("page has to be > 0") if($p_from < 1);
	}
	if(defined($p_chunksize))
	{
		$log->logdie("number of search results per page has to be > 1") if($p_chunksize < 1);
	}

	my $chunksize = 100;
        my $from = 1;
        my $to = $from+$chunksize;
	my @userchunks = ();

	#A requester is able to submit the page from where to start search and the chunksize
	#If only page is submitted, chunksize == DEFAULT-CHUNKSIZE
	if(defined($p_chunksize))
	{
		if($p_chunksize <= $chunksize)
		{
			$chunksize = $p_chunksize;
			$userchunks[0] = $chunksize;
		}
		else
		{
			while($p_chunksize > 100)
			{
				push @userchunks,100;
				$p_chunksize -= 100;
			}	
			push @userchunks,$p_chunksize;
		}
		$from = (($p_from - 1) * $chunksize) + 1 if(defined($p_from));
	}
	elsif(defined($p_from))
	{
		$log->logdie("page has to be > 0") if($p_from < 1);
		$from = (($p_from - 1) * $chunksize) + 1;
		$userchunks[0] = $chunksize;
	}

	my @pids = ();

	my $soap = $self->getSoap('apia');
	my ($done,$hitTotal) = (0,-1);
	my $calls = 0;
	$|=1;
	while(!$done)
	{
		last if(defined($userchunks[0]) && !defined($userchunks[$calls]));
		$chunksize = $userchunks[$calls] if(defined($userchunks[$calls]));
		$calls++;
		my ($gt0, $gt1);
		$gt0=[gettimeofday];
		$log->debug("search: Searching from $from to $to");
		my $res = $soap->pfindObjects(SOAP::Data->type(string => $query), $from, $chunksize, 0, 200, 'Lucene');
		if($res->fault)
		{
			$log->logdie("pfindObjects failed: ".$res->faultcode.": ".$res->faultstring);
		}
		$gt1=tv_interval($gt0);
		$log->debug("search: call done ($gt1)");

		$gt0=[gettimeofday];
		my $saxhandler = Phaidra::API::PfindObjectsSAXHandler->new($fieldlist, \@pids);
		my $parser = XML::Parser::PerlSAX->new(Handler => $saxhandler);
		my $xml = $res->result;
		$xml =~ s/<\?xml version="1.0" encoding="UTF-16"\?>/<?xml version="1.0" encoding="UTF-8"?>/;
		$parser->parse($xml);

		$gt1=tv_interval($gt0);
		$log->debug("search: XML processing done ($gt1)");

		$done = 1;
		$hitTotal = $saxhandler->get_hitTotal() if($hitTotal < 0);
		$log->debug("search: hitTotal = $hitTotal");
		if($to < $hitTotal)
		{
			$done = 0;
			$from += $chunksize;
			$to += $chunksize;
		}
	}
	
	if(!wantarray)
	{
		return (@pids ? \@pids : undef);
	}
	else
	{
		return (\@pids,$hitTotal);
	}
}

#searchin triples with the help of RISearch
sub risearchTRIPLE ($$$)
{
	my ($self,$query) = @_;

	my ($errno,$errstr,$result) = (0,'','');

	my $log = get_logger();

	my $ua = LWP::UserAgent::Determined->new;
	my $req=undef;
	if($self->{username})
	{
		my $cred = encode_base64($self->{username}.':'.$self->{password});
	
		$req = POST $self->{config}->{fedorarisearch}."type=triples&lang=spo&format=RDF%2FXML&query=".uri_escape($query),
					    Authorization => "Basic $cred";
	}
	else
	{
		$req = POST $self->{config}->{fedorarisearch}."type=triples&lang=spo&format=RDF%2FXML&query=".uri_escape($query);
	}
	
	my $risearchFedora = $ua->request($req);
	
	if ($risearchFedora->is_success)
	{
		$result = $risearchFedora->content;
	}
	else
	{
		$errstr = $risearchFedora->status_line;
		$errno = -1;
	}
	
	return ($errno,$errstr,$result);
}

# Request an object property of the resource index. Starts a search just like
# <subject> <property> * and returns the result as a reference on a list.
#
# If $rightsearch == true -> * <property> <subject>
sub RIsearch
{
	my ($self, $subject, $property, $rightsearch)=@_;
	my @results=();
	my $query="<$subject> <$property> *";
	if($rightsearch)
	{
		$query = "* <$property> <$subject>";
	}
	my ($errno, $errstr, $result)=$self->risearchTRIPLE($query);
	my $log = get_logger();
	if($errno==0)
	{
		my $xp=XML::XPath->new(xml => $result);
		$xp->set_namespace('rdf', "http://www.w3.org/1999/02/22-rdf-syntax-ns#");
		if($rightsearch)
		{
			my $nodeset=$xp->findnodes('/rdf:RDF/rdf:Description/@rdf:about');
			foreach my $node ($nodeset->get_nodelist)
			{
				push @results, $node->string_value();
			}
		}
		else
		{
			my $nodeset=$xp->findnodes('/rdf:RDF/rdf:Description[@rdf:about="'.$subject.'"]/*/text()');
			foreach my $node ($nodeset->get_nodelist)
			{
				push @results, $node->string_value();
			}

			# Resources can be found in the tag
			$nodeset=$xp->findnodes('/rdf:RDF/rdf:Description[@rdf:about="'.$subject.'"]/*/@rdf:resource');
			foreach my $node ($nodeset->get_nodelist)
			{
				push @results, $node->string_value();
			}
		}
	}
	else
	{
		$log->logdie("RIsearch: $errstr");
	}
	return \@results;
}

sub getRelatedObjectsInfo(){
	
	my ($self, $subject, $relation, $right, $offset, $limit)=@_;
	
	my $log = get_logger();
	
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
	
	my ($errno,$errstr,$result) = $self->risearchTUPLE($relcount);
	my $xp = XML::XPath->new(xml => $result);
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

	($errno,$errstr,$result) = $self->risearchTUPLE($query, $offset, $limit);
	
	if($errno ne 0)
	{
		$log->error("getPropertyWithTitle: ".$errstr);
		return;
	}

	my @objects;
	my $oaiid = $self->{config}->{proaiRepositoryIdentifier};
	$xp = XML::XPath->new(xml => $result);
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
	
	return (\@objects, $count);
}

=head2 getAllActiveObjects

Returns all active objects with following info:
- pid
- title
- cmodel
- created
- modified

=cut
sub getAllActiveObjects(){
	
	my ($self, $offset, $limit)=@_;
	
	my $log = get_logger();
	
	my $count;
	my $countquery = '
	select count(select $item from <#ri> where $item <info:fedora/fedora-system:def/model#state> <info:fedora/fedora-system:def/model#Active>)
	from <#ri> 
	where
	$item <http://www.openarchives.org/OAI/2.0/itemID> $itemID and
	$item <info:fedora/fedora-system:def/model#state> <info:fedora/fedora-system:def/model#Active>';
	
	my ($errno,$errstr,$result) = $self->risearchTUPLE($countquery);
	
	my $xp = XML::XPath->new(xml => $result);
	my $nodeset = $xp->findnodes('//result');	
	foreach my $node ($nodeset->get_nodelist){				
		$count = int($node->findvalue('k0'));
	}	
		
	my $query = '
	select $itemID $title $cmodel $created $modified
	from <#ri> 
	where 
	$item <http://www.openarchives.org/OAI/2.0/itemID> $itemID and
	$item <info:fedora/fedora-system:def/model#state> <info:fedora/fedora-system:def/model#Active> and 
	$item <http://purl.org/dc/elements/1.1/title> $title and
	$item <info:fedora/fedora-system:def/model#createdDate> $created and
	$item <info:fedora/fedora-system:def/view#lastModifiedDate> $modified and
	$item <info:fedora/fedora-system:def/model#hasModel> $cmodel
	minus $cmodel <mulgara:is> <info:fedora/fedora-system:FedoraObject-3.0> 
	order by $modified desc';
	
	if($limit){
		$query .= ' limit '.$limit;
	}
	if($offset){
		$query .= ' offset '.$offset;
	}

	($errno,$errstr,$result) = $self->risearchTUPLE($query, $offset, $limit);
	
	if($errno ne 0)
	{
		$log->error("getAllActiveObjects: ".$errstr);
		return;
	}

	my @objects;
	my $oaiid = $self->{config}->{proaiRepositoryIdentifier};
	$xp=XML::XPath->new(xml => $result);
	$nodeset=$xp->findnodes('//result');	
	foreach my $node ($nodeset->get_nodelist){				

		my $cmodel = $node->findvalue('cmodel/@uri');
		
		if($cmodel =~ m/fedora-system/){
			next;
		}
				
		$cmodel =~ s/^info:fedora\/cmodel:(.*)$/$1/;				

		my $itemID = $node->findvalue('itemID/@uri');		
		$itemID =~ s/^info:fedora\/oai:$oaiid:(.*)$/$1/;
		
		push @objects, { 
			pid => $itemID, 
			title => $node->findvalue('title'), 
			cmodel => $cmodel,
			created => $node->findvalue('created'),
			modified => $node->findvalue('modified'), 
		};			
	}	
	
	return (\@objects, $count);
}

sub risearchTUPLE ($$$)
{
	my ($self,$query, $offset, $limit) = @_;

	my ($errno,$errstr,$result) = (0,'','');

	my $log = get_logger();

	my $ua = LWP::UserAgent::Determined->new;
	my $req=undef;
	
	my $params = 'type=tuples&lang=itql&format=Sparql';	
	
	$log->debug("tuple query:\n".$query);
		
	if($self->{username})
	{
		my $cred = encode_base64($self->{username}.':'.$self->{password});
	
		$req = POST $self->{config}->{fedorarisearch}.$params."&query=".uri_escape($query),
					    Authorization => "Basic $cred";
	}
	else
	{
		$req = POST $self->{config}->{fedorarisearch}.$params."&query=".uri_escape($query);
	}
	
	my $risearchFedora = $ua->request($req);
	
	if ($risearchFedora->is_success)
	{
		$result = $risearchFedora->content;
	}
	else
	{
		$errstr = $risearchFedora->status_line;
		$errno = -1;
	}
	
	return ($errno,$errstr,$result);
}

sub getSoap
{
	my ($self, $api) = @_;

	my $soap = Phaidra::API::SOAP::Determined->uri($self->{$api}->{uri})->proxy($self->{$api}->{proxy});
	return $soap;
}

# change no thing, just create an update so that
# info:fedora/fedora-system:def/view#lastModifiedDate
# gets updated
sub touchObject
{
	my ($self, $pid) = @_;

	my $log = get_logger();

	$log->info("touching object: ".$pid);
	my $res = $self->getSoap("apim")->modifyObject($pid, undef, undef, undef, SOAP::Data->type(string => 'touchObject by Phaidra API'));
	
	if($res->fault)
	{
		$log->logdie("modifyObject failed: ".$res->faultcode.": ".$res->faultstring);
	}

	$log->info("modifyObject success: DSID = ".$res->result);
}

=item cut

purgeObject, first approach to clean delete 

element name="pid" type="xsd:string"/>
<element name="logMessage" type="xsd:string"/>
<element name="force" type="xsd:boolean"/>

 my opinion, force should never be used Hugh B!


This is currently duplicated in Fedora.pm but probably
should be here...


sub purgeObject
{
	my ($self, $pid, $message, $force) = @_;

	my $log = get_logger();

    # make sure things aren't force purged because of rubbish in the field
	$force = 0 if (! length($force) || $force != 1 ) ;
	$log->info("purging object: ". $pid . ':' . $message); # this is somewhat redundant goes in the Fedora log too..
	
	my $res = $self->getSoap("apim")->purgeObject($pid, SOAP::Data->type(string => "$message"), $force) ;	
	if($res->fault)
	{
		$log->logdie("purgeObject failed: ".$res->faultcode.": ".$res->faultstring);
	}
	$log->info("purgeObject success: DSID = ".$res->result);

	return ;
}

=cut

1;

