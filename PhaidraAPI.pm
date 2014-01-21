package PhaidraAPI;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';
use Mojo::Log;

# This method will run once at server start
sub startup {
    my $self = shift;

    my $config = $self->plugin( 'JSONConfig' => { file => 'PhaidraAPI.json' } );
	$self->config($config);  
	$self->mode($config->{mode});     
    $self->secret($config->{secret});
    
    # init log	
  	$self->log(Mojo::Log->new(path => $config->{log_path}, level => $config->{log_level}));
  	
  	# init cache
  	$self->plugin(CHI => {
	    default => {
	      	driver     => 'File', # FastMmap seems to have problems saving the metadata structure (it won't save anything)
	    	root_dir   => '/tmp/phaidra-api-cache',
	    	cache_size => '20m',
	      	global => 1,
	      	#serializer => 'Storable',
    	},
  	});
  	
  	# init databases
    $self->plugin('database', { 
    	databases => {
        	'db_metadata' => { 
				dsn      => $config->{phaidra_db}->{dsn},
                username => $config->{phaidra_db}->{username},
                password => $config->{phaidra_db}->{password},
            },
            #'db_api' => {
            #    dsn      => $config->{api_db}->{dsn},
            #    username => $config->{api_db}->{username},
            #    password => $config->{api_db}->{password},
            #},
        },
    });
     
    my $r = $self->routes;
    $r->namespaces(['PhaidraAPI::Controller']);
	
	$r->route                            ->via('post')   ->to('objects#create');
	# FIXME o:
    $r->route('/:pid', pid => qr/o:\d+/) ->via('get')    ->to('objects#getobject');    
    $r->route('/:pid', pid => qr/o:\d+/) ->via('put')    ->to('objects#update');
    $r->route('/:pid', pid => qr/o:\d+/) ->via('delete') ->to('objects#delete');

	$r->route('info/metadata_format')     ->via('get')   ->to('info#metadata_format');
	$r->route('info/languages')     	  ->via('get')   ->to('info#languages');      
	$r->route('demo/submitform')          ->via('get')   ->to('demo#submitform');
	$r->route('demo/metadataeditor_full') ->via('get')   ->to('demo#metadataeditor_full');
	$r->route('demo/test_json')           ->via('get')   ->to('demo#test_json');
	
	$r->route('get/metadata')				  ->via('get')   ->to('get#metadata');	

return $self;
}

1;
