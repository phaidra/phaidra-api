#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use MongoDB 1.8.3;
use DateTime;
use DateTime::Format::ISO8601;
use Time::HiRes qw/tv_interval gettimeofday/;
use Mojo::JSON qw(from_json);

my $folders = {
  'datastreams' => {
    'path' => '/usr/local/fedora/data/datastreams',
    'size' => undef
  },
  'objects' => {
    'path' => '/usr/local/fedora/data/objects',
    'size' => undef
  },
  'imageserver' => {
    'path' => '/usr/local/phaidra/imageserver',
    'size' => undef
  },
  'ocflroot' => {
    'path' => $ENV{FEDORA_OCFL_ROOT},
    'size' => undef
  }
};

my $configPath = '/usr/local/phaidra/phaidra-api/PhaidraAPI.json'
my $json_text = do {
  open(my $json_fh, "<:encoding(UTF-8)", $configPath) or die("Can't open file[".$configPath."]: $!\n");
  local $/;
  <$json_fh>
};

my $config = from_json($json_text);

my $mongo = MongoDB::MongoClient->new(
  host               => $config->{mongodb}->{host},
  port               => $config->{mongodb}->{port},
  username           => $config->{mongodb}->{username},
  password           => $config->{mongodb}->{password},
  connect_timeout_ms => 300000,
  socket_timeout_ms  => 300000,
)->get_database($config->{mongodb}->{database});

for my $f (keys %{$folders}) {
  my $p = $folders->{$f}->{'path'};
  if ($p) {
    if (-d $p) {
      my $t0 = [gettimeofday];
      my $command = "du -s ".$folders->{$f}->{'path'}." | cut -f1";
      my $size = `$command`;
      my $t1 = tv_interval($t0);
      $size =~ s/^\s+|\s+$//g;
      print "du of $p took $t1 s, size=$size\n";
      $folders->{$f}->{size} = $size;
    }
  }
}

my $insert = { 
  timestamp => time, 
  timestamp_iso => DateTime->now->iso8601 . 'Z'
};
for my $f (keys %{$folders}) {
  $insert->{$f} = $folders->{$f}->{size};
}

$mongo->get_collection('storage_stats')->insert_one($insert);

__END__
