#!/usr/bin/perl -w
#
# Phaidra API Object class.
#
# $Id: Objekt.pm 1887 2010-05-18 14:46:34Z swdevel $

use strict;
use warnings;

package Phaidra::API::Objekt;

use URI::Escape;
use Data::Dumper;
use LWP::UserAgent::Determined;
use MIME::Base64;
use HTTP::Request::Common 'POST';
use File::Temp qw/tempfile/;
use Encode;
use Log::Log4perl qw(get_logger);
use base 'Phaidra::API';

# Constructor
#
sub new {
  my ($class, $phaidra) = @_;
  my $self = {};
  $self->{PID}            = undef;
  $self->{phaidra}        = $phaidra;
  $self->{existing}       = 0;          # Does the object exist in Fedora?
  $self->{changed_rights} = 0;
  bless($self, $class);
  return $self;
}

=head2 ingest

Ingest object


      <typ:ingest>
         <objectXML>cid:1290637633050</objectXML>
         <format>?</format>
         <logMessage>?</logMessage>
      </typ:ingest>

=cut

sub ingest {
  my ($self, $label, $contentmodel) = @_;

  my $log = get_logger();

  $label = xmlescape($label);
  my $owner = xmlescape($self->{phaidra}->{username});

  my $soap  = $self->{phaidra}->getSoap("apim");
  my $foxml = qq|<?xml version="1.0" encoding="UTF-8"?>
<foxml:digitalObject VERSION="1.1" xmlns:foxml="info:fedora/fedora-system:def/foxml#" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="info:fedora/fedora-system:def/foxml# http://www.fedora.info/definitions/1/0/foxml1-1.xsd">
        <foxml:objectProperties>
                <foxml:property NAME="info:fedora/fedora-system:def/model#state" VALUE="Inactive"/>
                <foxml:property NAME="info:fedora/fedora-system:def/model#label" VALUE="$label"/>
                <foxml:property NAME="info:fedora/fedora-system:def/model#ownerId" VALUE="$owner"/>
        </foxml:objectProperties>
</foxml:digitalObject>
|;

  my @args;
  push @args,
    SOAP::Data->new(
    name  => 'objectXML',
    value => SOAP::Data->type(base64 => encode("utf-8", $foxml))
    );
  push @args,
    SOAP::Data->new(
    name  => 'format',
    value => 'info:fedora/fedora-system:FOXML-1.1'
    );
  push @args,
    SOAP::Data->new(
    name  => 'logMessage',
    value => 'Ingested by Phaidra API'
    );
  my $res = $soap->ingest(@args);

  #	my $res = $soap->ingest(SOAP::Data->type(base64 => encode("utf-8", $foxml)), 'info:fedora/fedora-system:FOXML-1.1', 'Ingested by Phaidra API');

  if ($res->fault) {
    $log->logdie("Ingest failed: " . $res->faultcode . ": " . $res->faultstring);
  }

  $self->{PID} = $res->result;

  # set Content-Model
  $self->addRelationship("info:fedora/fedora-system:def/model#hasModel", $contentmodel);

  # set OAI link
  $self->addRelationship("http://www.openarchives.org/OAI/2.0/itemID", "oai:" . $self->{phaidra}->{config}->{proaiRepositoryIdentifier} . ":" . $self->{PID});
  $self->{existing}       = 0;
  $self->{changed_rights} = 0;

  $log->info("ingest success: PID = " . $self->{PID});
}

=head2 load

# Load existing object = lookup and check if the cmodel is correct
# If no cmodel submitted - lookup which cmodel it should be and set it

Uses getObjectProfile, see below

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:getObjectProfile>
         <pid>?</pid>
         <asOfDateTime>?</asOfDateTime>
      </typ:getObjectProfile>
   </soapenv:Body>
</soapenv:Envelope>


=cut

