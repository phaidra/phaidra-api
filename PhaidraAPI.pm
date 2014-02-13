package PhaidraAPI;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';
use Mojo::Log;
use Mojolicious::Plugin::I18N;
use Mojolicious::Plugin::Authentication;
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
    
    # init auth
    $self->plugin(authentication => {
		load_user => sub {
			my $self = shift;
			my $username  = shift;
			return $self->directory->get_login_data($self, $username);
		},
		validate_user => sub {
			my ($self, $username, $password, $extradata) = @_;
			return $self->directory->authenticate($config, $username, $password, $extradata);
		},
	});
    
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
    
    my $auth = $r->bridge->to('authentication#check');
    my $apiauth = $r->bridge->to('authentication#extract_basic_auth_credentials');
	
    $r->route('object/:pid/modify', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('put') ->to('object#modify');
    $r->route('object/:pid', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('delete') ->to('object#delete');
    
    $apiauth->route('object/:pid/uwmetadata', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('get') ->to('uwmetadata#get');
    $apiauth->route('object/:pid/uwmetadata', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('post') ->to('uwmetadata#post');
    	  
	# if not authenticated, users will be redirected to login page
	$auth->route('demo/submitform')          ->via('get')   ->to('demo#submitform');
	$r->route('uwmetadataeditor_full') ->via('get')   ->to('demo#uwmetadataeditor_full');
	#$auth->route('uwmetadataeditor_full') ->via('get')   ->to('demo#uwmetadataeditor_full');
	$r->route('demo/test_json')           ->via('get')   ->to('demo#test_json');
	$r->route('portal') 			  ->via('get')   ->to('demo#portal');
	$r->route('login') 			  ->via('get')   ->to('authentication#login');
	$r->route('loginform') 			  ->via('get')   ->to('authentication#loginform');
		
	#$apiauth->route('uwmetadata/')			      ->via('get')   ->to('uwmetadata#get');
	#$apiauth->route('uwmetadata/')			      ->via('post')  ->to('uwmetadata#post');
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
