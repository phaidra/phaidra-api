package PhaidraAPI::Model::Object;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use Mojo::Util qw/xml_escape/;
use lib "lib/phaidra_binding";
use Phaidra::API;
use PhaidraAPI::Model::Rights;
use Switch;
use IO::Scalar;
use File::MimeInfo;
use File::Temp 'tempfile';
my $home = Mojo::Home->new;
$home->detect('PhaidraAPI');
use PhaidraAPI::Model::Uwmetadata;

my %datastream_versionable = (
	'COLLECTIONORDER' => 0	
);

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
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };
    
    $c->app->log->debug("Creating empty object");
    # create empty object
    my $r = $self->create_empty($c, $username, $password);
    push @{$res->{alerts}}, $r->{alerts} if scalar $r->{alerts} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }	
        
  	my $pid = $r->{pid};  	
  	$c->app->log->debug("Created object: $pid");
  	$res->{pid} = $pid;
  	    	  	    
  	my $oaiid = "oai:".$c->app->config->{phaidra}->{baseurl}.":".$pid;
  	my @relationships;
	push @relationships, { predicate => "info:fedora/fedora-system:def/model#hasModel", object => "info:fedora/".$contentmodel };
	push @relationships, { predicate => "http://www.openarchives.org/OAI/2.0/itemID", object => $oaiid };  	
  	    	  	
    # set cmodel and oai itemid
    $c->app->log->debug("Set cmodel ($contentmodel) and oaiitemid ($oaiid)");
	$r = $self->add_relationships($c, $pid, \@relationships, $username, $password);
  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }
  		  	
  	# add thumbnail  	
  	my $thumburl = "http://".$c->app->config->{phaidra}->{baseurl}."/preview/$pid";
  	$c->app->log->debug("Adding thumbnail ($thumburl)");
	$r = $self->add_datastream($c, $pid, "THUMBNAIL", "image/png", $thumburl, undef, undef, "E", $username, $password);
  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }
    
  	# add stylesheet
  	$r = $self->add_datastream($c, $pid, "STYLESHEET", "text/xml", $c->app->config->{phaidra}->{fedorastylesheeturl}, undef, undef, "E", $username, $password);
  	push @{$res->{alerts}}, $r->{alerts} if scalar @{$r->{alerts}} > 0;
    $res->{status} = $r->{status};
    if($r->{status} ne 200){
    	return $res;
    }
    
  	return $res;
}

sub get_mimetype(){
	my ($self, $c, $asset) = @_;
	my $mimetype = undef;
	
	if($asset->is_file){
		# todo: maybe it won't be bad to look into the request headers as well
		
		$mimetype = File::MimeInfo::Magic::magic($asset->path);
		unless(defined($mimetype)){			
			$mimetype = File::MimeInfo::Magic::globs($asset->path);
			unless(defined($mimetype)){
			    $mimetype = mimetype($asset->path);
			} 
		}
	}else{
		$mimetype = File::MimeInfo::Magic::magic(new IO::Scalar($asset->slurp));
	}

	return $mimetype;
}

sub create_simple {	
	
	my $self = shift;
    my $c = shift;
    my $cmodel = shift;    
	my $metadata = shift;
	my $mimetype = shift;	
	my $upload = shift;
    my $username = shift;
    my $password = shift;
   	
	my $res = { alerts => [], status => 200 };

  	my $size = $upload->size;
  	my $name = $upload->filename;
  	
	unless(defined($metadata)){	
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'No metadata provided'};
		$res->{status} = 400;
		return $res;				
	}	
		
	# create object		
    my $r = $self->create($c, $cmodel, $username, $password);
   	if($r->{status} ne 200){
   		$res->{status} = 500;
		unshift @{$res->{alerts}}, @{$r->{alerts}};
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error creating object'};
   		return $res;
   	}
	
	my $pid = $r->{pid};
	$res->{pid} = $pid;
	
   	# save data first, because these may be needed (dsinfo..) when saving metadata
   	$c->app->log->debug("Saving octets: $name [$size B]");  	
   	my %params;
    $params{controlGroup} = 'M';
    $params{dsLabel} = $name;           
    unless(defined($mimetype)){	
    	$mimetype = $self->get_mimetype($c, $upload->asset);
		unshift @{$res->{alerts}}, { type => 'info', msg => "Undefined mimetype, using magic: $mimetype" };
	}
	$params{mimeType} = $mimetype;
    
    my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid/datastreams/OCTETS");
	$url->query(\%params);
	
	my $ua = Mojo::UserAgent->new;

	my $post = $ua->post($url => { 'Content-Type' => $mimetype } => form => { file => { file => $upload->asset }} );			
		
  	unless($r = $post->success) {    	
	  my ($err, $code) = $post->error;
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	  $res->{status} =  $code ? $code : 500;
	  return $res;
	}

    # save metadata
    $r = $self->save_metadata($c, $pid, $metadata->{metadata}, $username, $password);
    if($r->{status} ne 200){
        $res->{status} = 500;
        unshift @{$res->{alerts}}, @{$r->{alerts}};
        unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving metadata'};
        return $res;
    }

	# activate
    $r = $self->modify($c, $pid, 'A', undef, undef, undef, undef, $username, $password);
    if($r->{status} ne 200){
   		$res->{status} = 500;
		unshift @{$res->{alerts}}, @{$r->{alerts}};
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error activating object'};   		
   		return $res;	
   	}
   	
   	return $res;
}

