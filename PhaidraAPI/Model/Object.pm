package PhaidraAPI::Model::Object;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use Mojo::Util qw/xml_escape/;
use lib "lib/phaidra_binding";
use Phaidra::API;
my $home = Mojo::Home->new;
$home->detect('PhaidraAPI');

sub delete {
	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };
	
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
    
    my %params;
    $params{state} = $state if $state;
    $params{label} = $label if $label;
    $params{ownerId} = $ownerid if $ownerid;
    $params{logMessage} = $logmessage if $logmessage;
    $params{lastModifiedDate} = $lastmodifieddate if $lastmodifieddate;  
    
    my $res = { alerts => [], status => 200 };
	
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid");
	$url->query(\%params);
	
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

sub create {
	my $self = shift;
    my $c = shift;
    my $contentmodel = shift;   
    my $label = shift; 
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };
        
    my $pid;
    
    # create empty object
    my $r = $self->create_empty($c, $contentmodel, $label, $username, $password);
    push @{$res->{alerts}}, $r->{alerts} if scalar $r->{alerts} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }	
  	$pid = $r->{pid};
  	$res->{pid} = $pid;
  	    	  	    	
  	my $oaiid = "oai:".$c->app->config->{phaidra}->{baseurl}.":".$pid;
  	my @relationships;
	push @relationships, { predicate => "info:fedora/fedora-system:def/model#hasModel", object => $contentmodel };
	push @relationships, { predicate => "http://www.openarchives.org/OAI/2.0/itemID", object => $oaiid };  	
  	    	
    # set cmodel and oai itemid
	$r = $self->add_relationships($c, $pid, \@relationships, $username, $password);
  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }
  		
  	# add thumbnail  	
	$r = $self->add_datastream_location($c, $pid, "THUMBNAIL", "image/png", "http://".$c->app->config->{phaidra}->{staticbaseurl}."/thumbs/collection.png", "THUMBNAIL label", "E", $username, $password);
  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }
    
  	# add stylesheet
  	$r = $self->add_datastream_location($c, $pid, "STYLESHEET", "text/xml", $c->app->config->{phaidra}->{fedorastylesheeturl}, "STYLESHEET label", "E", $username, $password);
  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }
    
  	return $res;
}

sub add_datastream_location {
	
	my $self = shift;
	my $c = shift;
	my $pid = shift;	
	my $dsid = shift;
	my $mimetype = shift;
	my $location = shift;
	my $label = shift;
	my $controlgroup = shift;
	my $username = shift;
	my $password = shift;
	
	my %params;	
    $params{controlGroup} = $controlgroup if $controlgroup;
    $params{dsLocation} = $location if $location;
    #$params{altIDs}
    $params{dsLabel} = $label if $label;
    $params{versionable} = 1;
    $params{dsState} = 'A';
    #$params{formatURI}
    $params{checksumType} = 'DISABLED';
    #$params{checksum}
    $params{mimeType} = $mimetype if $mimetype;
    $params{logMessage} = 'PhaidraAPI object/addDatastreamLocation';  
    
    my $res = { alerts => [], status => 200 };
	
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid/datastreams/$dsid");
	$url->query(\%params);
	
	my $ua = Mojo::UserAgent->new;
	
  	my $post = $ua->post($url);  	
  	if (my $r = $post->success) {  
  		#unshift @{$res->{alerts}}, { type => 'success', msg => $r->body };
  	}
	else {
	  my ($err, $code) = $post->error;
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	  $res->{status} =  $code ? $code : 500;
	}
  	
  	return $res;	
}

sub create_empty {
	
	my $self = shift;
    my $c = shift;
    my $contentmodel = shift;   
    my $label = shift; 
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };
        
    $label = xml_escape $label if defined($label);
    $username = xml_escape $username;
    
    my %params;
    $params{label} = $label if $label;
    $params{format} = 'info:fedora/fedora-system:FOXML-1.1';
    $params{ownerId} = $username;
    $params{logMessage} = 'PhaidraAPI object/create_empty';

	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/new");
	$url->query(\%params);
	
	# have to sent xml, because without the foxml fedora creates a default empty object
	# but this is then automatically 'Active'!
	# http://www.fedora-commons.org/documentation/3.0/userdocs/server/webservices/apim/#methods.ingest
	my $foxml = qq|<?xml version="1.0" encoding="UTF-8"?>
<foxml:digitalObject VERSION="1.1" xmlns:foxml="info:fedora/fedora-system:def/foxml#" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="info:fedora/fedora-system:def/foxml# http://www.fedora.info/definitions/1/0/foxml1-1.xsd">
        <foxml:objectProperties>
                <foxml:property NAME="info:fedora/fedora-system:def/model#state" VALUE="Inactive"/>
                <foxml:property NAME="info:fedora/fedora-system:def/model#label" VALUE="$label"/>
                <foxml:property NAME="info:fedora/fedora-system:def/model#ownerId" VALUE="$username"/>
        </foxml:objectProperties>
</foxml:digitalObject>
|;
	
	my $pid;
	my $ua = Mojo::UserAgent->new;	
  	my $put = $ua->post($url => {'Content-Type' => 'text/xml'} => $foxml);  	
  	if (my $r = $put->success) {  
  		$res->{pid} = $r->body;
  	}else {
	  my ($err, $code) = $put->error;
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	  $res->{status} =  $code ? $code : 500;
	  return $res;
	}  
	return $res;
}

