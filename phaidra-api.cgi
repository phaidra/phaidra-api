#!/usr/bin/env perl

use strict;
use warnings;

# Start command line interface for application
require Mojolicious::Commands;
Mojolicious::Commands->start_app('PhaidraAPI');
