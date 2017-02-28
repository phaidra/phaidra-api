package PhaidraAPI::Controller::Index;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Mojo::ByteStream qw(b);
use Mojo::JSON qw(encode_json decode_json);
use PhaidraAPI::Model::Index;

sub get {
  my ($self) = @_;

  my $pid = $self->stash('pid');
  
  my $index_model = PhaidraAPI::Model::Index->new;
  my $r = $index_model->get($self, $pid);

  $self->render(json => $r, status => $r->{status});
}

sub update {

  my $self = shift;
  my $pid_param = $self->stash('pid');

  unless(exists($self->app->config->{index_mongodb})){
    $self->render(json => { alerts => [{ type => 'danger', msg => 'The index database is not configured' }]} , status => 400) ;
    return;
  }

  my $username = $self->stash->{basic_auth_credentials}->{username};
  my $password = $self->stash->{basic_auth_credentials}->{password};

  my @pidsarr;
  if(defined($pid_param)){
    push @pidsarr, $pid_param;
  }else{

    my $pids = $self->param('pids');

    unless(defined($pids)){
      $self->render(json => { alerts => [{ type => 'danger', msg => 'No pids sent' }]} , status => 400) ;
      return;
    }

    if(ref $pids eq 'Mojo::Upload'){
      $self->app->log->debug("Pids sent as file param");
      $pids = $pids->asset->slurp;
      $pids = decode_json($pids);
    }else{
      $pids = decode_json(b($pids)->encode('UTF-8'));
    }

    unless(defined($pids->{pids})){
      $self->render(json => { alerts => [{ type => 'danger', msg => 'No pids found' }]} , status => 400) ;
      return;
    }

    @pidsarr = @{$pids->{pids}};
  }
  
  my $index_model = PhaidraAPI::Model::Index->new;
  my $dc_model = PhaidraAPI::Model::Dc->new;
  my $search_model = PhaidraAPI::Model::Search->new;
  my $rel_model = PhaidraAPI::Model::Relationships->new;
  my @res;
  my $pidscount = scalar @pidsarr;
  my $i = 0;
  for my $pid (@pidsarr){

    $i++;
    $self->app->log->info("Processing $pid [$i/$pidscount]");

    eval {

	    my $r = $index_model->update($self, $pid, $dc_model, $search_model, $rel_model);  
	    if($r->{status} eq 200 && $pidscount > 1){      
	      push @res, { pid => $pid, status => 200 };
	    }else{
	      $r->{pid} = $pid;
	      push @res, $r;
	    }
	  };

	  if($@){
      $self->app->log->error("pid $pid Error: $@");         
    }
    
  }
  
  $self->render(json => { results => \@res }, status => 200);
}

1;
