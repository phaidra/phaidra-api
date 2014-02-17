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
    $self->secrets([$config->{secret}]);
    
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
        },
    });
     
    my $r = $self->routes;
    $r->namespaces(['PhaidraAPI::Controller']);
    
    my $apiauth = $r->bridge->to('authentication#extract_basic_auth_credentials');
	
    $apiauth->route('object/:pid/modify', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('put') ->to('object#modify');
    $apiauth->route('object/:pid', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('delete') ->to('object#delete');
    
    $apiauth->route('object/:pid/uwmetadata', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('get') ->to('uwmetadata#get');
    $apiauth->route('object/:pid/uwmetadata', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('post') ->to('uwmetadata#post');
    
		
	$r->route('uwmetadata/tree')			  ->via('get')   ->to('uwmetadata#tree');
	$r->route('uwmetadata/languages')		  ->via('get')   ->to('uwmetadata#languages');
	
	$r->route('help/tooltip')		  	  ->via('get')   ->to('help#tooltip');		
	
	$r->route('directory/get_org_units')  	->via('get')   ->to('directory#get_org_units');
	$r->route('directory/get_study_plans')  ->via('get')   ->to('directory#get_study_plans');
	$r->route('directory/get_study')  		->via('get')   ->to('directory#get_study');
	$r->route('directory/get_study_name')  	->via('get')   ->to('directory#get_study_name');

	return $self;
}

1;