sub load {
  my ($self, $pid, $contentmodel) = @_;

  my $log = get_logger();

  # call GetObjectProfile
  my $soap = $self->{phaidra}->getSoap("apia");
  my @args;
  push @args, SOAP::Data->new(name => 'pid', value => $pid);
  my $res = $soap->getObjectProfile(@args);

=getObjectProfile output:

 $VAR1 = {
           'objLastModDate' => '2008-11-13T14:45:22.954Z',
           'objModels' => {
                          'model' => [
                                     'info:fedora/cmodel:PDFDocument',
                                     'info:fedora/fedora-system:FedoraObject-3.0'
                                   ]
                        },
           'pid' => 'o:1113',
           'objItemIndexViewURL' => 'https://fedora.phaidra30.univie.ac.at:443/fedora/get/o:1113/fedora-system:3/viewItemIndex',
           'objCreateDate' => '2008-10-11T15:42:08.920Z',
           'objLabel' => 'budronp5',
           'objDissIndexViewURL' => 'https://fedora.phaidra30.univie.ac.at:443/fedora/get/o:1113/fedora-system:3/viewMethodIndex'
         };

=cut

  if ($res->fault) {
    $log->logdie("load failed: " . $res->faultcode . ": " . $res->faultstring);
  }
  my $objectProfile = $res->result;
  if (defined($contentmodel)) {
    my $valid = 0;
    foreach my $model (@{$objectProfile->{'objModels'}->{'model'}}) {
      if ( $model =~ m/^info:fedora\/(cmodel:.*)$/i
        && $contentmodel eq $1)
      {
        $valid = 1;
        last;
      }
    }
    unless ($valid) {
      $log->logdie("Object is no $contentmodel object, can't load: " . Dumper($objectProfile->{'objModels'}->{'model'}));
    }
  }
  else {
    # auch ok
  }

  # Everything ok...
  $self->{PID}            = $pid;
  $self->{existing}       = 1;
  $self->{changed_rights} = 0;

  # All objects can have a RIGHTS-DS. Load it and put it into internal structure
  my $rightsxml = undef;
  eval {
    my $mimetype;
    ($mimetype, $rightsxml) = $self->getDissemination("bdef:Asset", "getRights");
  };
  if ($@) {

    # Does not matter if no RIGHTS-DS exist => object is not locked
    $log->debug("Object has no RIGHTS-DS - that is OK!");
  }

  $self->{rights}->{usernames}   = {};
  $self->{rights}->{departments} = {};
  $self->{rights}->{faculties}   = {};
  $self->{rights}->{groups}      = {};
  $self->{rights}->{spl}         = {};
  $self->{rights}->{kennzahl}    = {};
  $self->{rights}->{perfunk}     = {};
  if (defined($rightsxml)) {

    # Object has a RIGHTS-DS -> parse it
    my $xp = XML::XPath->new(xml => $rightsxml);
    $xp->set_namespace('uwr', 'http://phaidra.univie.ac.at/XML/V1.0/rights');
    my $nodeset = $xp->findnodes('/uwr:rights/uwr:allow/uwr:username');
    foreach my $node ($nodeset->get_nodelist) {
      $self->{rights}->{usernames}->{$node->string_value()} = {
        who     => $node->string_value(),
        expires => $node->getAttribute("expires")
      };
    }

    $nodeset = $xp->findnodes('/uwr:rights/uwr:allow/uwr:department');
    foreach my $node ($nodeset->get_nodelist) {
      $self->{rights}->{departments}->{$node->string_value()} = {
        who     => $node->string_value(),
        expires => $node->getAttribute("expires")
      };
    }

    $nodeset = $xp->findnodes('/uwr:rights/uwr:allow/uwr:faculty');
    foreach my $node ($nodeset->get_nodelist) {
      $self->{rights}->{faculties}->{$node->string_value()} = {
        who     => $node->string_value(),
        expires => $node->getAttribute("expires")
      };
    }

    $nodeset = $xp->findnodes('/uwr:rights/uwr:allow/uwr:gruppe');
    foreach my $node ($nodeset->get_nodelist) {
      $self->{rights}->{groups}->{$node->string_value()} = {
        who     => $node->string_value(),
        expires => $node->getAttribute("expires")
      };
    }

    $nodeset = $xp->findnodes('/uwr:rights/uwr:allow/uwr:spl');
    foreach my $node ($nodeset->get_nodelist) {
      $self->{rights}->{spl}->{$node->string_value()} = {
        who     => $node->string_value(),
        expires => $node->getAttribute("expires")
      };
    }

    $nodeset = $xp->findnodes('/uwr:rights/uwr:allow/uwr:kennzahl');
    foreach my $node ($nodeset->get_nodelist) {
      $self->{rights}->{kennzahl}->{$node->string_value()} = {
        who     => $node->string_value(),
        expires => $node->getAttribute("expires")
      };
    }

    $nodeset = $xp->findnodes('/uwr:rights/uwr:allow/uwr:perfunk');
    foreach my $node ($nodeset->get_nodelist) {
      $self->{rights}->{perfunk}->{$node->string_value()} = {
        who     => $node->string_value(),
        expires => $node->getAttribute("expires")
      };
    }

    $log->debug("object has RIGHTS: " . Dumper($self->{rights}));
  }

  $log->info("load success: PID = " . $self->{PID});
}

=head2 addMetadata

Specialized addDatastream

=cut

sub addMetadata {
  my ($self, $metadata) = @_;

  $self->addDatastreamContent("UWMETADATA", "text/xml", $metadata, $self->{phaidra}->{config}->{uwmetadatalabel}, "X");
}

=head2 modifyMetadata

Specialized modifyDatastreamByValue

=cut

sub modifyMetadata {
  my ($self, $metadata) = @_;

  $self->modifyDatastreamByValue("UWMETADATA", "text/xml", $metadata, $self->{phaidra}->{config}->{uwmetadatalabel}, "X");
}

=head2 addDatastreamContent

Same as addDatastream but the content parameter is submitted as String
Creates a temp file and calls addDatastream

=cut

sub addDatastreamContent {
  my ($self, $dsid, $mimetype, $content, $label, $controlGroup) = @_;

  my ($fh, $filename) = tempfile(UNLINK => 0);
  print $fh $content;
  close $fh;

  $self->addDatastream($dsid, $mimetype, $filename, $label, $controlGroup);

  unlink $filename;
}

=head2 addDatastream

FIXME: Actually this isn't really addDatastream
It's upload and then a call to add the datastream at
the end of the function

Also all the LWP mechanics are in the function rather than
being in the 'official' upload function


=cut

