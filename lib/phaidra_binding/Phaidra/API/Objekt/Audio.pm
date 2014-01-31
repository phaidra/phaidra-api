#!/usr/bin/perl -w
#
# Phaidra API Audio Object class.
#

use strict;
use warnings;

package Phaidra::API::Objekt::Audio;

use URI::Escape;
use Data::Dumper;
use Log::Log4perl qw(get_logger);
use base 'Phaidra::API::Objekt';

# Ingest object
sub ingest
{
	my ($self, $label) = @_;

	$self->SUPER::ingest($label, "cmodel:Audio");
}

sub load
{
	my ($self, $pid) = @_;

	$self->SUPER::load($pid, "cmodel:Audio");
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
		$self->addDatastreamLocation("THUMBNAIL", "image/png", "http://".$self->{phaidra}->{config}->{staticbaseurl}."/thumbs/audio.png", "THUMBNAIL label", "E");
	}


	$self->SUPER::save();
}

# Specialized addDatastream
sub addAudio
{
        my ($self, $filename, $mimetype) = @_;

        # TODO basename($filename) for Label
        $self->addDatastream("OCTETS", $mimetype, $filename, $filename, "M");
}

1;
