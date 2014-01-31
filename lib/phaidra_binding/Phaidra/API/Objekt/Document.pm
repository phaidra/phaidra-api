#!/usr/bin/perl -w
#
# Phaidra API Document Object class.
#
# $Id: Document.pm 1887 2010-05-18 14:46:34Z swdevel $

use strict;
use warnings;

package Phaidra::API::Objekt::Document;

use URI::Escape;
use Data::Dumper;
use Log::Log4perl qw(get_logger);
use base 'Phaidra::API::Objekt';

# Ingest object
sub ingest
{
	my ($self, $label) = @_;

	$self->SUPER::ingest($label, "cmodel:PDFDocument");
}

sub load
{
	my ($self, $pid) = @_;

	$self->SUPER::load($pid, "cmodel:PDFDocument");
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
		$self->addDatastreamLocation("THUMBNAIL", "image/png", $self->{phaidra}->{config}->{fedoraurlgetinternal}."/".$self->{PID}."/bdef:Document/preview?box=120&pad=1", "THUMBNAIL label", "E");
	}


	$self->SUPER::save();
}

# Specialized addDatastream for PDF-files
sub addPDF
{
	my ($self, $filename) = @_;

	# TODO basename($filename) for Label?
	$self->addDatastream("OCTETS", "application/pdf", $filename, $filename, "M");
}

sub addAbstract
{
	my ($self, $abstract) = @_;
	
	my $log = get_logger();

	$log->logdie("Undefined abstract XML") if(!defined($abstract));
	$log->logdie("Empty abstract XML") if($abstract eq '');
	
	$self->addDatastreamContent("ABSTRACT", "text/xml", $abstract, "Abstract of paper" , "X");
}

1;
