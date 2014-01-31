#!/usr/bin/perl -w
#
# Phaidra API Other Object class.
#
# $Id$

use strict;
use warnings;

package Phaidra::API::Objekt::Other;

use URI::Escape;
use Data::Dumper;
use Log::Log4perl qw(get_logger);
use base 'Phaidra::API::Objekt';

# Ingest object
sub ingest
{
	my ($self, $label) = @_;

	$self->SUPER::ingest($label, "cmodel:Asset");
}

sub load
{
	my ($self, $pid) = @_;

	$self->SUPER::load($pid, "cmodel:Asset");
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
		$self->addDatastreamLocation("THUMBNAIL", "image/png", "http://".$self->{phaidra}->{config}->{staticbaseurl}."/thumbs/unknown.png", "THUMBNAIL label", "E");
	}


	$self->SUPER::save();
}

# Specialized addDatastream for Other-files
sub addFile
{
	my ($self, $filename, $contenttype) = @_;

	# TODO basename($filename) for Label?
	$self->addDatastream("OCTETS", $contenttype, $filename, $filename, "M");
}

1;
