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

our %jsonld_identifiers =
(
  'schema:url' => 'url',
  'identifiers:urn' => 'urn',
  'identifiers:hdl' => 'hdl',
  'identifiers:doi' => 'doi',
  'identifiers:isbn' => 'isbn',
  'identifiers:issn' => 'issn',
  'identifiers:local' => 'local'
);

sub _get_jsonld_titles {

  my ($self, $c, $jsonld) = @_;

  my @dctitles;

  my $titles = $jsonld->{'dce:title'};

  for my $o (@{$titles}) {
    my $new = {
      value => $o->{'bf:mainTitle'}->{'@value'}
    };
    if(exists($o->{'bf:subtitle'}) && exists($o->{'bf:subtitle'}->{'@value'}) && ($o->{'bf:subtitle'}->{'@value'} ne '')){
      $new->{value} = $new->{value} . " : " . $o->{'bf:subtitle'}->{'@value'};
    }
    if(exists($o->{'bf:mainTitle'}->{'@language'}) && ($o->{'bf:mainTitle'}->{'@language'} ne '')){
      $new->{lang} = $o->{'bf:mainTitle'}->{'@language'};
    }
    push @dctitles, $new;
  }

  return \@dctitles;
}

sub _get_jsonld_descriptions {

  my ($self, $c, $jsonld) = @_;

  my @dcdescriptions;

  my $bfnotes = $jsonld->{'bf:note'};

  for my $o (@{$bfnotes}) {
    my $new = {
      value => $o->{'rdfs:label'}->{'@value'}
    };
    if(exists($o->{'@language'}) && ($o->{'@language'} ne '')){
      $new->{lang} = $o->{'@language'};
    }
    push @dcdescriptions, $new;
  }

  return \@dcdescriptions;
}

sub _get_jsonld_objectlabels {

  my ($self, $c, $jsonld, $predicate) = @_;

  my @labels;

  my $objects = $jsonld->{$predicate};
  if(ref($objects) ne 'ARRAY'){
    $objects = [ $jsonld->{$predicate} ];
  }
  for my $o (@{$objects}) {
    my $rdfslabels = $o->{'rdfs:label'};
    if(ref($rdfslabels) ne 'ARRAY'){
      $rdfslabels = [ $o->{'rdfs:label'} ];
    }
    for my $l (@{$rdfslabels}){
      my $new = {
        value => $l->{'@value'}
      };
      if(exists($l->{'@language'}) && ($l->{'@language'} ne '')){
        $new->{lang} = $l->{'@language'};
      }
      push @labels, $new;
    }
  }

  return \@labels;
}

sub _get_jsonld_subjects {

  my ($self, $c, $jsonld) = @_;

  my @dcsubjects;
  my $subs = $jsonld->{'dcterms:subject'};

  if($jsonld->{'opaque:ethnographic'}){
    for my $s (@{$jsonld->{'opaque:ethnographic'}}){
      push @{$subs}, $s;
    }
  }

  if($jsonld->{'dce:subject'}){
    for my $s (@{$jsonld->{'dce:subject'}}){
      push @{$subs}, $s;
    }
  }

  for my $o (@{$subs}) {

    next if ($o->{'@type'} eq 'phaidra:Subject');

    for my $s (@{$o->{'skos:prefLabel'}}){
      my $new = {
        value => $s->{'@value'}
      };
      if(exists($s->{'@language'}) && ($s->{'@language'} ne '')){
        $new->{lang} = $s->{'@language'};
      }

      push @dcsubjects, $new;
    }
    
    for my $s (@{$o->{'rdfs:label'}}){
      my $new = {
        value => $s->{'@value'}
      };
      if(exists($s->{'@language'}) && ($s->{'@language'} ne '')){
        $new->{lang} = $s->{'@language'};
      }

      push @dcsubjects, $new;
    }
    
  }

  return \@dcsubjects;
}

=head x
sub _get_jsonld_identifiers {

  my ($self, $c, $jsonld) = @_;

  my @ids;

  for my $id_predicate (keys %jsonld_identifiers){
    if(exists($jsonld->{$id_predicate}) && $jsonld->{$id_predicate} ne ''){
      for my $id (@{$jsonld->{$id_predicate}}){
        push @ids, { value => $jsonld_identifiers{$id_predicate}.":".$id };
      }
    }
  }

  return \@ids;
}
=cut

sub _get_jsonld_languages {

  my ($self, $c, $jsonld) = @_;

  my @langs;

  my $languages = $jsonld->{'dcterms:language'};

  for my $lang (@{$languages}){
    if($lang =~ m/http:\/\/id.loc.gov\/vocabulary\/iso639-2\/(\w+)/g){
      push @langs, { value => $1 };
    }
  }

  return \@langs;
}

sub _get_jsonld_roles {

  my ($self, $c, $jsonld) = @_;
  
  my @creators; 
  my @contributors;
  for my $pred (keys %{$jsonld}){
    if($pred =~ m/role:(\w+)/g){
      my $role = $1;
      my $name;
      for my $contr (@{$jsonld->{$pred}}){
        if($contr->{'@type'} eq 'schema:Person'){
          $name = $contr->{'schema:givenName'}->{'@value'}." ".$contr->{'schema:familyName'}->{'@value'};
        }elsif($contr->{'@type'} eq 'schema:Organisation'){
          $name = $contr->{'schema:name'}->{'@value'};
        }else{
          $c->app->log->error("_get_jsonld_roles: Unknown contributor type in jsonld");
        }
      }
      if($jsonld_creator_roles{$role}){
        push @creators, { value => $name };
      }else{
        push @contributors, { value => $name };
      }
    }
  }

  return (\@creators, \@contributors);
}

sub _get_jsonld_langvalues {

  my ($self, $c, $jsonld, $predicate) = @_;

  my @arr;
  for my $l (@{$jsonld->{$predicate}}){
    my $new = {
      value => $l->{'@value'}
    };
    if(exists($l->{'@language'}) && ($l->{'@language'} ne '')){
      $new->{lang} = $l->{'@language'};
    }
    push @arr, $new;
  }
  return \@arr;
}

sub _get_jsonld_values {

  my ($self, $c, $jsonld, $predicate) = @_;

  my $p = $jsonld->{$predicate};
  my @arr;
  if(ref($p) eq 'ARRAY'){
    for my $l (@{$p}){
      push @arr, { value => $l };
    }
  }else{
    push @arr, { value => $p };
  }
  return \@arr;
}

1;
__END__
