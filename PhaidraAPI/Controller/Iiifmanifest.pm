package PhaidraAPI::Controller::Iiifmanifest;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use PhaidraAPI::Model::Iiifmanifest;

sub update_manifest_metadata {
  my $self = shift;

  my $res = {alerts => [], status => 200};

  my $pid = $self->stash('pid');

  my $iiifm_model = PhaidraAPI::Model::Iiifmanifest->new;
  my $r           = $iiifm_model->update_manifest_metadata($self, $pid);
  if ($r->{status} ne 200) {

    # just log but don't change status, this isn't fatal
    push @{$res->{alerts}}, {type => 'danger', msg => 'Error updating IIIF-MANIFEST metadata'};
    push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
  }

  $self->render(json => $res, status => $res->{status});
}

1;