=cut

not REST for addRelationship in Fedora Commons 3.3

sub add_relationship {
	
	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $predicate = shift;
    my $object = shift;
    my $isliteral = shift;
    my $datatype = shift;
    my $username = shift;
    my $password = shift;
    
    my $res = { alerts => [], status => 200 };
    
    my %params;
    $params{subject} = 'info:fedora/'.$pid;
    $params{predicate} = $predicate;
    $params{object} = $object;
    $params{isLiteral} = $isliteral if $isliteral;
    $params{datatype} = $datatype if $datatype;

	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid/relationships/new");
	$url->query(\%params);
    
    my $ua = Mojo::UserAgent->new;	
  	my $post = $ua->post($url);  	
  	if (my $r = $post->success) {  
  		unshift @{$res->{alerts}}, { type => 'success', msg => $r->body };
  	}else {
	  my ($err, $code) = $post->error;
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	  $res->{status} =  $code ? $code : 500;
	}
  	
  	return $res;
}
=cut


=cut

    $r = $self->add_relationship($c, $pid, "info:fedora/fedora-system:def/model#hasModel", $contentmodel, undef, undef, $username, $password);
	push @{$res->{alerts}}, $r->{alerts} if scalar $r->{alerts} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }
    
=cut
sub add_relationship {
	
	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $predicate = shift;
    my $object = shift;
    my $isliteral = shift;
    my $datatype = shift;
    my $username = shift;
    my $password = shift;
    
    my $res = { alerts => [], status => 200 };
    
    $c->app->log->debug("Connecting to ".$c->app->config->{phaidra}->{fedorabaseurl}."...");
	my $phaidra = Phaidra::API->new(
		$c->app->config->{phaidra}->{fedorabaseurl}, 
		$c->app->config->{phaidra}->{staticbaseurl}, 
		$c->app->config->{phaidra}->{fedorastylesheeturl}, 
		$c->app->config->{phaidra}->{proaiRepositoryIdentifier}, 
		$username, 
		$password
	);
		
	my $soap = $phaidra->getSoap("apim");
	unless(defined($soap)){
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Cannot create SOAP connection to '.$c->app->config->{phaidra}->{fedorabaseurl}};
		$res->{status} = 500;	
		return $res;
	}
	$c->app->log->debug("Connected");	
	my $soapres = $soap->addRelationship($pid, SOAP::Data->type(string => $predicate), SOAP::Data->type(string => "info:fedora/$object"), SOAP::Data->type(boolean => 0), undef);
	
	if($soapres->fault)
	{
		$c->app->log->error("Saving UWMETADATA for $pid failed.");		
		$res->{status} = 500;	
		unshift @{$res->{alerts}}, { type => 'danger', msg => "Saving UWMETADATA failed: ".$soapres->faultcode.": ".$soapres->faultstring};
		return $res;
	}
  	
  	return $res;
}

# this method is our hack in 3.3
sub add_relationships {
	
	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $relationships = shift;
    my $username = shift;
    my $password = shift;
    
    my $res = { alerts => [], status => 200 };
    
    $c->app->log->debug("Connecting to ".$c->app->config->{phaidra}->{fedorabaseurl}."...");
	my $phaidra = Phaidra::API->new(
		$c->app->config->{phaidra}->{fedorabaseurl}, 
		$c->app->config->{phaidra}->{staticbaseurl}, 
		$c->app->config->{phaidra}->{fedorastylesheeturl}, 
		$c->app->config->{phaidra}->{proaiRepositoryIdentifier}, 
		$username, 
		$password
	);
		
    # on a rope
	my $soap = $phaidra->getSoap("apim");
	unless(defined($soap)){
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Cannot create SOAP connection to '.$c->app->config->{phaidra}->{fedorabaseurl}};
		$res->{status} = 500;	
		return $res;
	}
	$c->app->log->debug("Connected");	
	
	my @rels = ();
	foreach my $r (@$relationships)
	{
        	push @rels, SOAP::Data->type("RelationshipTuple")->name("relationships" =>
			\SOAP::Data->value(
				SOAP::Data->name("subject")->value($pid),
				SOAP::Data->name("predicate")->value($r->{predicate})->type("string"),
				SOAP::Data->name("object")->value("info:fedora/".$r->{object})->type("string"),
				SOAP::Data->name("isLiteral")->value(0)->type("boolean"),
				SOAP::Data->name("datatype")->value(undef)
			)
		);
	}

	#$c->app->log->debug($c->app->dumper(\@rels));
	my $soapres = $soap->addRelationships(\@rels);
	
	if($soapres->fault)
	{
		$c->app->log->error("Adding relationships for $pid failed:".$soapres->faultcode.": ".$soapres->faultstring);		
		$res->{status} = 500;	
		unshift @{$res->{alerts}}, { type => 'danger', msg => "Adding relationships for $pid failed: ".$soapres->faultcode.": ".$soapres->faultstring};
		return $res;
	}
  	
  	return $res;
}

sub set_rights {
	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $rights = shift;
    my $username = shift;
    my $password = shift;
    
       
    my $res = { alerts => [], status => 200 };
	
  	
  	return $res;	
}


1;
__END__
