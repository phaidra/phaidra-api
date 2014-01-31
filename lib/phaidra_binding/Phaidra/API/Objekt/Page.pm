#!/usr/bin/perl -w
#
# Phaidra API Picture Object class.
#
# $Id: Page.pm 1382 2013-01-10 15:04:50Z univie $
# $URL: https://svn.phaidra.univie.ac.at/phaidra/trunk/api/perl/Phaidra/API/Objekt/Page.pm $
#

use strict;
use warnings;

package Phaidra::API::Objekt::Page;

use URI::Escape;
use Data::Dumper;
use Encode;
use Log::Log4perl qw(get_logger);
use base 'Phaidra::API::Objekt';

# Ingest object
sub ingest
{
	my ($self, $label, $bookpid, $abspagenum, $pagenum, $structure, $startpage) = @_;

	$self->{pageinfo} = { abspagenum => $abspagenum, pagenum => $pagenum, bookpid => $bookpid, structure => $structure, startpage => $startpage };

	$self->SUPER::ingest($label, "cmodel:Page");
}

sub load
{
	my ($self, $pid) = @_;

	my $log = get_logger();

	$log->logdie("TODO: pageinfo aus PAGEINFO auslesen");

	$self->SUPER::load($pid, "cmodel:Page");
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
		# TODO: if the filesize < X -> link directly to ImageManipulator
		$self->addDatastreamLocation("THUMBNAIL", "image/png", "http://".$self->{phaidra}->{config}->{staticbaseurl}."/thumbs/page.png", "THUMBNAIL label", "E");
	
		# create PAGEINFO
		my $pageinfoxml = '<page xmlns="http://phaidra.univie.ac.at/XML/page/V1.0">'."\n";
		$pageinfoxml .= "<book abspagenum=\"".xmlescape($self->{pageinfo}->{abspagenum})."\" pagenum=\"".xmlescape($self->{pageinfo}->{pagenum})."\" pid=\"".xmlescape($self->{pageinfo}->{bookpid})."\" structure=\"".xmlescape($self->{pageinfo}->{structure})."\" />\n";
		$pageinfoxml .= "</page>";
		$self->addDatastreamContent("PAGEINFO", "text/xml", encode("utf-8", $pageinfoxml), "PAGEINFO", "X");
	}

	$self->SUPER::save();
}

sub xmlescape
{
	my ($in) = @_;

	$in =~ s/&/&amp;/go;
	$in =~ s/</&lt;/go;
	$in =~ s/>/&gt;/go;
	$in =~ s/'/&apos;/go;
	$in =~ s/"/&quot;/go;

	return $in;
}

# Specialized addDatastream
sub addPicture
{
	my ($self, $filename, $mimetype) = @_;

	# TODO basename($filename) for Label
	$self->addDatastream("OCTETS", $mimetype, $filename, $filename, "M");
}

1;
