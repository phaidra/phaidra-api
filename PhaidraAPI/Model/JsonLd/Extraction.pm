package PhaidraAPI::Model::JsonLd::Extraction;

use strict;
use warnings;
use v5.10;
use utf8;
use base qw/Mojo::Base/;
use PhaidraAPI::Model::Terms;

our %jsonld_contributor_roles =
(
  'ctb' => 1
);

our %jsonld_creator_roles =
(
  'aut' => 1,
  'prt' => 1,
  'edt' => 1,
  'ill' => 1,
  'dte' => 1,
  'drm' => 1,
  'ctg' => 1,
  'ltg' => 1,
  'egr' => 1
);

sub _get_jsonld_titles {

  my ($self, $c, $jsonld) = @_;

  my @dctitles;

  my $titles = $jsonld->{'dce:title'};

  for my $t (@{$titles}) {
    my $ti = $t->{'bf:mainTitle'};
    if(exists($t->{'bf:subtitle'}) && ($t->{'bf:subtitle'} ne '')){
      $ti->{'@value'} = $ti->{'@value'} . " : " . $t->{'bf:subtitle'}->{'@value'};
    }
    push @dctitles, { value => $ti->{'@value'}, lang => $ti->{'@language'} }
  }

  return \@dctitles;
}

sub _get_jsonld_descriptions {

  my ($self, $c, $jsonld) = @_;

  my @dcdescriptions;

  my $descriptions = $jsonld->{'bf:note'};

  for my $d (@{$descriptions}) {
    push @dcdescriptions, { value => $d->{'@value'}, lang => $d->{'@language'} }
  }

  return \@dcdescriptions;
}

1;
__END__