sub save_metadata {
	
	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $metadata = shift; 
	my $username = shift;
	my $password = shift;	
	
	my $res = { alerts => [], status => 200 };
	
	my $found = 0;
	my $found_bib = 0;
	foreach my $f (keys %{$metadata}){
		
		switch ($f) {
			
			case "uwmetadata" { 
				my $uwmetadata = $metadata->{uwmetadata};
				my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;	
				my $r = $metadata_model->save_to_object($c, $pid, $uwmetadata, $username, $password);
				if($r->{status} ne 200){
			   		$res->{status} = 500;				
					unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving uwmetadata'};	
			   	}	
			   	$found = 1;		 
			   	$found_bib = 1;
			}
		
			case "rights" { 
				my $rights = $metadata->{rights};
				my $rights_model = PhaidraAPI::Model::Rights->new;						
				my $xml = $rights_model->json_2_xml($c, $rights);		
				$c->app->log->debug("Saving RIGHTS for $pid");		
				my $r = $self->add_datastream($c, $pid, "RIGHTS", "text/xml", undef, "Phaidra Permissions", $xml, "X", $username, $password);
			  	if($r->{status} ne 200){
			   		$res->{status} = 500;				
					unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving rights'};	
			   	}
				$found = 1;
			}
			
			else { 
				$found = 1;
				unshift @{$res->{alerts}}, { type => 'danger', msg => 'Unknown or unsupported metadata format: $f' };	
			}
		}
	}

	unless($found){		
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'No metadata provided' };
		$res->{status} = 400;	
	}
	
	unless($found_bib){		
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'No bibliographical metadata provided' };
		$res->{status} = 400;	
	}

	return $res;		
}

sub get_datastream {
	
	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $dsid = shift; 
	my $username = shift;
	my $password = shift;
	
	my $res = { alerts => [], status => 200 };
	
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid/datastreams/$dsid/content");	
	
  	my $get = Mojo::UserAgent->new->get($url);  	
  	
  	if (my $r = $get->success) {
  		$res->{status} = 200;  
  		$res->{$dsid} = $r->body;
  	}
	else 
	{
	  my ($err, $code) = $get->error;
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	  $res->{status} =  $code ? $code : 500;
	}
	
	return $res;		
}

