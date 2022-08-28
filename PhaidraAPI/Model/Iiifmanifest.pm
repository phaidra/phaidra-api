package PhaidraAPI::Model::Iiifmanifest;

use strict;
use warnings;
use v5.10;
use utf8;
use base qw/Mojo::Base/;
use Mojo::JSON qw(decode_json);
use JSON;
use PhaidraAPI::Model::Index;
use PhaidraAPI::Model::Object;

sub update_manifest_metadata {

  my ($self, $c, $pid) = @_;

  my $res = {alerts => [], status => 200};

  my $index_model = PhaidraAPI::Model::Index->new;
  my $r           = $index_model->get($c, $pid);
  if ($r->{status} ne 200) {
    return $r;
  }
  my $index = $r->{index};

  $c->app->log->debug("XXXXXXXXXXXXXXXXXXXXXXXXXXXX" . $c->app->dumper($index));

  my $object_model = PhaidraAPI::Model::Object->new;
  $r = $object_model->get_datastream($c, $pid, 'IIIF-MANIFEST', $c->stash->{basic_auth_credentials}->{username}, $c->stash->{basic_auth_credentials}->{password});
  if ($r->{status} ne 200) {
    return $r;
  }

  my $manifest = decode_json($r->{'IIIF-MANIFEST'});
  delete $manifest->{seeAlso};
  delete $manifest->{description};
  delete $manifest->{metadata};
  delete $manifest->{attribution};
  delete $manifest->{requiredStatement};
  delete $manifest->{license};
  delete $manifest->{rights};
  delete $manifest->{label};
  delete $manifest->{summary};
  $manifest->{metadata} = [];

  if (exists($index->{dc_title_eng})) {
    $manifest->{label} = {'en' => [$index->{dc_title_eng}]};
  }
  else {
    $manifest->{label} = {'en' => [$index->{sort_dc_title}]};
  }

  if (exists($index->{dc_description})) {
    $manifest->{summary} = {'en' => [$index->{dc_description}]};
  }

  $manifest->{homepage} = [
    { "id"     => 'https://' . $c->app->config->{phaidra}->{baseurl} . '/detail/' . $pid,
      "type"   => "Text",
      "label"  => {"en" => ["Detail page"]},
      "format" => "text/html"
    }
  ];

  push @{$manifest->{metadata}},
    {
    label => {"en"   => ["Identifier"]},
    value => {"none" => ['https://' . $c->app->config->{phaidra}->{baseurl} . '/' . $pid]}
    };

  if (exists($index->{bib_roles_pers_aut})) {
    my $authors = [];
    for my $a (@{$index->{bib_roles_pers_aut}}) {
      push @{$authors}, $a;
    }
    push @{$manifest->{metadata}},
      {
      label => {"en"   => ["Author"]},
      value => {"none" => $authors}
      };
  }

  if (exists($index->{bib_publisher})) {
    my $pubs = [];
    for my $p (@{$index->{bib_publisher}}) {
      push @{$pubs}, $p;
    }
    push @{$manifest->{metadata}},
      {
      label => {"en"   => ["Publisher"]},
      value => {"none" => $pubs}
      };
  }

  if (exists($index->{bib_published})) {
    my $dateissued = [];
    for my $di (@{$index->{bib_published}}) {
      push @{$dateissued}, $di;
    }
    push @{$manifest->{metadata}},
      {
      label => {"en"   => ["Issued"]},
      value => {"none" => $dateissued}
      };
  }

  if (exists($index->{dc_language})) {
    my $langs = [];
    for my $l (@{$index->{dc_language}}) {
      push @{$langs}, $l;
    }
    push @{$manifest->{metadata}},
      {
      label => {"en"   => ["Language"]},
      value => {"none" => $langs}
      };
  }

  if (exists($index->{dc_rights})) {
    my $statements = [];
    for my $st (@{$index->{dc_rights}}) {
      push @{$statements}, $st;
    }
    $manifest->{requiredStatement} = {
      label => {"en"   => ["Rights"]},
      value => {"none" => $statements}
    };
  }

  my $coder = JSON->new->utf8->pretty;
  my $json  = $coder->encode($manifest);
  return $object_model->add_or_modify_datastream($c, $pid, "IIIF-MANIFEST", "application/json", undef, $c->app->config->{phaidra}->{defaultlabel}, $json, "M", undef, undef, $c->stash->{basic_auth_credentials}->{username}, $c->stash->{basic_auth_credentials}->{password});
}

1;
__END__
