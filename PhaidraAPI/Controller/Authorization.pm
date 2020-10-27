package PhaidraAPI::Controller::Authorization;

use strict;
use warnings;
use v5.10;
use Mojo::ByteStream qw(b);
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Authorization;

sub check_rights {

  my $self = shift;

  my $pid = $self->stash('pid');
  my $op  = $self->stash('op');

  my $authz_model = PhaidraAPI::Model::Authorization->new;
  my $res         = $authz_model->check_rights($self, $pid, $op);

  $self->render(json => {status => $res->{status}, alerts => $res->{alerts}}, status => $res->{status});
}

1;