sub addDatastream {
  my ($self, $dsid, $mimetype, $filename, $label, $controlGroup) = @_;

  $mimetype = 'application/octet-stream' if (!defined($mimetype));
  $mimetype = 'application/octet-stream' if ($mimetype eq '');

  my $log = get_logger();

  $log->logdie("No PID; call 'ingest' or 'load' first")
    unless (defined($self->{PID}));

  # TODO: GG 2011-12-05: ask Markus or Thomas: please explain that silly bug
  # Workaround because of a silly bug
  utf8::downgrade($filename);

  # Upload file to Fedora
  $log->debug("beginning upload of $dsid...");
  my $ua   = LWP::UserAgent::Determined->new;
  my $cred = encode_base64($self->{phaidra}->{username} . ':' . $self->{phaidra}->{password});
  $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
  my $req = POST $self->{phaidra}->{uploadurl},
    Authorization => "Basic: $cred",
    Content_Type  => 'form-data',
    Content       => [file => [$filename]];
  my $resFedora = $ua->request($req);
  unless ($resFedora->is_success && $resFedora->code() == 201) {
    $log->logdie("upload failed: " . $resFedora->status_line);
  }
  my $location = $resFedora->content;
  $location =~ s/\r|\n$//g;
  $log->debug("upload success: location = $location");

  $self->addDatastreamLocation($dsid, $mimetype, $location, $label, $controlGroup);
}

=head2 addDatastream Location

Call addDatastream with a location
FIXME: This is pretty much the 'official' addDatastream

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:addDatastream>
         <pid>?</pid>
         <dsID>?</dsID>
         <altIDs>
            <!--Zero or more repetitions:-->
            <item>?</item>
         </altIDs>
         <dsLabel>?</dsLabel>
         <versionable>?</versionable>
         <MIMEType>?</MIMEType>
         <formatURI>?</formatURI>
         <dsLocation>?</dsLocation>
         <controlGroup>?</controlGroup>
         <dsState>?</dsState>
         <checksumType>?</checksumType>
         <checksum>?</checksum>
         <logMessage>?</logMessage>
      </typ:addDatastream>
   </soapenv:Body>
</soapenv:Envelope>

=cut

sub addDatastreamLocation {
  my ($self, $dsid, $mimetype, $location, $label, $controlGroup) = @_;

  my $log = get_logger();

  # call addDatastream
  my $soap = $self->{phaidra}->getSoap("apim");
  $log->info("Hugh dumping SOAP in  addDatastreamLocation" . Dumper $soap);

  # TODO: although this works, it's pretty ugly
  my @args;
  push @args, SOAP::Data->new(name => 'pid',          value => $self->{PID});
  push @args, SOAP::Data->new(name => 'dsID',         value => $dsid);
  push @args, SOAP::Data->new(name => 'dsLabel',      value => $label);
  push @args, SOAP::Data->new(name => 'versionable',  value => 'true');
  push @args, SOAP::Data->new(name => 'MIMEType',     value => $mimetype);
  push @args, SOAP::Data->new(name => 'dsLocation',   value => $location);
  push @args, SOAP::Data->new(name => 'controlGroup', value => $controlGroup);
  push @args, SOAP::Data->new(name => 'dsState',      value => 'A');
  push @args, SOAP::Data->new(name => 'checksumType', value => 'DISABLED');
  push @args, SOAP::Data->new(name => 'checksum',     value => 'none');
  push @args,
    SOAP::Data->new(
    name  => 'logMessage',
    value => 'Created by Phaidra API'
    );
  my $res = $soap->addDatastream(@args);

  ###	my $res = $soap->addDatastream($self->{PID}, $dsid, '', SOAP::Data->type(string => $label), SOAP::Data->type(boolean => 1),
  ###		$mimetype, '', SOAP::Data->type(string => $location), $controlGroup, 'A', 'DISABLED', 'none', 'Created by Phaidra API');

  if ($res->fault) {
    $log->logdie("addDatastream failed: " . $res->faultcode . ": " . $res->faultstring);
  }

  $log->info("addDatastream success: DSID = " . $res->result);
}

=head2 purgeRelationship

purgeRelationship

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:purgeRelationship>
         <pid>?</pid>
         <relationship>?</relationship>
         <object>?</object>
         <isLiteral>?</isLiteral>
         <datatype>?</datatype>
      </typ:purgeRelationship>
   </soapenv:Body>
</soapenv:Envelope>


=cut

sub purgeRelationship {
  my ($self, $predicate, $object) = @_;

  my $log = get_logger();

  my $soap = $self->{phaidra}->getSoap("apim");

  my @args;
  push @args, SOAP::Data->new(name => 'pid',          value => $self->{PID});
  push @args, SOAP::Data->new(name => 'relationship', value => $predicate);
  push @args, SOAP::Data->new(name => 'object',       value => "info:fedora/$object");
  push @args,
    SOAP::Data->new(
    name  => 'isLiteral',
    value => SOAP::Data->type(boolean => 0)
    );
  my $res = $soap->purgeRelationship(@args);

=cut
    my $res  = $soap->purgeRelationship(
        $self->{PID},
        SOAP::Data->type( string  => $predicate ),
        SOAP::Data->type( string  => "info:fedora/$object" ),
        SOAP::Data->type( boolean => 0 ),
        undef
    );
=cut

  if ($res->fault) {
    $log->logdie("purgeRelationship failed: " . $res->faultcode . ": " . $res->faultstring);
  }

  $log->info("purgeRelationship success: " . $res->result);
}

