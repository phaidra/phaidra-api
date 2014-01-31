#!/usr/bin/perl -w
#
# Phaidra API Paper Object class.
#

use strict;
use warnings;

package Phaidra::API::Objekt::Paper;

use URI::Escape;
use Data::Dumper;
use Encode;
use File::Basename;
use File::MimeInfo::Magic;
use Log::Log4perl qw(get_logger);
use base 'Phaidra::API::Objekt';

# Ingest Paper object
sub ingest
{
	my ($self, $label) = @_;

	$self->SUPER::ingest($label, "cmodel:Paper");

	$self->{members} = undef;
}

sub load
{
        my ($self, $pid) = @_;

        $self->SUPER::load($pid, "cmodel:Paper");
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
		$self->addDatastreamLocation("STYLESHEET", "text/xml", $self->{phaidra}->{config}->{fedorastylesheeturl}, "STYLESHEET label", "E");
		$self->addDatastreamLocation("THUMBNAIL", "image/png", $self->{phaidra}->{config}->{fedoraurlgetinternal}."/".$self->{PID}."/bdef:Paper/preview?box=120&pad=1", "THUMBNAIL label", "E");
	}

	$self->SUPER::save();
}

# Specialized addDatastream for PDF-files
sub addPDF
{
        my ($self, $filename) = @_;
        $self->addDatastream("OCTETS", "application/pdf", $filename, basename($filename), "M");
}


sub addAbstract
{
	my ($self, $abstract) = @_;
	
	my $log = get_logger();

	$log->logdie("Undefined abstract XML") if(!defined($abstract));
	$log->logdie("Empty abstract XML") if($abstract eq '');
	
	$self->addDatastreamContent("ABSTRACT", "text/xml", $abstract, "Abstract of paper" , "X");
}

sub addPaperParts
{
        my ($self, $pids) = @_;

        my $log = get_logger();

        my @relationships = ();
        foreach my $pid (@$pids)
        {
                push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasPaperPart",
                                       object => $pid };
        }

        $self->addRelationships(\@relationships);

        $log->debug("addParts: success");
}

sub removePaperParts
{
        my ($self, $pids) = @_;

        my $log = get_logger();

        my @relationships = ();
        foreach my $pid (@$pids)
        {
                push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasPaperPart",
                                       object => $pid };
        }

        $self->purgeRelationships(\@relationships);

        $log->debug("removeParts: success");
}

sub getParts
{
        my ($self) = @_;

        my $rels = $self->getRelationships("info:fedora/fedora-system:def/relations-external#hasPaperPart");

        my $parts = undef;
        foreach my $r (@$rels)
        {
                if($r->{object} =~ m/^info:fedora\/(.*)$/i)
                {
                        push @$parts, $1;
                }
        }

        return $parts;
}

1;
