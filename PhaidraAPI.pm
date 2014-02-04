package PhaidraAPI;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';
use Mojo::Log;
use Mojolicious::Plugin::I18N;
use Mojo::Loader;
use lib "lib/phaidra_directory";
use lib "lib/phaidra_binding";

# This method will run once at server start
sub startup {
    my $self = shift;

    my $config = $self->plugin( 'JSONConfig' => { file => 'PhaidraAPI.json' } );
	$self->config($config);  
	$self->mode($config->{mode});     
    $self->secret($config->{secret});
    
    # init log	
  	$self->log(Mojo::Log->new(path => $config->{log_path}, level => $config->{log_level}));

	my $directory_impl = $config->{directory_class};
	my $e = Mojo::Loader->new->load($directory_impl);    
    my $directory = $directory_impl->new($self, $config);
 
    $self->helper( directory => sub { return $directory; } );
    
  	# init I18N
  	$self->plugin(charset => {charset => 'utf8'});
  	$self->plugin(I18N => {namespace => 'PhaidraAPI::I18N', support_url_langs => [qw(en de it sr)]});
  	
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
	
	#$r->route                            ->via('post')   ->to('objects#create');
	# FIXME o:
    #$r->route('/:pid', pid => qr/o:\d+/) ->via('get')    ->to('objects#getobject');    
    #$r->route('/:pid', pid => qr/o:\d+/) ->via('put')    ->to('objects#update');
    #$r->route('/:pid', pid => qr/o:\d+/) ->via('delete') ->to('objects#delete');
	  
	$r->route('demo/submitform')          ->via('get')   ->to('demo#submitform');
	$r->route('demo/metadataeditor_full') ->via('get')   ->to('demo#metadataeditor_full');
	$r->route('demo/test_json')           ->via('get')   ->to('demo#test_json');
		
	$r->route('metadata/')			      ->via('get')   ->to('metadata#get');
	$r->route('metadata/')			      ->via('post')  ->to('metadata#post');
	$r->route('metadata/tree')			  ->via('get')   ->to('metadata#tree');
	$r->route('metadata/languages')		  ->via('get')   ->to('metadata#languages');
	
	$r->route('help/tooltip')		  	  ->via('get')   ->to('help#tooltip');		
	
	$r->route('directory/get_org_units')  ->via('get')   ->to('directory#get_org_units');
	$r->route('directory/get_study_plans')  ->via('get')   ->to('directory#get_study_plans');
	$r->route('directory/get_study')  ->via('get')   ->to('directory#get_study');

return $self;
}

1;