=head2 addRelationship

addRelationship

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:addRelationship>
         <pid>?</pid>
         <relationship>?</relationship>
         <object>?</object>
         <isLiteral>?</isLiteral>
         <datatype>?</datatype>
      </typ:addRelationship>
   </soapenv:Body>
</soapenv:Envelope>

=cut

sub addRelationship {
  my ($self, $predicate, $object) = @_;

  my $log = get_logger();

  my $soap = $self->{phaidra}->getSoap("apim");

  # TODO: although this works, it's pretty ugly
  my @args;
  push @args, SOAP::Data->new(name => 'pid',          value => $self->{PID});
  push @args, SOAP::Data->new(name => 'relationship', value => $predicate);
  push @args, SOAP::Data->new(name => 'object',       value => "info:fedora/$object");
  push @args, SOAP::Data->new(name => 'isLiteral',    value => 'false');
  push @args, SOAP::Data->new(name => 'datatype',     value => undef);
  my $res = $soap->addRelationship(@args);

  ###	my $res = $soap->addRelationship($self->{PID}, SOAP::Data->type(string => $predicate),
  ###			SOAP::Data->type(string => "info:fedora/$object"), SOAP::Data->type(boolean => 0), undef);

  if ($res->fault) {
    $log->logdie("addRelationship failed: " . $res->faultcode . ": " . $res->faultstring);
  }

  $log->info("addRelationship success: " . $res->result);
}

=head2 addRelationships

addRelationships

This should still work 'as is' because the data is
formatted in the way suggested. Hugh Barnard March 2015

=cut

sub addRelationships {
  my ($self, $relationships) = @_;

  my $log = get_logger();

  my $soap = $self->{phaidra}->getSoap("apim");
  my @rels = ();
  foreach my $r (@$relationships) {
    push @rels,
      SOAP::Data->type("RelationshipTuple")
      ->name("relationships" =>
        \SOAP::Data->value(SOAP::Data->name("subject")->value($self->{PID}), SOAP::Data->name("predicate")->value($r->{predicate}), SOAP::Data->name("object")->value("info:fedora/" . $r->{object}), SOAP::Data->name("isLiteral")->value(0)->type("boolean"), SOAP::Data->name("datatype")->value(undef))
      );
  }

  my $res = $soap->addRelationships(\@rels);

  if ($res->fault) {
    $log->logdie("addRelationships failed: " . $res->faultcode . ": " . $res->faultstring);
  }

  $log->info("addRelationships success: " . $res->result);
}

=head2 getRelationships

 returns the relationships of an object in following structure:

 $VAR1 = [
           {
             'object' => 'info:fedora/o:367',
             'predicate' => 'info:fedora/fedora-system:def/relations-external#hasCollectionMember',
             'subject' => 'info:fedora/o:4881',
             'isLiteral' => 'false',
             'datatype' => undef
           },
           {
             'object' => 'info:fedora/o:643',
             'predicate' => 'info:fedora/fedora-system:def/relations-external#hasCollectionMember',
             'subject' => 'info:fedora/o:4881',
             'isLiteral' => 'false',
             'datatype' => undef
           },
           ...
         ];

 "Subject" is the object. Predicate is optional and can be undef - if so all relationships
 will be returned, otherwise only the matching ones.

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:getRelationships>
         <pid>?</pid>
         <relationship>?</relationship>
      </typ:getRelationships>
   </soapenv:Body>
</soapenv:Envelope>

=cut

sub getRelationships {
  my ($self, $predicate) = @_;

  my $log = get_logger();

  my $soap = $self->{phaidra}->getSoap("apim");
  my @args;
  push @args, SOAP::Data->new(name => 'pid',          value => $self->{PID});
  push @args, SOAP::Data->new(name => 'relationship', value => $predicate);

  my $res = $soap->getRelationships(@args);

  ###my $res  = $soap->getRelationships(
  ###    SOAP::Data->type( string => $self->{PID} ),
  ###    SOAP::Data->type( string => $predicate )
  ###);

  if ($res->fault) {
    $log->logdie("getRelationships failed: " . $res->faultcode . ": " . $res->faultstring);
  }

  my $rels = undef;
  foreach my $relation ($res->result(), $res->paramsout()) {
    push @$rels, $relation;
  }

  return $rels;
}

=head2 purgeRelationships

purgeRelationships

This should still work 'as is' because the data is
formatted in the way suggested. Hugh Barnard March 2015

=cut

sub purgeRelationships {
  my ($self, $relationships) = @_;

  my $log = get_logger();

  my $soap = $self->{phaidra}->getSoap("apim");
  my @rels = ();
  foreach my $r (@$relationships) {
    push @rels,
      SOAP::Data->type("RelationshipTuple")->name(
      "relationships" => \SOAP::Data->value(
        SOAP::Data->name("subject")->value($self->{PID}),                                     SOAP::Data->name("predicate")->value(SOAP::Data->type(string => $r->{predicate})),
        SOAP::Data->name("object")->value("info:fedora/" . $r->{object})->type("xsd:string"), SOAP::Data->name("isLiteral")->value(0)->type("boolean"),
        SOAP::Data->name("datatype")->value(undef)
      )
      );
  }

  my $res = $soap->purgeRelationships(\@rels);

  if ($res->fault) {
    $log->logdie("purgeRelationships failed: " . $res->faultcode . ": " . $res->faultstring);
  }

  $log->info("purgeRelationships success: " . $res->result);
}

