#!/usr/bin/perl -w
#
# Phaidra API Collection Object class.
#
# $Id: Collection.pm 1817 2013-07-27 03:37:37Z gg $
# $URL: https://svn.phaidra.univie.ac.at/phaidra/trunk/api/perl/Phaidra/API/Objekt/Collection.pm $
#

use strict;
use warnings;

package Phaidra::API::Objekt::Collection;

use URI::Escape;
use Data::Dumper;
use XML::XPath;
use XML::LibXML;
use Log::Log4perl qw(get_logger);
use base 'Phaidra::API::Objekt';

# Ingest object
sub ingest
{
	my ($self, $label) = @_;

	$self->SUPER::ingest($label, "cmodel:Collection");
}

sub load
{
	my ($self, $pid) = @_;

	$self->SUPER::load($pid, "cmodel:Collection");
}

# save
#
# Save object.
sub save
{
	my ($self) = @_;

	my $log = get_logger();

	$log->logdie("No PID; call 'ingest' or 'load' first") unless(defined($self->{PID}));

	if($self->{existing} == 0)
	{

		# add Default-Datastreams
		$self->addDatastreamLocation("STYLESHEET", "text/xml", $self->{phaidra}->{config}->{fedorastylesheeturl}, "STYLESHEET label", "E");
		$self->addDatastreamLocation("THUMBNAIL", "image/png", "http://".$self->{phaidra}->{config}->{staticbaseurl}."/thumbs/collection.png", "THUMBNAIL label", "E");
	}

	$self->SUPER::save();
}

# Add members (PID) into the collection.
# $pids is an arrayref of PIDs
# The member information will be saved into the object directly. An object that is already declared as a member will be ignored.
sub addMembers
{
	my ($self, $pids) = @_;

	my $log = get_logger();

	my @relationships = ();
	foreach my $pid (@$pids)
	{
		push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasCollectionMember",
				       object => $pid };
	}

	$self->addRelationships(\@relationships);
	
	$log->debug("addMembers: success");
}

# Delete a member from the collection.
# $pids is an arrayref of PIDs
#
# The member information will be saved into the object directly. An object that is already deleted will be ignored.
sub removeMembers
{
	my ($self, $pids) = @_;

	my $log = get_logger();

	my @relationships = ();
	foreach my $pid (@$pids)
	{
		push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasCollectionMember",
				       object => $pid };
	}

	$self->purgeRelationships(\@relationships);
	
	$log->debug("removeMembers: success");
}

# Return actual members list as arrayref. Get data from the object. Returns undef if no members found.
sub getMembers
{
	my ($self) = @_;

	my $rels = $self->getRelationships("info:fedora/fedora-system:def/relations-external#hasCollectionMember");

	my $members = undef;
	foreach my $r (@$rels)
	{
		if($r->{object} =~ m/^info:fedora\/(.*)$/i)
		{
			push @$members, $1;
		}
	}

	return $members;
}

1;
