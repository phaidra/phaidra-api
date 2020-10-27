#!/usr/bin/perl -w
#
# A Drop-In-Replacement for SOAP::Lite, the requests repeated if something went wrong.
#
# $Id: Determined.pm 387 2011-07-26 12:36:11Z univie $

package Phaidra::API::SOAP::Determined;

use strict;
use warnings;

our $VERSION = '1.0';
use base 'SOAP::Lite';
use Log::Log4perl qw(get_logger);
use Data::Dumper;

sub call {
  my ($self, @args) = @_;

  my %retry_codes = (408 => 1, 500 => 1, 502 => 1, 503 => 1, 504 => 1);
  my $log         = get_logger();

  my $resp;
  foreach my $pause (1, 3, 15, 0) {
    eval {
      SOAP::Trace::debug("Requesting...");
      $resp = $self->SUPER::call(@args);
      ###$log->debug("Soap object". Dumper $self);
    };
    if ($@) {

      # Something happened at request. First three chars are return code
      my $fehler = $@;
      my $rc     = substr($fehler, 0, 3);
      if ($retry_codes{$rc}) {

        # rc is one of the retry codes that are configured => sleep
        if ($pause) {
          SOAP::Trace::debug("Request failed: |$fehler|, sleeping $pause...");
          sleep($pause);

          # Let's try ist again -> start loop again
        }
        else {
          # Das war's - hoffnungslos
          SOAP::Trace::debug("Request failed: |$fehler|, giving up");
          die($fehler);
        }
      }
      else {
        # Some kind of other error -> return immediately
        SOAP::Trace::debug("Request failed: |$fehler|, RC-code is non-sleepable, giving up immediately");
        die($fehler);
      }
    }
    else {
      # Request had no error -> everything OK :)
      SOAP::Trace::debug("Request success!");
      return $resp;
    }
  }

  # The retries failed -> return error
  SOAP::Trace::debug("Fell through, returning result");
  return $resp;
}

sub new {
  my $self = shift->SUPER::new(@_);
  return $self;
}

1;