=head2 modifyDatastreamByValue

modify Datastream by Value.

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:modifyDatastreamByValue>
         <pid>?</pid>
         <dsID>?</dsID>
         <altIDs>
            <!--Zero or more repetitions:-->
            <item>?</item>
         </altIDs>
         <dsLabel>?</dsLabel>
         <MIMEType>?</MIMEType>
         <formatURI>?</formatURI>
         <dsContent>cid:920454504651</dsContent>
         <checksumType>?</checksumType>
         <checksum>?</checksum>
         <logMessage>?</logMessage>
         <force>?</force>
      </typ:modifyDatastreamByValue>
   </soapenv:Body>
</soapenv:Envelope>


=cut

sub modifyDatastreamByValue {
  my ($self, $dsid, $mimetype, $content, $label, $controlGroup) = @_;

  my $log = get_logger();

  $log->logdie("No PID; call 'ingest' or 'load' first")
    unless (defined($self->{PID}));

  my $soap = $self->{phaidra}->getSoap("apim");

  # TODO: although this works, it's pretty ugly
  my @args;
  push @args, SOAP::Data->new(name => 'pid',      value => $self->{PID});
  push @args, SOAP::Data->new(name => 'dsID',     value => $dsid);
  push @args, SOAP::Data->new(name => 'dsLabel',  value => $label);
  push @args, SOAP::Data->new(name => 'MIMEType', value => $mimetype);
  push @args,
    SOAP::Data->new(
    name  => 'dsContent',
    value => SOAP::Data->type(base64 => $content)
    );
  push @args, SOAP::Data->new(name => 'checksumType', value => 'DISABLED');
  push @args, SOAP::Data->new(name => 'checksum',     value => 'none');
  push @args,
    SOAP::Data->new(
    name  => 'logMessage',
    value => 'Modified by Phaidra API'
    );
  push @args,
    SOAP::Data->new(
    name  => 'force',
    value => SOAP::Data->type(boolean => 0)
    );
  my $res = $soap->modifyDatastreamByValue(@args);
  ###my $res = $soap->modifyDatastreamByValue($self->{PID}, $dsid, '', $label, $mimetype, '', SOAP::Data->type(base64 => $content), 'DISABLED', 'none', 'Modified by Phaidra API', SOAP::Data->type(boolean => 0));
  if ($res->fault) {
    $log->logdie("modifyDatastreamByValue failed: " . $res->faultcode . ": " . $res->faultstring);
  }

  $log->info("modifyDatastreamByValue success: " . $res->result);
}

=head2 modifyDatastreamByReference

# modify Datastream by Reference.

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:modifyDatastreamByReference>
         <pid>?</pid>
         <dsID>?</dsID>
         <altIDs>
            <!--Zero or more repetitions:-->
            <item>?</item>
         </altIDs>
         <dsLabel>?</dsLabel>
         <MIMEType>?</MIMEType>
         <formatURI>?</formatURI>
         <dsLocation>?</dsLocation>
         <checksumType>?</checksumType>
         <checksum>?</checksum>
         <logMessage>?</logMessage>
         <force>?</force>
      </typ:modifyDatastreamByReference>
   </soapenv:Body>
</soapenv:Envelope>


=cut

sub modifyDatastreamByReference {
  my ($self, $dsid, $mimetype, $location, $label, $controlGroup) = @_;

  my $log = get_logger();

  $log->logdie("No PID; call 'ingest' or 'load' first")
    unless (defined($self->{PID}));

  my $soap = $self->{phaidra}->getSoap("apim");
  my @args;
  push @args, SOAP::Data->new(name => 'pid',      value => $self->{PID});
  push @args, SOAP::Data->new(name => 'dsID',     value => $dsid);
  push @args, SOAP::Data->new(name => 'dsLabel',  value => $label);
  push @args, SOAP::Data->new(name => 'MIMEType', value => $mimetype);
  push @args,
    SOAP::Data->new(
    name  => 'dsLocation',
    value => SOAP::Data->type(string => $location)
    );
  push @args, SOAP::Data->new(name => 'checksumType', value => 'DISABLED');
  push @args, SOAP::Data->new(name => 'checksum',     value => 'none');
  push @args,
    SOAP::Data->new(
    name  => 'logMessage',
    value => 'Modified by Phaidra API'
    );
  push @args,
    SOAP::Data->new(
    name  => 'force',
    value => SOAP::Data->type(boolean => 0)
    );
  my $res = $soap->modifyDatastreamByReference(@args);

  ###$res = $soap->modifyDatastreamByReference($self->{PID}, $dsid, '', $label, $mimetype, '', SOAP::Data->type(string => $location), 'DISABLED', 'none', 'Modified by Phaidra API', SOAP::Data->type(boolean => 0));
  if ($res->fault) {
    $log->logdie("modifyDatastreamByReference failed: " . $res->faultcode . ": " . $res->faultstring);
  }

  $log->info("modifyDatastreamByReference success: " . $res->result);
}

=head2 getDatastream

