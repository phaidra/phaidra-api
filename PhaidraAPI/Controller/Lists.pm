package PhaidraAPI::Controller::Lists;

use strict;
use warnings;
use v5.10;
use Data::UUID;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::ByteStream qw(b);

use base 'Mojolicious::Controller';

sub get_list {
  my $self = shift;

  my $owner = $self->stash->{basic_auth_credentials}->{username};

  my $lid  = $self->stash('lid');
  my $list = $self->mongo->get_collection('lists')->find_one({"listid" => $lid, "owner" => $owner});

  $self->render(json => {alerts => [], list => $list}, status => 200);
}

sub get_lists {
  my $self = shift;

  my $owner = $self->stash->{basic_auth_credentials}->{username};

  my $cursor = $self->mongo->get_collection('lists')->find({"owner" => $owner})->fields({"listid" => 1, "name" => 1, "updated" => 1, "created" => 1});

  my @lists = ();
  while (my $l = $cursor->next) {
    push @lists, $l;
  }
  $self->render(json => {alerts => [], lists => \@lists}, status => 200);
}

sub add_list {
  my $self = shift;

  my $name  = $self->param('name');
  my $owner = $self->stash->{basic_auth_credentials}->{username};

  my $uuid    = Data::UUID->new;
  my $blid    = $uuid->create();
  my $lid     = $uuid->to_string($blid);
  my @members = ();
  $self->mongo->get_collection('lists')->insert_one(
    { "listid"  => $lid,
      "owner"   => $self->stash->{basic_auth_credentials}->{username},
      "name"    => $name,
      "members" => \@members,
      "created" => time,
      "updated" => time
    }
  );

  $self->render(json => {alerts => [], lid => $lid}, status => 200);
}

sub remove_list {
  my $self = shift;

  my $lid   = $self->stash('lid');
  my $owner = $self->stash->{basic_auth_credentials}->{username};

  $self->mongo->get_collection('lists')->delete_one({"listid" => $lid, "owner" => $owner});

  $self->render(json => {alerts => []}, status => 200);
}

sub add_members {
  my $self = shift;

  my $lid   = $self->stash('lid');
  my $owner = $self->stash->{basic_auth_credentials}->{username};

  my $members = $self->param('members');
  unless (defined($members)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'No members sent'}]}, status => 400);
    return;
  }

  eval {
    if (ref $members eq 'Mojo::Upload') {
      $self->app->log->debug("Members sent as file param");
      $members = $members->asset->slurp;
      $self->app->log->debug("parsing json");
      $members = decode_json($members);
    }
    else {
      $self->app->log->debug("parsing json");
      $members = decode_json(b($members)->encode('UTF-8'));
    }
  };

  my $r;
  for my $m (@{$members->{members}}) {
    $r = $self->mongo->get_collection('lists')->update_one({"listid" => $lid, "owner" => $owner}, {'$push' => {'members' => $m}, '$set' => {"updated" => time}});
  }

  if ($r->{ok}) {
    $self->render(json => {status => 200, alerts => []}, status => 200);
  }
  else {
    $self->render(json => {alerts => [{type => 'danger', msg => $r->{err}}]}, status => 500);
  }
}

sub remove_members {
  my $self = shift;

  my $lid   = $self->stash('lid');
  my $owner = $self->stash->{basic_auth_credentials}->{username};

  my $members = $self->param('members');
  unless (defined($members)) {
    $self->render(json => {alerts => [{type => 'danger', msg => 'No members sent'}]}, status => 400);
    return;
  }

  eval {
    if (ref $members eq 'Mojo::Upload') {
      $self->app->log->debug("Members sent as file param");
      $members = $members->asset->slurp;
      $self->app->log->debug("parsing json");
      $members = decode_json($members);
    }
    else {
      $self->app->log->debug("parsing json");
      $members = decode_json(b($members)->encode('UTF-8'));
    }
  };

  my $r;
  for my $pid (@{$members->{members}}) {
    $r = $self->mongo->get_collection('lists')->update_one({"listid" => $lid, "owner" => $owner}, {'$pull' => {'members' => {pid => $pid}}, '$set' => {"updated" => time}});
  }

  if ($r->{modified_count}) {
    $self->render(json => {status => 200, alerts => []}, status => 200);
  }
  else {
    $self->render(json => {alerts => [{type => 'danger', msg => $r->{err}}]}, status => 500);
  }
}

1;
