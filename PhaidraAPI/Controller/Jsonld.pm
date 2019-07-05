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

  if(ref $metadata eq 'Mojo::Upload'){
    $self->app->log->debug("Metadata sent as file param");
    $metadata = $metadata->asset->slurp;
    $metadata = decode_json($metadata);
  }else{
    # http://showmetheco.de/articles/2010/10/how-to-avoid-unicode-pitfalls-in-mojolicious.html
    $metadata = decode_json(b($metadata)->encode('UTF-8'));
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

  my $jsonld_model = PhaidraAPI::Model::Jsonld->new;
  my $res = $jsonld_model->save_to_object($self, $pid, $metadata->{'json-ld'}, $self->stash->{basic_auth_credentials}->{username}, $self->stash->{basic_auth_credentials}->{password});

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

  if(ref $form eq 'Mojo::Upload'){
    $self->app->log->debug("form sent as file param");
    $form = $form->asset->slurp;
    $form = decode_json($form);
  }else{
    $form = decode_json(b($form)->encode('UTF-8'));
  }

  my $ug = Data::UUID->new;
	my $btid = $ug->create();
	my $tid = $ug->to_string($btid);

  $self->mango->db->collection('jsonldtemplates')->insert({ tid => $tid, owner => $self->stash->{basic_auth_credentials}->{username}, name => $name, form => $form, created => time });

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

  my $users_templates = $self->mango->db->collection('jsonldtemplates')->find({"owner" => $self->stash->{basic_auth_credentials}->{username}})->sort({ "created" => -1});
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
