package PhaidraAPI::Model::Session::Store::Mongo;

use strict;
use warnings;
use base 'MojoX::Session::Store';
use Mango 0.24;
use Data::Dumper;

__PACKAGE__->attr('mango');
__PACKAGE__->attr('log');

sub create {
  my ($self, $sid, $expires, $data) = @_;

  $expires = $expires * 1000;
  $self->mango->db->collection('session')->update({_id => $sid}, {_id => $sid, expires => Mango::BSON::Time->new($expires), data => $data}, {upsert => 1});

  return 1;
}

sub update {
  shift->create(@_);
}

sub load {
  my ($self, $sid) = @_;

  my $res     = $self->mango->db->collection('session')->find_one({_id => $sid});
  my $expires = $res->{expires} / 1000;

  return ($expires, $res->{data});
}

sub delete {
  my ($self, $sid) = @_;

  my $res = $self->mango->db->collection('session')->remove({_id => $sid});

  return 1;
}

1;

