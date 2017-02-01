package PhaidraAPI::Model::Mods::Extraction;

use strict;
use warnings;
use v5.10;
use utf8;
use base qw/Mojo::Base/;
use PhaidraAPI::Model::Terms;

our %mods_contributor_roles =
(
  'ctb' => 1
);

our %mods_creator_roles =
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

sub _get_mods_classifications {

  my ($self, $c, $dom) = @_;

  my @cls;
  for my $e ($dom->find('mods > classification')->each){
    my $text = $e->text;
    if(defined($text) && $text ne ''){
      if(defined($e->attr->{authority}) && $e->attr->{authority} ne ''){
        $text = $e->attr->{authority}.": ".$text; 
      }
      push @cls, { value => $text };
    }else{
      if(defined($e->attr->{valueURI})){    
        my $uri = $e->attr->{valueURI};
        my $terms_model = PhaidraAPI::Model::Terms->new;
        my $res = $terms_model->label($c, $uri); 
        if($res->{status} eq 200){
          if(defined($res->{labels})){
            if(defined($res->{labels}->{labels})){
              # use only en if available
              if(defined($res->{labels}->{labels}->{en})){
                push @cls, { value => $res->{labels}->{labels}->{en}, lang => 'eng' };
              }else{
                # if en not available, use everything else
                if(defined($res->{labels}->{labels}->{de})){
                  push @cls, { value => $res->{labels}->{labels}->{de}, lang => 'deu' };
                }
                if(defined($res->{labels}->{labels}->{it})){
                  push @cls, { value => $res->{labels}->{labels}->{it}, lang => 'ita' };
                }
              }
            }
          }
        }else{
          $c->app->log->error("Could not fetch label for classification uri[$uri] res=".$c->app->dumper($res));
        }
      }
    }
    
  }

  return \@cls;
}

sub _get_mods_creators {
  my ($self, $c, $dom, $mode) = @_;

  $mode = 'p' unless defined $mode;

  my @creators;

  for my $name ($dom->find('mods name[type="personal"]')->each){
    my $role = $name->find('role roleTerm[type="code"][authority="marcrelator"]')->first;
    if(defined($role)){
      $role = $role->text;
      if($mods_creator_roles{$role}){
        my $firstname = $name->find('namePart[type="given"]')->map('text')->join(" ");
        my $lastname = $name->find('namePart[type="family"]')->map('text')->join(" ");

        if(defined($firstname) && $firstname ne '' && defined($lastname) && $lastname ne ''){
          if($mode eq 'oai'){
            # APA bibliographic style
            my $initials = ucfirst(substr($firstname, 0, 1));
            push @creators, { value => "$lastname, $initials ($firstname)" };
          }else{
            push @creators, { value => "$lastname, $firstname" };
          }
        }else{
          my $name = $name->find('namePart')->map('text')->join(" ");
          push @creators, { value => $name };
        }
      }
    }

  }

  return \@creators;
}

sub _get_mods_contributors {
  my ($self, $c, $dom, $mode) = @_;

  $mode = 'p' unless defined $mode;

  my @contributors;

  for my $name ($dom->find('mods name[type="personal"]')->each){
    my $role = $name->find('role roleTerm[type="code"][authority="marcrelator"]')->first;
    if(defined($role)){
      $role = $role->text;
      if($mods_contributor_roles{$role}){
        my $firstname = $name->find('namePart[type="given"]')->map('text')->join(" ");
        my $lastname = $name->find('namePart[type="family"]')->map('text')->join(" ");

        if(defined($firstname) && $firstname ne '' && defined($lastname) && $lastname ne ''){
          if($mode eq 'oai'){
            # APA bibliographic style
            my $initials = ucfirst(substr($firstname, 0, 1));
            push @contributors, { value => "$lastname, $initials ($firstname)" };
          }else{
            push @contributors, { value => "$lastname, $firstname" };
          }
        }else{
          my $namepart = $name->find('namePart')->map('text')->join(" ");
          push @contributors, { value => $namepart };
        }
      }
    }

  }

  for my $name ($dom->find('mods name[type="corporate"]')->each){
    my $namepart = $name->find('namePart')->map('text')->join(" ");
    push @contributors, { value => $namepart };
  }

  return \@contributors;
}

sub _get_mods_relations {
  my ($self, $c, $dom) = @_;

  my @relations;

  # find relateditem
  for my $e ($dom->find('mods relatedItem')->each){

    # identifier
    for my $id ($e->find('identifier')->each){
      push @relations, { value => $id->text };
    }

    #title
    for my $titleInfo ($e->find('titleInfo')->each){
      my $tit = $e->find('title')->map('text')->join(" ");
      my $subtit = $e->find('subTitle')->map('text')->join(" ");

      if($subtit && $subtit ne ''){
        $tit .= ": $subtit";
      }
      push @relations, { value => $tit };
    }
  }

  return \@relations;
}

sub _get_mods_subjects {
  my ($self, $c, $dom) = @_;

  my @subs;

  for my $e ($dom->find('subject')->each){
    my @s_arr;
    # not 'cartographics' (scale is saved there), that goes to description
    push @s_arr, $e->find('geographic')->map('text')->join(";");
    push @s_arr, $e->find('topic')->map('text')->join(";");
    push @s_arr, $e->find('genre')->map('text')->join(";");
    push @s_arr, $e->find('temporal')->map('text')->join(";");
    for my $n ($e->find('name')->each){
      push @s_arr, $n->find('namePart')->map('text')->join(",");      
    }    

    @s_arr = grep defined, @s_arr;
    @s_arr = grep /\w+/, @s_arr;
    my $cnt = scalar @s_arr;
    if($cnt > 0){
      push @subs, { value => join(';', @s_arr) };
    }
  }

  return \@subs;
}

sub _get_mods_titles {
  my ($self, $c, $dom) = @_;

  my @tits; # yes, tits
  # each titleInfo will be a separate title
  for my $e ($dom->find('titleInfo')->each){
    # there should be one title element, whatewer attribute is has
    # like tranlsated, parallel and what not
    # it will be simply added as a title in dc
    # if there is a subtitle, it will be added with ':' after the title
    my $tit = $e->find('title')->map('text')->join(" ");
    my $subtit = $e->find('subTitle')->map('text')->join(" ");
    if($subtit && $subtit ne ''){
      $tit .= ": $subtit";
    }

    push @tits, { value => $tit };
  }

  return \@tits;
}

sub _get_mods_element_values {

  my ($self, $c, $dom, $elm) = @_;

  my @vals;
  for my $e ($dom->find($elm)->each){
    my %v = ( value => $e->content );
    if($e->attr('lang')){
        $v{lang} = $e->attr('lang');
    }
    push @vals, \%v;
  }

  return \@vals;
}

1;
__END__
