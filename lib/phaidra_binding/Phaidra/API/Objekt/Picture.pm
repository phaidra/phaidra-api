#!/usr/bin/perl -w
#
# Phaidra API Picture Object class.
#
# $Id: Picture.pm 1889 2010-05-19 06:12:16Z swdevel $

use strict;
use warnings;

package Phaidra::API::Objekt::Picture;

use URI::Escape;
use Data::Dumper;
use Log::Log4perl qw(get_logger);
use base 'Phaidra::API::Objekt';

# Ingest object
sub ingest
{
	my ($self, $label) = @_;

	$self->SUPER::ingest($label, "cmodel:Picture");
}

sub load
{
	my ($self, $pid) = @_;

	$self->SUPER::load($pid, "cmodel:Picture");
}

# save
#
# save object.
sub save
{
	my ($self) = @_;

	my $log = get_logger();

	$log->logdie("No PID; call 'ingest' or 'load' first") unless(defined($self->{PID}));

	if($self->{existing} == 0)
	{
		# add Default-Datastreams
		$self->addDatastreamLocation("STYLESHEET", "text/xml", $self->{phaidra}->{config}->{fedorastylesheeturl}, "STYLESHEET label", "E");
		#$self->addDatastreamLocation("THUMBNAIL", "image/png", $self->{phaidra}->{config}->{fedoraurlgetinternal}."/".$self->{PID}."/bdef:ImageManipulator/boxImage?BOX=120&FORMAT=png&PAD=1", "THUMBNAIL label", "E");
		$self->addDatastreamLocation("THUMBNAIL", "image/png", $self->{phaidra}->{config}->{fedoraurlgetinternal}."/".$self->{PID}."/bdef:Asset/getThumbnail", "THUMBNAIL label", "E");
	}

	$self->SUPER::save();
}

# Specialized addDatastream
sub addPicture
{
	my ($self, $filename, $mimetype) = @_;

	# TODO basename($filename) for Label
	$self->addDatastream("OCTETS", $mimetype, $filename, $filename, "M");
}

1;
