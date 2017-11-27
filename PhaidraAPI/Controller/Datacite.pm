package PhaidraAPI::Controller::Datacite;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::ByteStream qw(b);
use Mojo::JSON qw(encode_json decode_json);
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Datacite;

sub get {

  my $self = shift;

  my $pid = $self->stash('pid');
  my $format = $self->param('format');
 
  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $model = PhaidraAPI::Model::Datacite->new;

  my $res = $model->get($self, $pid, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});
  if($res->{status} ne 200){
    $self->render(json => { alerts => $res->{alerts} }, status => $res->{status});
    return;
  }

  # when extracting metadata using Mojo::DOM we use ->content which returns UTF-8 encoded data
  # since we're not going to save the data to fedora but render them, we need to decode them first before passing it to renderer because
  # the renderer will UTF-8 encode the data again
  $self->_decode_rec(undef, $res->{datacite});

  if($format eq 'xml'){
    $self->render(text => $model->json_2_xml($self, $res->{datacite}), format => 'xml');
    return;
  }

  $self->respond_to(
    json => { json => $res->{datacite} },
    xml  => { text => $model->json_2_xml($self, $res->{datacite})},
    any => { json => { metadata => { datacite => $res->{datacite}}}}
  );

}

sub _decode_rec(){

  my $self = shift;
  my $parent = shift;
  my $children = shift;

  foreach my $child (@{$children}){

    my $children_size = defined($child->{children}) ? scalar (@{$child->{children}}) : 0;
    my $attributes_size = defined($child->{attributes}) ? scalar (@{$child->{attributes}}) : 0;

    if((!defined($child->{value}) || ($child->{value} eq '')) && $children_size == 0 && $attributes_size == 0){
      next;
    }

    if (defined($child->{attributes}) && (scalar @{$child->{attributes}} > 0)){
      my @attrs;
      foreach my $a (@{$child->{attributes}}){
        if(defined($a->{value}) && $a->{value} ne ''){
          $a->{value} = b($a->{value})->decode('UTF-8');
        }
      }
    }

    if($children_size > 0){
      $self->_decode_rec($child, $child->{children});
    }else{
      $child->{value} = b($child->{value})->decode('UTF-8');
    }

  }
}


1;
