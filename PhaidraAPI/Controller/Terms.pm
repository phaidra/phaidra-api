package PhaidraAPI::Controller::Terms;

use strict;
use warnings;
use v5.10;
use PhaidraAPI::Model::Terms;
use base 'Mojolicious::Controller';

sub label {
  my $self = shift;

  my $terms_model = PhaidraAPI::Model::Terms->new;
  my $res         = $terms_model->label($self, $self->param('uri'));

  $self->render(json => $res, status => $res->{status});
}

sub children {
  my $self = shift;

  my $terms_model = PhaidraAPI::Model::Terms->new;
  my $res         = $terms_model->children($self, $self->param('uri'));

  $self->render(json => $res, status => $res->{status});
}

sub parent {
  my $self = shift;

  my $terms_model = PhaidraAPI::Model::Terms->new;
  my $res         = $terms_model->parent($self, $self->param('uri'));

  $self->render(json => $res, status => $res->{status});
}

sub taxonpath {
  my $self = shift;

  my $terms_model = PhaidraAPI::Model::Terms->new;
  my $res         = $terms_model->taxonpath($self, $self->param('uri'));

  $self->render(json => $res, status => $res->{status});
}

sub search {
  my $self = shift;

  my $terms_model = PhaidraAPI::Model::Terms->new;
  my $res         = $terms_model->search($self, $self->param('q'));

  $self->render(json => $res, status => $res->{status});
}

1;
