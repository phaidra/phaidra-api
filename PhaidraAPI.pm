package PhaidraAPI;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';
use Mojo::Log;
use Mojolicious::Plugin::I18N;
use Mojolicious::Plugin::Session;
use Mojo::Loader;
use lib "lib/phaidra_directory";
use lib "lib/phaidra_binding";
use Mango 0.24;
use Sereal::Encoder qw(encode_sereal);
use Sereal::Decoder qw(decode_sereal);
use Crypt::CBC              ();
use Crypt::Rijndael         ();
use Crypt::URandom          (qw/urandom/);
use Digest::SHA             (qw/hmac_sha256/);
use Math::Random::ISAAC::XS ();
use MIME::Base64 3.12 (qw/encode_base64url decode_base64url/);
use PhaidraAPI::Model::Session::Transport::Header;
use PhaidraAPI::Model::Session::Store::Mongo;

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
	      	driver     => 'Memory',
	    	#driver     => 'File', # FastMmap seems to have problems saving the metadata structure (it won't save anything)
	    	#root_dir   => '/tmp/phaidra-api-cache',
	    	#cache_size => '20m',
	      	global => 1,
	      	#serializer => 'Storable',
    	},
  	});
  	
  	# init databases
  	my %databases;
  	$databases{'db_metadata'} = { 
				dsn      => $config->{phaidra_db}->{dsn},
                username => $config->{phaidra_db}->{username},
                password => $config->{phaidra_db}->{password},
    };

	if($config->{phaidra}->{triplestore} eq 'localMysqlMPTTriplestore'){
		$databases{'db_triplestore'} = { 
				dsn      => $config->{localMysqlMPTTriplestore}->{dsn},
                username => $config->{localMysqlMPTTriplestore}->{username},
                password => $config->{localMysqlMPTTriplestore}->{password},
    	};
	}           

    $self->plugin('database', { databases => \%databases } );
	
	$self->helper(mango => sub { state $mango = Mango->new('mongodb://'.$config->{mongodb}->{username}.':'.$config->{mongodb}->{password}.'@'.$config->{mongodb}->{host}.'/'.$config->{mongodb}->{database}) });
	
    # we might possibly save a lot of data to session 
    # so we are not going to use cookies, but a database instead
    $self->plugin(
        session => {
            stash_key     => 'mojox-session',
	    	store  => PhaidraAPI::Model::Session::Store::Mongo->new( 
	    		mango => $self->mango, 
	    		'log' => $self->log 
	    	),              
	    	transport => PhaidraAPI::Model::Session::Transport::Header->new(
	    		name => $config->{authentication}->{token_header},
	    		'log' => $self->log 
	    		),
            expires_delta => $config->{session_expiration}, 
	    	ip_match      => 1
        }
    );
    
    $self->hook('before_dispatch' => sub {
		my $self = shift;		  
		
		my $session = $self->stash('mojox-session');
		$session->load;
		if($session->sid){
			$session->extend_expires;
			$session->flush;			
		}      	
	});
	
	$self->hook('after_dispatch' => sub {
		my $self = shift;		  
		my $json = $self->res->json;
		if($json){
			if($json->{alerts}){
				if(scalar(@{$json->{alerts}}) > 0){
					$self->app->log->debug("Alerts:\n".$self->dumper($json->{alerts}));
				}	
			}	
		}
		
		# CORS
		if($self->req->headers->header('Origin')){
			$self->res->headers->add('Access-Control-Allow-Origin' => $self->req->headers->header('Origin'));	
		}else{
			$self->res->headers->add('Access-Control-Allow-Origin' => $config->{authentication}->{'Access-Control-Allow-Origin'});
		}
		$self->res->headers->add('Access-Control-Allow-Credentials' => 'true');
		$self->res->headers->add('Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS');
		$self->res->headers->add('Access-Control-Allow-Headers' => 'Content-Type, '.$config->{authentication}->{token_header});				     	
	});
     
    $self->helper(save_cred => sub {
    	my $self = shift;
		my $u = shift;
		my $p = shift;
		
		my $ciphertext;
		
		my $session = $self->stash('mojox-session');
		$session->load;
		unless($session->sid){		
			$session->create;		
		}	
		my $ba = encode_sereal({ username => $u, password => $p });  	
	    my $salt = Math::Random::ISAAC::XS->new( map { unpack( "N", urandom(4) ) } 1 .. 256 )->irand();
	    my $key = hmac_sha256( $salt, $self->app->config->{enc_key} );
	    my $cbc = Crypt::CBC->new( -key => $key, -cipher => 'Rijndael' );
	    
	    eval {
	        $ciphertext = encode_base64url( $cbc->encrypt( $ba ) );      
	    };
	    $self->app->log->error("Encoding error: $@") if $@;
		$session->data(cred => $ciphertext, salt => $salt);
    });
    
    $self->helper(load_cred => sub {
    	my $self = shift;
    	
    	my $session = $self->stash('mojox-session');
		$session->load;
		unless($session->sid){
			return undef;
		}
		
		my $salt = $session->data('salt');
		my $ciphertext = $session->data('cred');		
	    my $key = hmac_sha256( $salt, $self->app->config->{enc_key} );	
	    my $cbc = Crypt::CBC->new( -key => $key, -cipher => 'Rijndael' );
	    my $data;
	    eval {  
	    	$data = decode_sereal($cbc->decrypt( decode_base64url($ciphertext) ))	    	
	   	};
	    $self->app->log->error("Decoding error: $@") if $@;
	
	    return $data;
    });	 
     
    my $r = $self->routes;
    $r->namespaces(['PhaidraAPI::Controller']);
    		
	$r->route('uwmetadata/tree')			  ->via('get')   ->to('uwmetadata#tree');
	$r->route('uwmetadata/languages')		  ->via('get')   ->to('uwmetadata#languages');
       $r->route('uwmetadata/json2xml')                  ->via('post')  ->to('uwmetadata#json2xml');
       $r->route('uwmetadata/xml2json')                  ->via('post')  ->to('uwmetadata#xml2json');
	
	$r->route('help/tooltip')		  	  ->via('get')   ->to('help#tooltip');		
	
	$r->route('directory/get_org_units')  	->via('get')   ->to('directory#get_org_units');
	$r->route('directory/get_study')  		->via('get')   ->to('directory#get_study');
	$r->route('directory/get_study_name')  	->via('get')   ->to('directory#get_study_name');
	
	$r->route('search/owner/:username')  ->via('get')   ->to('search#owner');
	$r->route('search/collections/owner/:username')  ->via('get')   ->to('search#collections_owner');
	$r->route('search/triples')  ->via('get')   ->to('search#triples');
	$r->route('search')  ->via('get')   ->to('search#search');

	# CORS
	$r->any('*')->via('OPTIONS')->to('authentication#cors_preflight');
	
	$r->route('signin') 			  	->via('get')   ->to('authentication#signin');
    $r->route('signout') 			->via('get')   ->to('authentication#signout');   
    $r->route('keepalive') 			->via('get')   ->to('authentication#keepalive');   

	my $apiauth = $r->bridge->to('authentication#extract_credentials');
    
    unless($self->app->config->{readonly}){
    	$apiauth->route('object/:pid/modify', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('put') ->to('object#modify');
	$apiauth->route('object/:pid', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('delete') ->to('object#delete');
	$apiauth->route('object/:pid/uwmetadata', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('post') ->to('uwmetadata#post');
	$apiauth->route('collection/create') ->via('post') ->to('collection#create');
	$apiauth->route('collection/:pid/members') ->via('delete') ->to('collection#remove_collection_members');
        $apiauth->route('collection/:pid/members') ->via('post') ->to('collection#add_collection_members');
        $apiauth->route('collection/:pid/members') ->via('put') ->to('collection#set_collection_members');
        $apiauth->route('collection/:pid/members/order') ->via('post') ->to('collection#order_collection_members');
        $apiauth->route('collection/:pid/members/:itempid/order/:position') ->via('post') ->to('collection#order_collection_member');
    }
    
    if($self->app->config->{allow_userdata_queries}){
    	$apiauth->route('directory/get_user_data')  	->via('get')   ->to('directory#get_user_data');
   		$apiauth->route('directory/get_name')  	->via('get')   ->to('directory#get_name');
   		$apiauth->route('directory/get_email')  	->via('get')   ->to('directory#get_email');
    }

    $apiauth->route('object/:pid/uwmetadata', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('get') ->to('uwmetadata#get');
    
    # does not show inactive objects, not specific to collection (but does ordering)
    $apiauth->route('object/:pid/related', pid => qr/[a-zA-Z\-]+:[0-9]+/) ->via('get') ->to('search#related');
    
    $apiauth->route('collection/:pid/members') ->via('get') ->to('collection#get_collection_members');

	return $self;
}

1;
