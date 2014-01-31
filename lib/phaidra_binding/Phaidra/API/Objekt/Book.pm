#!/usr/bin/perl -w
#
# Phaidra API Book Object class.
#
# $Id: Book.pm 1382 2013-01-10 15:04:50Z univie $
# $URL: https://svn.phaidra.univie.ac.at/phaidra/trunk/api/perl/Phaidra/API/Objekt/Book.pm $
#

use strict;
use warnings;

package Phaidra::API::Objekt::Book;

use URI::Escape;
use Data::Dumper;
use Encode;
use Log::Log4perl qw(get_logger);
use base 'Phaidra::API::Objekt';

# Ingest book object
sub ingest
{
	my ($self, $label) = @_;

	$self->SUPER::ingest($label, "cmodel:Book");

	$self->{members} = undef;
}

sub load
{
	my ($self, $pid) = @_;

	my $log = get_logger();

	$log->logdie("Books are write only for now, sorry");
}

# save
#
# Save object.
sub save
{
	my ($self) = @_;

	my $log = get_logger();

	$log->logdie("No PID; call 'ingest' or 'load' first") unless(defined($self->{PID}));

	# create BOOKINFO and save
	my $bookinfo = '<book:book xmlns:book="http://phaidra.univie.ac.at/XML/book/V1.0"> <book:pages>'."\n";
	my $firstpagepid = undef;
	foreach my $cnr (sort { $a <=> $b } keys %{$self->{chapters}})
	{
		my $chapter = $self->{chapters}->{$cnr};
		$bookinfo .= "<book:structure name=\"".xmlescape($chapter->{label})."\" seq=\"$cnr\">\n";
		foreach my $page (sort { $a->{pageinfo}->{abspagenum} <=> $b->{pageinfo}->{abspagenum} } @{$chapter->{pages}})
		{
			my $startpagexml = "";
			if(defined($page->{pageinfo}->{startpage}) && $page->{pageinfo}->{startpage} eq 'true')
			{
				$startpagexml = "startpage=\"true\"";
			}
			$bookinfo .= "<book:page abspagenum=\"".xmlescape($page->{pageinfo}->{abspagenum})."\" pagenum=\"".xmlescape($page->{pageinfo}->{pagenum})."\" pid=\"".xmlescape($page->{PID})."\" $startpagexml />\n";
			$firstpagepid = $page->{PID} unless(defined($firstpagepid));
		}
		$bookinfo .= "</book:structure>\n";
	}
	$bookinfo.= "\n</book:pages></book:book>";
	
	if($self->{existing} == 0)
	{
		$self->addDatastreamContent("BOOKINFO", "text/xml", encode("utf-8", $bookinfo), "BOOKINFO", "X");
	}else{
		$self->modifyDatastreamByValue("BOOKINFO", "text/xml", encode("utf-8", $bookinfo), "BOOKINFO", "X");	
	}
	
	# A book without pages? Impossible! 
	$log->logdie("Book has no pages!") unless(defined($firstpagepid));
            
	$self->{bookinfoxml} = $bookinfo;

	if($self->{existing} == 0)
	{
		# Default-Datastreams anlegen
		$self->addDatastreamLocation("STYLESHEET", "text/xml", $self->{phaidra}->{config}->{fedorastylesheeturl}, "STYLESHEET label", "E");
		# THUMBNAIL beim Bild: die erste Buchseite.
		$self->addDatastreamLocation("THUMBNAIL", "image/png", $self->{phaidra}->{config}->{fedoraurlgetinternal}."/$firstpagepid/bdef:ImageManipulator/boxImage?BOX=120&FORMAT=png&PAD=1", "THUMBNAIL label", "E");
	}

	# Set relationships: Book-Pages are "members" of the Book-Object
	my @relationships = ();
	foreach my $mpid (@{$self->{members}})
	{
		push @relationships, { predicate => "info:fedora/fedora-system:def/relations-external#hasCollectionMember",
				       object => $mpid };
	}
	$self->addRelationships(\@relationships);

	$self->SUPER::save();
}

# Create Chapter - for BOOKINFO - and return it
sub addChapter
{
	my ($self, $label) = @_;

	my $chapter = { label => $label, pages => undef };

	if(!defined($self->{nextcnr}))
	{
		$self->{nextcnr} = 0;
	}
	my $cnr = $self->{nextcnr};
	$self->{nextcnr}++;

	$self->{chapters}->{$cnr} = $chapter;

	return $chapter;
}

# Specialized addDatastream for PDF-Files
sub addPDF
{
	my ($self, $filename) = @_;

	# TODO basename($filename) for Label?
	$self->addDatastream("OCTETS", "application/pdf", $filename, $filename, "M");
}

# Add Page-Object to chapter
# Until save() the members are only saved in the object
sub addPage
{
	my ($self, $chapter, $page) = @_;

	my $log = get_logger();

	# add memeber into the internal array of the object
	push @{$self->{members}}, $page->{PID};

	# Uniq
	my %h = map { $_ => 1 } @{$self->{members}};
	@{$self->{members}} = keys %h;

	# add page into chapter
	push @{$chapter->{pages}}, $page;
	
	$log->debug("addPage: members now: ".join(",", @{$self->{members}}));
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

1;
