package PhaidraAPI::Model::Hooks;

use strict;
use warnings;
use v5.10;
use utf8;
use base qw/Mojo::Base/;
use Mojo::ByteStream qw(b);
use PhaidraAPI::Model::Dc;
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Search;
use PhaidraAPI::Model::Index;

sub add_or_modify_datastream_hooks {

  my ($self, $c, $pid, $dsid, $dscontent, $username, $password) = @_;

  my $res = {alerts => [], status => 200};

  if (exists($c->app->config->{hooks})) {
    if (exists($c->app->config->{hooks}->{updatedc}) && $c->app->config->{hooks}->{updatedc}) {
      if ($dsid eq "UWMETADATA") {
        my $dc_model = PhaidraAPI::Model::Dc->new;
        $res = $dc_model->generate_dc_from_uwmetadata($c, $pid, $dscontent, $username, $password);
      }
      elsif ($dsid eq "MODS") {
        my $dc_model = PhaidraAPI::Model::Dc->new;
        $res = $dc_model->generate_dc_from_mods($c, $pid, $dscontent, $username, $password);
      }
    }
  }

  if (exists($c->app->config->{hooks})) {
    if (exists($c->app->config->{hooks}->{updateindex}) && $c->app->config->{hooks}->{updateindex}) {
      my $dc_model     = PhaidraAPI::Model::Dc->new;
      my $search_model = PhaidraAPI::Model::Search->new;
      my $index_model  = PhaidraAPI::Model::Index->new;
      my $object_model = PhaidraAPI::Model::Object->new;
      my $r            = $index_model->update($c, $pid, $dc_model, $search_model, $object_model);
      if ($r->{status} ne 200) {

        # just log but don't change status, this isn't fatal
        push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      }
    }
  }

  return $res;
}

sub add_or_modify_relationships_hooks {

  my ($self, $c, $pid, $username, $password) = @_;

  my $res = {alerts => [], status => 200};

  my $dc_model     = PhaidraAPI::Model::Dc->new;
  my $search_model = PhaidraAPI::Model::Search->new;

  my $object_model = PhaidraAPI::Model::Object->new;

  if (exists($c->app->config->{hooks})) {
    if (exists($c->app->config->{hooks}->{updatedc}) && $c->app->config->{hooks}->{updatedc}) {

      my $r = $search_model->datastreams_hash($c, $pid);
      if ($r->{status} ne 200) {
        return $r;
      }

      if (exists($r->{dshash}->{'UWMETADATA'})) {
        $res = $object_model->get_datastream($c, $pid, 'UWMETADATA', $username, $password);
        if ($res->{status} ne 200) {
          return $res;
        }
        $res->{UWMETADATA} = b($res->{UWMETADATA})->decode('UTF-8');
        return $dc_model->generate_dc_from_uwmetadata($c, $pid, $res->{UWMETADATA}, $username, $password);
      }

      if (exists($r->{dshash}->{'MODS'})) {
        $res = $object_model->get_datastream($c, $pid, 'MODS', $username, $password);
        if ($res->{status} ne 200) {
          return $res;
        }
        $res->{MODS} = b($res->{MODS})->decode('UTF-8');
        return $dc_model->generate_dc_from_mods($c, $pid, $res->{MODS}, $username, $password);
      }
    }
  }

  if (exists($c->app->config->{hooks})) {
    if (exists($c->app->config->{hooks}->{updateindex}) && $c->app->config->{hooks}->{updateindex}) {
      my $index_model = PhaidraAPI::Model::Index->new;
      my $r           = $index_model->update($c, $pid, $dc_model, $search_model, $object_model);
      if ($r->{status} ne 200) {

        # just log but don't change status, this isn't fatal
        push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      }
    }
  }

  return $res;
}

sub modify_object_hooks {

  my ($self, $c, $pid, $username, $password) = @_;

  my $res = {alerts => [], status => 200};

  if (exists($c->app->config->{hooks})) {
    if (exists($c->app->config->{hooks}->{updateindex}) && $c->app->config->{hooks}->{updateindex}) {
      my $dc_model     = PhaidraAPI::Model::Dc->new;
      my $search_model = PhaidraAPI::Model::Search->new;
      my $index_model  = PhaidraAPI::Model::Index->new;
      my $object_model = PhaidraAPI::Model::Object->new;
      my $r            = $index_model->update($c, $pid, $dc_model, $search_model, $object_model);
      if ($r->{status} ne 200) {

        # just log but don't change status, this isn't fatal
        push @{$res->{alerts}}, @{$r->{alerts}} if scalar @{$r->{alerts}} > 0;
      }
    }
  }

  return $res;
}

1;
__END__
