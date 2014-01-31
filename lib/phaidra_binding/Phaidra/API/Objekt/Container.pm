#!/usr/bin/perl -w
#
# Phaidra API Container Object class.
#
# $Id: Container.pm 1382 2013-01-10 15:04:50Z univie $
# $URL: https://svn.phaidra.univie.ac.at/phaidra/trunk/api/perl/Phaidra/API/Objekt/Container.pm $
#

use strict;
use warnings;

package Phaidra::API::Objekt::Container;

use URI::Escape;
use Data::Dumper;
use Encode;
use File::Basename;
use File::MimeInfo::Magic;
use Log::Log4perl qw(get_logger);
use base 'Phaidra::API::Objekt';

# Ingest Container object
sub ingest
{
	my ($self, $label) = @_;

	$self->SUPER::ingest($label, "cmodel:Container");

	$self->{members} = undef;
}

sub load
{
	my ($self, $pid) = @_;

	my $log = get_logger();

	$log->logdie("Containers are write only for now, sorry");
}

# save
#
# Save object.
sub save
{
	my ($self) = @_;

	my $log = get_logger();

	$log->logdie("No PID; call 'ingest' or 'load' first") unless(defined($self->{PID}));
	$log->logdie("No files found; add some files to CONTAINER object") if(!defined($self->{compIndex}));
	
	#create CONTAINERINFO
	my $setDefault = 0;
	my $containerinfo = '<c:container xmlns:c="http://phaidra.univie.ac.at/XML/V1.0/container">';
	foreach my $ds (@{$self->{compDatastreams}})
	{
		my $default = 'no';
		$default = 'yes' if(!$setDefault && $ds->{default} eq 'yes');
		$containerinfo .= '<c:datastream filename="'.$ds->{filename}.'" default="'.$default.'">'.$ds->{DSID}.'</c:datastream>';
		$setDefault = 1 if($ds->{default} eq 'yes');
	}
	$containerinfo .= '</c:container>';
	$log->logdie("No default datastream found; please set default datastream") if(!$setDefault); 

	# create CONTAINERINFO and save
	$self->addDatastreamContent("CONTAINERINFO", "text/xml", encode("utf-8", $containerinfo), "CONTAINER control information", "X");

	$self->{containerinfoxml} = $containerinfo;

	if($self->{existing} == 0)
	{
		$self->addDatastreamLocation("STYLESHEET", "text/xml", $self->{phaidra}->{config}->{fedorastylesheeturl}, "STYLESHEET label", "E");
		$self->addDatastreamLocation("THUMBNAIL", "image/png", "http://".$self->{phaidra}->{config}->{staticbaseurl}."/thumbs/container.png", "THUMBNAIL label", "E");
	}

	$self->SUPER::save();
}

sub addFile
{
	my ($self, $filename, $default, $mimetype) = @_;

	my $log = get_logger();

	$log->logdie("No filename submitted") if(!defined($filename));
	$log->logdie("Missing default parameter") if(!defined($default));
	$log->logdie("Unexpected default parameter '$default' - allowed parameters -> 'yes' || 'no'") if($default ne 'yes' && $default ne 'no');

	my $DSID = $self->getNextDSID($log);
	my $basename = basename($filename);
	$mimetype = $self->getMIMETYPE($log,$filename,$basename) if (!defined($mimetype));
	push @{$self->{compDatastreams}}, { DSID => $DSID, filename => $basename, mimetype => $mimetype, default => $default };
	$self->addDatastream($DSID, $mimetype, $filename, $basename, "M");
}

sub getNextDSID
{
	my ($self,$logger) = @_;
	
	if(!defined($self->{compIndex}))
	{
		$self->{compIndex} = 0;
	}
	else
	{
		$self->{compIndex}++;
	}
	return sprintf("COMP%06d", $self->{compIndex});	
}

sub getMIMETYPE
{
	my ($self,$logger,$filename,$basename) = @_;

	my $mimetype = File::MimeInfo::Magic::magic($filename);
	unless(defined($mimetype))
        {
		$mimetype = File::MimeInfo::Magic::globs($basename);
		unless(defined($mimetype))
		{
			$logger->logwarn("Unable to determine mimetype of $basename -> fallback 'application/octet-stream'");
			$mimetype = 'application/octet-stream';
		}
	}
	return $mimetype;
}

1;
