package PhaidraAPI::Model::Vocabulary;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use Mojo::ByteStream qw(b);
use Mojo::JSON qw(encode_json decode_json);
use Mojo::File;

sub get_vocabulary {
  my ($self, $c, $uri, $nocache) = @_;

	my %vocab_router = (
  	'http://id.loc.gov/vocabulary/iso639-2' => 'file://'.$c->app->config->{vocabulary_folder}.'/iso639-2.json'
	);

  my $url = $vocab_router{$uri} || $uri; 

  if($url =~ /^(file:\/\/)(.+)/){
    return $self->_get_file_vocabulary($c, $2, $nocache);
  }else{
    return $self->_get_server_vocabulary($c, $url, $nocache);
  }
}

sub _get_file_vocabulary {
  my ($self, $c, $file, $nocache) = @_;

  my $res = { alerts => [], status => 200 };

	if($nocache){
	  $c->app->log->debug("Reading vocabulary file [$file] (nocache request)");

	  # read metadata tree from file
    my $path = Mojo::File->new($file);
	  my $bytes = $path->slurp;
	  unless(defined($bytes)){
	    push @{$res->{alerts}}, "Error reading vocabulary file [$file], no content";
	    $res->{status} = 500;
	    return $res;
	  }
		my $json = decode_json($bytes);

	 	$res->{vocabulary} = $json;

	}else{

		$c->app->log->debug("Reading vocabulary file [$file] from cache");

		my $cachekey = $file;
	 	my $cacheval = $c->app->chi->get($cachekey);

	  my $miss = 1;
	  if($cacheval){
	  		$miss = 0;
	  		#$c->app->log->debug("[cache hit] $cachekey");
	  }

	  if($miss){
	    $c->app->log->debug("[cache miss] $cachekey");

			# read metadata tree from file
      my $path = Mojo::File->new($file);
      my $bytes = $path->slurp;			
		    unless(defined($bytes)){
		    	push @{$res->{alerts}}, "Error reading vocabulary file [$file], no content";
		    	$res->{status} = 500;
	    		return $res;
		    }
			$cacheval = decode_json($bytes);

	    	$c->app->chi->set($cachekey, $cacheval, '1 day');

	  		# save and get the value. the serialization can change integers to strings so
	  		# if we want to get the same structure for cache miss and cache hit we have to run it through
	  		# the cache serialization process even if cache miss [when we already have the structure]
	  		# so instead of using the structure created we will get the one just saved from cache.
	    	$cacheval = $c->app->chi->get($cachekey);
	    	#$c->app->log->debug($c->app->dumper($cacheval));
	  }
    $res->{vocabulary} = $cacheval;
	}

	return $res;
}

sub _get_server_vocabulary {
  # TODO! - sparql to provided url
}

1;
__END__
