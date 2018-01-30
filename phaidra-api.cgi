#!/usr/bin/env perl

use strict;
use warnings;
use FileHandle; # temporary fix for https://groups.google.com/d/topic/mojolicious/y9J88fboW50/discussion
use lib('/usr/local/phaidra/phaidra-api');

# Start command line interface for application
require Mojolicious::Commands;
Mojolicious::Commands->start_app('PhaidraAPI');
