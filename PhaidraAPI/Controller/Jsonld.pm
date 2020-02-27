package PhaidraAPI::Controller::Jsonld;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::ByteStream qw(b);
use Mojo::JSON qw(encode_json decode_json);
use PhaidraAPI::Model::Jsonld;
use PhaidraAPI::Model::Util;
use Time::HiRes qw/tv_interval gettimeofday/;
use Data::UUID;

sub get {
  my $self = shift;

  my $pid = $self->stash('pid');

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  my $object_model = PhaidraAPI::Model::Object->new;
  $object_model->proxy_datastream($self, $pid, 'JSON-LD', undef, undef, 1);
  return;
}

sub post {
  my $self = shift;

  my $t0 = [gettimeofday];

  my $pid = $self->stash('pid');

  my $metadata = $self->param('metadata');
  unless(defined($metadata)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata sent' }]} , status => 400) ;
    return;
  }

  eval {
    if(ref $metadata eq 'Mojo::Upload'){
      $self->app->log->debug("Metadata sent as file param");
      $metadata = $metadata->asset->slurp;
      $self->app->log->debug("parsing json");
      $metadata = decode_json($metadata);
    }else{
      # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
      $self->app->log->debug("parsing json");
      $metadata = decode_json(b($metadata)->encode('UTF-8'));
    }
  };

  if($@){
    $self->app->log->error("Error: $@");
    $self->render(json => { alerts => [{ type => 'danger', msg => $@ }]} , status => 400);
    return;
  }

  unless(defined($metadata->{metadata})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No metadata found' }]} , status => 400) ;
    return;
  }
  $metadata = $metadata->{metadata};

  unless(defined($pid)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined pid' }]} , status => 400) ;
    return;
  }

  unless(defined($metadata->{'json-ld'})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No JSON-LD sent' }]} , status => 400) ;
    return;
  }

  my $cmodel;
  my $search_model = PhaidraAPI::Model::Search->new;
  my $res_cmodel = $search_model->get_cmodel($self, $pid);
  if($res_cmodel->{status} ne 200){
    my $err = "ERROR saving json-ld for object $pid, could not get cmodel:".$self->app->dumper($res_cmodel);
    $self->app->log->error($err);
    $self->render(json => { alerts => [{ type => 'danger', msg => $err }]} , status => 500) ;
    return;
  }else{
    $cmodel = $res_cmodel->{cmodel};
  }

  my $jsonld_model = PhaidraAPI::Model::Jsonld->new;
  my $res = $jsonld_model->save_to_object($self, $pid, $cmodel, $metadata->{'json-ld'}, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

  my $t1 = tv_interval($t0);
  if($res->{status} eq 200){
    unshift @{$res->{alerts}}, { type => 'success', msg => "JSON-LD for $pid saved successfully ($t1 s)"};
  }

  $self->render(json => { alerts => $res->{alerts} } , status => $res->{status});
}

sub add_template {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $name = $self->param('name');
  unless(defined($name)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No name sent' }]} , status => 400) ;
    return;
  }

  my $form = $self->param('form');
  unless(defined($form)){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'No form sent' }]} , status => 400) ;
    return;
  }

  my $tag = $self->param('tag');

  eval {
    if(ref $form eq 'Mojo::Upload'){
      $self->app->log->debug("form sent as file param");
      $form = $form->asset->slurp;
      $form = decode_json($form);
    }else{
      $form = decode_json(b($form)->encode('UTF-8'));
    }
  };

  if($@){
    $self->app->log->error("Error: $@");
    unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
    $res->{status} = 400;
    $self->render(json => $res , status => $res->{status});
    return;
  }

  my $ug = Data::UUID->new;
  my $btid = $ug->create();
  my $tid = $ug->to_string($btid);

  $self->mango->db->collection('jsonldtemplates')->insert({ tid => $tid, owner => $self->stash->{basic_auth_credentials}->{username}, name => $name, form => $form, tag => $tag, created => time });

  $res->{tid} = $tid;

  $self->render(json => $res , status => $res->{status});
}

sub get_template {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  unless(defined($self->stash('tid'))){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined template id' }]} , status => 400) ;
    return;
  }
  $self->app->log->debug($self->stash('tid')." ".$self->stash->{basic_auth_credentials}->{username});
  my $tres = $self->mango->db->collection('jsonldtemplates')->find({tid => $self->stash('tid'), owner => $self->stash->{basic_auth_credentials}->{username}})->next;

  $res->{template} = $tres;

  $self->render(json => $res, status => $res->{status});
}

sub get_users_templates {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  my $tag = $self->param('tag');

  my $find = {'owner' => $self->stash->{basic_auth_credentials}->{username}};
  if ($tag) {
    $find->{'tag'} = $tag;
  }

  my $users_templates = $self->mango->db->collection('jsonldtemplates')->find($find)->sort({ 'created' => -1});
  my @tmplts = ();
  while (my $doc = $users_templates->next) {
      push @tmplts, { tid => $doc->{tid}, name => $doc->{name}, created => $doc->{created}};
  }

  $res->{templates} = \@tmplts;

  $self->render(json => $res, status => $res->{status});
}

sub remove_template {
  my $self = shift;

  my $res = { alerts => [], status => 200 };

  unless(defined($self->stash('tid'))){
		$self->render(json => { alerts => [{ type => 'danger', msg => 'Undefined template id' }]} , status => 400) ;
		return;
	}

  $self->mango->db->collection('jsonldtemplates')->remove({ tid => $self->stash('tid'), owner => $self->stash->{basic_auth_credentials}->{username} }); 

  $self->render(json => $res , status => $res->{status});
}

1;
