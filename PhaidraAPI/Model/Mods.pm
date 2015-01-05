package PhaidraAPI::Model::Mods;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use POSIX qw/strftime/;
use Switch;
use Data::Dumper;
use Mojo::ByteStream qw(b);
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(encode decode slurp);
use XML::Writer;
use XML::LibXML;
use PhaidraAPI::Model::Object;
use PhaidraAPI::Model::Uwmetadata;

sub metadata_tree {

    my ($self, $c, $nocache) = @_;

    my $res = { alerts => [], status => 200 };

	if($nocache){
		$c->app->log->debug("Reading uwmetadata tree from file (nocache request)");

		# read metadata tree from file		
		my $bytes = slurp $c->app->config->{local_mods_tree};
	    unless(defined($bytes)){
	    	push @{$res->{alerts}}, "Error reading local_mods_tree, no content";
	    	$res->{status} = 500;
	    	return $res;
	    }	    
		my $metadata = decode_json($bytes);
		
	 	$res->{metadata_tree} = $metadata->{mods};
	 	
	}else{
		
		$c->app->log->debug("Reading mods tree from cache");

		my $cachekey = 'mods_tree';
	 	my $cacheval = $c->app->chi->get($cachekey);

	  	my $miss = 1;
 
	  	if($cacheval){
	  		if(scalar @{$cacheval->{mods}} > 0){
	  			$miss = 0;
	  			#$c->app->log->debug("[cache hit] $cachekey");
	  		}
	  	}

	    if($miss){
	    	$c->app->log->debug("[cache miss] $cachekey");
			
			# read metadata tree from file		
			my $bytes = slurp $c->app->config->{local_mods_tree};
		    unless(defined($bytes)){
		    	push @{$res->{alerts}}, "Error reading local_mods_tree, no content";
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
	    $res->{metadata_tree} = $cacheval->{mods};				
	}
 	#$c->app->log->debug("XXXXXXXXXXX ".$c->app->dumper($res));
	return $res;
}


1;
__END__