sub add_datastream {
	
	my $self = shift;
	my $c = shift;
	my $pid = shift;	
	my $dsid = shift;
	my $mimetype = shift;
	my $location = shift;
	my $label = shift;
	my $dscontent = shift;
	my $controlgroup = shift;
	my $username = shift;
	my $password = shift;
	
	my %params;
	unless(defined($label)){	
		# the label is mandatory when adding datastream
		$label = $c->app->config->{phaidra}->{defaultlabel};
	}
    $params{controlGroup} = $controlgroup if $controlgroup;
    $params{dsLocation} = $location if $location;
    #$params{altIDs}
    $params{dsLabel} = $label;    
    if(defined($datastream_versionable{$dsid})){
    	$params{versionable} = $datastream_versionable{$dsid};
    }    
    $params{dsState} = 'A';
    #$params{formatURI}
    $params{checksumType} = 'DISABLED';
    #$params{checksum}
    $params{mimeType} = $mimetype if $mimetype;
    $params{logMessage} = 'PhaidraAPI object/add_datastream';  
    
    my $res = { alerts => [], status => 200 };
	
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid/datastreams/$dsid");
	$url->query(\%params);
	
	my $ua = Mojo::UserAgent->new;
	my $post;
	if($dscontent){
  		$post = $ua->post($url => $dscontent);
	}else{
		$post = $ua->post($url);
	}  	
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

sub modify_datastream {
	
	my $self = shift;
	my $c = shift;
	my $pid = shift;	
	my $dsid = shift;
	my $mimetype = shift;
	my $location = shift;
	my $label = shift;
	my $dscontent = shift;
	my $username = shift;
	my $password = shift;
	
	my %params;	
    $params{dsLocation} = $location if $location;
    #$params{altIDs}
    $params{dsLabel} = $label if $label;
    if($dsid eq 'COLLECTIONORDER'){
    	$params{versionable} = 0;
    }
    #$params{versionable} = 1;
    $params{dsState} = 'A';
    #$params{formatURI}
    $params{checksumType} = 'DISABLED';
    #$params{checksum}
    $params{mimeType} = $mimetype if $mimetype;
    $params{logMessage} = 'PhaidraAPI object/modify_datastream';
    $params{force} = 0;
    #$params{ignoreContent}   
    
    my $res = { alerts => [], status => 200 };

	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->userinfo("$username:$password");
	$url->host($c->app->config->{phaidra}->{fedorabaseurl});
	$url->path("/fedora/objects/$pid/datastreams/$dsid");
	$url->query(\%params);
	
	my $ua = Mojo::UserAgent->new;
	my $put;
	if($dscontent){
  		$put = $ua->put($url => $dscontent);
	}else{
		$put = $ua->put($url);
	}  	
  	if (my $r = $put->success) {  
  		#unshift @{$res->{alerts}}, { type => 'success', msg => $r->body };
  	}
	else {
	  my ($err, $code) = $put->error;
	  unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	  $res->{status} =  $code ? $code : 500;
	}
  	
  	return $res;	
}

sub create_empty {
	
	my $self = shift;
    my $c = shift; 
    my $username = shift;
    my $password = shift;

    my $res = { alerts => [], status => 200 };
        
    $username = xml_escape $username;
    
    my %params;
    my $label = $c->app->config->{phaidra}->{defaultlabel};
    $params{label} = $label;	
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
	  $c->app->log->error("Cannot create fedora object: $code:".$err);
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

sub add_relationship {
	
	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $predicate = shift;
    my $object = shift;    
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
	my $soapres = $soap->addRelationship($pid, SOAP::Data->type(string => $predicate), SOAP::Data->type(string => $object), SOAP::Data->type(boolean => 0), undef);
	
	if($soapres->fault)
	{
		$c->app->log->error("Adding relationships for $pid failed: ".$soapres->faultcode.": ".$soapres->faultstring);		
		$res->{status} = 500;	
		unshift @{$res->{alerts}}, { type => 'danger', msg => "Adding relationships for $pid failed: ".$soapres->faultcode.": ".$soapres->faultstring};
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
				SOAP::Data->name("object")->value($r->{object})->type("string"),
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

# not REST for purgeRelationship in Fedora Commons 3.3
sub purge_relationship {
	
	my $self = shift;
    my $c = shift;
    my $pid = shift;
    my $predicate = shift;
    my $object = shift;    
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
	my $soapres = $soap->purgeRelationship($pid, SOAP::Data->type(string => $predicate), SOAP::Data->type(string => $object), SOAP::Data->type(boolean => 0), undef);
	
	if($soapres->fault)
	{
		$c->app->log->error("Removing relationships for $pid failed:".$soapres->faultcode.": ".$soapres->faultstring);		
		$res->{status} = 500;	
		unshift @{$res->{alerts}}, { type => 'danger', msg => "Removing relationship for $pid failed:".$soapres->faultcode.": ".$soapres->faultstring};
		return $res;
	}
  	
  	return $res;
}


# this method is our hack in 3.3
sub purge_relationships {
	
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
				SOAP::Data->name("object")->value($r->{object})->type("string"),
				SOAP::Data->name("isLiteral")->value(0)->type("boolean"),
				SOAP::Data->name("datatype")->value(undef)
			)
		);
	}

	my $soapres = $soap->purgeRelationships(\@rels);
	
	if($soapres->fault)
	{
		$c->app->log->error("Removing relationships for $pid failed:".$soapres->faultcode.": ".$soapres->faultstring);		
		$res->{status} = 500;	
		unshift @{$res->{alerts}}, { type => 'danger', msg => "Removing relationships for $pid failed: ".$soapres->faultcode.": ".$soapres->faultstring};
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