Get a datastream from an object
Returns an array: MIME-Type as String and
OCTETS as String (base64-Encoded, accordingly
already decoded if MIME-Type 'text/*')

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:getDatastreamDissemination>
         <pid>?</pid>
         <dsID>?</dsID>
         <asOfDateTime>?</asOfDateTime>
      </typ:getDatastreamDissemination>
   </soapenv:Body>
</soapenv:Envelope>


=cut

sub getDatastream {
  my ($self, $ds) = @_;

  my $log = get_logger();

  $log->logdie("No PID; call 'ingest' or 'load' first")
    unless (defined($self->{PID}));

  my $soap = $self->{phaidra}->getSoap("apia");
  my @args;
  push @args, SOAP::Data->new(name => 'pid',  value => $self->{PID});
  push @args, SOAP::Data->new(name => 'dsID', value => $ds);

  my $res = $soap->getDatastreamDissemination(@args);

  ### my $res  = $soap->getDatastreamDissemination(
  ###    SOAP::Data->type( string => $self->{PID} ),
  ###    SOAP::Data->type( string => $ds )
  ### );

  if ($res->fault) {
    $log->logdie("getDatastreamDissemination failed: " . $res->faultcode . ": " . $res->faultstring);
  }
  my $dsi = $res->result;
  my ($mimetype, $octets) = ($dsi->{'MIMEType'}, $dsi->{'stream'});
  if ($mimetype =~ m/^text\// || $ds eq 'RELS-EXT') {
    $octets = decode_base64($octets);
  }
  return ($mimetype, $octets);
}

=head2 getDissemination

Get a dissemination of an object
Returns an array: MIME-Type as String and OCTETS as String
(base64-Encoded, accordingly already decoded if MIME-Type 'text/*')

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:getDissemination>
         <pid>?</pid>
         <serviceDefinitionPid>?</serviceDefinitionPid>
         <methodName>?</methodName>
         <parameters>
            <!--Zero or more repetitions:-->
            <parameter>
               <name>?</name>
               <value>?</value>
            </parameter>
         </parameters>
         <asOfDateTime>?</asOfDateTime>
      </typ:getDissemination>
   </soapenv:Body>
</soapenv:Envelope>

=cut

sub getDissemination {
  my ($self, $sdef, $method) = @_;

  my $log = get_logger();

  $log->logdie("No PID; call 'ingest' or 'load' first")
    unless (defined($self->{PID}));

  my $soap = $self->{phaidra}->getSoap("apia");
  my @args;
  push @args, SOAP::Data->new(name => 'pid',                  value => $self->{PID});
  push @args, SOAP::Data->new(name => 'serviceDefinitionPid', value => $sdef);
  push @args, SOAP::Data->new(name => 'methodName',           value => $method);

  my $res = $soap->getDissemination(@args);

  ### my $res  = $soap->getDissemination(
  ###     SOAP::Data->type( string => $self->{PID} ),
  ###     SOAP::Data->type( string => $sdef ),
  ###     SOAP::Data->type( string => $method ),
  ###     undef, undef
  ### );

  if ($res->fault) {
    $log->logdie("getDissemination failed: " . $res->faultcode . ": " . $res->faultstring);
  }
  my $dsi = $res->result;
  my ($mimetype, $octets) = ($dsi->{'MIMEType'}, $dsi->{'stream'});
  if ($mimetype =~ m/^text\//) {
    $octets = decode_base64($octets);
  }
  return ($mimetype, $octets);
}

=head2 save

save() saves theobject into Fedora and closes it.
Is implemented by children, only tha adding of disseminators
and activating the object is done here

uses modifyObject:

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:modifyObject>
         <pid>?</pid>
         <state>?</state>
         <label>?</label>
         <ownerId>?</ownerId>
         <logMessage>?</logMessage>
      </typ:modifyObject>
   </soapenv:Body>
</soapenv:Envelope>

=cut

sub save {
  my ($self) = @_;

  my $log = get_logger();

  $log->logdie("No PID; call 'ingest' or 'load' first")
    unless (defined($self->{PID}));

  if ($self->{existing} == 0) {

    # Make object active
    my $soap = $self->{phaidra}->getSoap("apim");

    my @args;
    push @args, SOAP::Data->new(name => 'pid',   value => $self->{PID});
    push @args, SOAP::Data->new(name => 'state', value => 'A');
    push @args,
      SOAP::Data->new(
      name  => 'logMessage',
      value => 'Changed by Phaidra API'
      );

    my $res = $soap->modifyObject(@args);

    ### my $res  = $soap->modifyObject( $self->{PID}, 'A', undef, undef,
    ###     'Changed by Phaidra API' );

    if ($res->fault) {
      $log->logdie("modifyObject (A) failed: " . $res->faultcode . ": " . $res->faultstring);
    }
    $log->info("modifyObject success");
  }

  # Write RIGHTS-DS. If a RIGHTS-DS already exists - does not matter because we administrate this DS.
  # So create a new one and add/update
  if ($self->{changed_rights}) {
    my $rights = XML::LibXML::Document->createDocument();
    my $root   = $rights->createElementNS("http://phaidra.univie.ac.at/XML/V1.0/rights", "uwr:rights");
    $rights->setDocumentElement($root);
    my $allow = $rights->createElement("uwr:allow");
    $root->appendChild($allow);
    foreach my $s (keys %{$self->{rights}->{usernames}}) {
      my $node = $rights->createElement("uwr:username");
      my $text = $rights->createTextNode($s);
      $node->appendChild($text);
      if (defined($self->{rights}->{usernames}->{$s}->{expires})) {
        $node->setAttribute("expires", $self->{rights}->{usernames}->{$s}->{expires});
      }
      $allow->appendChild($node);
    }
    foreach my $s (keys %{$self->{rights}->{faculties}}) {
      my $node = $rights->createElement("uwr:faculty");
      my $text = $rights->createTextNode($s);
      $node->appendChild($text);
      if (defined($self->{rights}->{faculties}->{$s}->{expires})) {
        $node->setAttribute("expires", $self->{rights}->{faculties}->{$s}->{expires});
      }
      $allow->appendChild($node);
    }
    foreach my $s (keys %{$self->{rights}->{departments}}) {
      my $node = $rights->createElement("uwr:department");
      my $text = $rights->createTextNode($s);
      $node->appendChild($text);
      if (defined($self->{rights}->{departments}->{$s}->{expires})) {
        $node->setAttribute("expires", $self->{rights}->{departments}->{$s}->{expires});
      }
      $allow->appendChild($node);
    }
    foreach my $s (keys %{$self->{rights}->{groups}}) {
      my $node = $rights->createElement("uwr:gruppe");
      my $text = $rights->createTextNode($s);
      $node->appendChild($text);
      if (defined($self->{rights}->{groups}->{$s}->{expires})) {
        $node->setAttribute("expires", $self->{rights}->{groups}->{$s}->{expires});
      }
      $allow->appendChild($node);
    }
    foreach my $s (keys %{$self->{rights}->{spl}}) {
      my $node = $rights->createElement("uwr:spl");
      my $text = $rights->createTextNode($s);
      $node->appendChild($text);
      if (defined($self->{rights}->{spl}->{$s}->{expires})) {
        $node->setAttribute("expires", $self->{rights}->{spl}->{$s}->{expires});
      }
      $allow->appendChild($node);
    }
    foreach my $s (keys %{$self->{rights}->{kennzahl}}) {
      my $node = $rights->createElement("uwr:kennzahl");
      my $text = $rights->createTextNode($s);
      $node->appendChild($text);
      if (defined($self->{rights}->{kennzahl}->{$s}->{expires})) {
        $node->setAttribute("expires", $self->{rights}->{kennzahl}->{$s}->{expires});
      }
      $allow->appendChild($node);
    }
    foreach my $s (keys %{$self->{rights}->{perfunk}}) {
      my $node = $rights->createElement("uwr:perfunk");
      my $text = $rights->createTextNode($s);
      $node->appendChild($text);
      if (defined($self->{rights}->{perfunk}->{$s}->{expires})) {
        $node->setAttribute("expires", $self->{rights}->{perfunk}->{$s}->{expires});
      }
      $allow->appendChild($node);
    }

    $log->debug("created RIGHTS-DS: " . $rights->toString());

    # Also an existing object may not have a RIGHTS-DS - so try modifyDatastream and then addDatastream
    eval {$self->modifyDatastreamByValue("RIGHTS", "text/xml", $rights->toString(), "Rights", "X");};
    if ($@) {
      $self->addDatastreamContent("RIGHTS", "text/xml", $rights->toString(), "Rights", "X");
    }
    $self->{changed_rights} = 0;
  }

  # now creating the object is done.
  $self->{existing} = 1;
}

###############################################################################
# Rightsmanagement - same for every object type.

sub grantUsername {
  my ($self, $username, $expire) = @_;

  $self->grant("username", $username, $expire);
}

sub grantOrgEinheit {
  my ($self, $orgeinheit, $expire) = @_;

  $self->grant("orgeinheit", $orgeinheit, $expire);
}

sub grantSubEinheit {
  my ($self, $subeinheit, $expire) = @_;

  $self->grant("subeinheit", $subeinheit, $expire);
}

sub grantGroup {
  my ($self, $group, $expire) = @_;

  $self->grant("group", $group, $expire);
}

sub grantSPL {
  my ($self, $SPL, $expire) = @_;

  $self->grant("spl", $SPL, $expire);
}

sub grantStudienKennzahl {
  my ($self, $code, $expire) = @_;

  $self->grant("studienkennzahl", $code, $expire);
}

sub grantFunktion {
  my ($self, $code, $expire) = @_;

  $self->grant("funktion", $code, $expire);
}

sub revokeUsername {
  my ($self, $username) = @_;

  $self->revoke("username", $username);
}

sub revokeOrgEinheit {
  my ($self, $orgeinheit) = @_;

  $self->revoke("orgeinheit", $orgeinheit);
}

sub revokeSubEinheit {
  my ($self, $subeinheit) = @_;

  $self->revoke("subeinheit", $subeinheit);
}

sub revokeGroup {
  my ($self, $group) = @_;

  $self->revoke("group", $group);
}

sub revokeSPL {
  my ($self, $spl) = @_;

  $self->revoke("spl", $spl);
}

sub revokeStudienKennzahl {
  my ($self, $code) = @_;

  $self->revoke("studienkennzahl", $code);
}

sub revokeFunktion {
  my ($self, $code) = @_;

  $self->revoke("funktion", $code);
}

# Adding right. Save it in internal object structure - will be saved at save()
sub grant {
  my ($self, $what, $who, $expire) = @_;

  my $log = get_logger();

  my $where;
  if ($what eq 'username') {
    $where = "usernames";
  }
  elsif ($what eq 'orgeinheit') {
    $where = "faculties";
  }
  elsif ($what eq 'subeinheit') {
    $where = "departments";
  }
  elsif ($what eq 'group') {
    $where = "groups";
  }
  elsif ($what eq 'spl') {
    $where = "spl";
  }
  elsif ($what eq 'studienkennzahl') {
    $where = "kennzahl";
  }
  elsif ($what eq 'funktion') {
    $where = "perfunk";
  }
  else {
    $log->logdie("grant: invalid mode: $what");
  }

  $self->{rights}->{$where}->{$who} = {who => $who, expires => $expire};
  $self->{changed_rights} = 1;

  $log->debug("grant $what $who: rights now: " . Dumper($self->{rights}));
}

# Removing right. Save it in internal object structure - will be saved at save()
sub revoke {
  my ($self, $what, $who) = @_;

  my $log = get_logger();

  my $where;
  if ($what eq 'username') {
    $where = 'usernames';
  }
  elsif ($what eq 'orgeinheit') {
    $where = 'faculties';
  }
  elsif ($what eq 'subeinheit') {
    $where = 'departments';
  }
  elsif ($what eq 'group') {
    $where = "groups";
  }
  elsif ($what eq 'spl') {
    $where = "spl";
  }
  elsif ($what eq 'studienkennzahl') {
    $where = "kennzahl";
  }
  elsif ($what eq 'funktion') {
    $where = "perfunk";
  }
  else {
    $log->logdie("revoke: invalid mode: $what");
  }

  delete $self->{rights}->{$where}->{$who};
  $self->{changed_rights} = 1;

  $log->debug("revoke $what $who: rights now: " . Dumper($self->{rights}));
}

sub addObjectToPapers {
  my ($self, $pids) = @_;

  my $log = get_logger();

  my @relationships = ();
  foreach my $pid (@$pids) {
    push @relationships,
      {
      predicate => "info:fedora/fedora-system:def/relations-external#isPartOfPaper",
      object    => $pid
      };
  }

  $self->addRelationships(\@relationships);

  $log->debug("isPart: success");
}

sub removeObjectFromPapers {
  my ($self, $pids) = @_;

  my $log = get_logger();

  my @relationships = ();
  foreach my $pid (@$pids) {
    push @relationships,
      {
      predicate => "info:fedora/fedora-system:def/relations-external#isPartOfPaper",
      object    => $pid
      };
  }

  $self->purgeRelationships(\@relationships);

  $log->debug("removeParts: success");
}

sub isPartOfPapers {
  my ($self) = @_;

  my $rels = $self->getRelationships("info:fedora/fedora-system:def/relations-external#isPartOfPaper");

  my $parts = undef;
  foreach my $r (@$rels) {
    if ($r->{object} =~ m/^info:fedora\/(.*)$/i) {
      push @$parts, $1;
    }
  }

  return $parts;
}

=head2 modifyObject

<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.fedora.info/definitions/1/0/types/">
   <soapenv:Header/>
   <soapenv:Body>
      <typ:modifyObject>
         <pid>?</pid>
         <state>?</state>
         <label>?</label>
         <ownerId>?</ownerId>
         <logMessage>?</logMessage>
      </typ:modifyObject>
   </soapenv:Body>
</soapenv:Envelope>


=cut

sub modifyObject {
  my ($self, $state, $label, $ownerid, $logmessage) = @_;

  my $log = get_logger();

  # call modifyObject

  my $soap = $self->{phaidra}->getSoap("apim");
  my @args;
  push @args, SOAP::Data->new(name => 'pid',     value => $self->{PID});
  push @args, SOAP::Data->new(name => 'state',   value => $state);
  push @args, SOAP::Data->new(name => 'label',   value => $label);
  push @args, SOAP::Data->new(name => 'ownerId', value => $ownerid);

  push @args,
    SOAP::Data->new(
    name  => 'logMessage',
    value => SOAP::Data->type(string => $logmessage)
    );

  my $res = $soap->modifyObject(@args);

  ###my $res = $soap->modifyObject($self->{PID}, $state, $label, $ownerid, SOAP::Data->type(string => $logmessage));

  if ($res->fault) {
    $log->logdie("modifyObject failed: " . $res->faultcode . ": " . $res->faultstring);
  }

  $log->info("modifyObject success: DSID = " . $res->result);
}

=head2 touchObject

change no thing, just create an update so that
info:fedora/fedora-system:def/view#lastModifiedDate
gets updated

=cut

sub touchObject() {
  my ($self) = @_;

  my $log = get_logger();
  $log->info("touching object: " . $self->{PID});
  $self->modifyObject(undef, undef, undef, 'touchObject by Phaidra API');
}

################################################################################

=head2 xmlescape

FIXME: This probably doesn't cover half the things
it needs to do, replace by library module?

=cut

sub xmlescape {
  my ($in) = @_;

  $in =~ s/&/&amp;/go;
  $in =~ s/</&lt;/go;
  $in =~ s/>/&gt;/go;
  $in =~ s/'/&apos;/go;
  $in =~ s/"/&quot;/go;

  return $in;
}

1;
