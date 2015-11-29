package PhaidraAPI;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';
use Mojo::Log;
use Mojolicious::Plugin::I18N;
use Mojolicious::Plugin::Session;
use Mojo::Loader qw(load_class);
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

BEGIN
{
  # that's what we want:
  # use MIME::Base64 3.12 (qw/encode_base64url decode_base64url/);

  # but you don't always get what you want, so:
  use MIME::Base64 (qw/encode_base64 decode_base64/);

  sub encode_base64url {
    my $e = encode_base64(shift, "");
    $e =~ s/=+\z//;
    $e =~ tr[+/][-_];
    return $e;
  }

  sub decode_base64url {
    my $s = shift;
    $s =~ tr[-_][+/];
    $s .= '=' while length($s) % 4;
    return decode_base64($s);
  }
}

use PhaidraAPI::Model::Session::Transport::Header;
use PhaidraAPI::Model::Session::Store::Mongo;

$ENV{MOJO_MAX_MESSAGE_SIZE} = 20737418240;
$ENV{MOJO_INACTIVITY_TIMEOUT} = 600;
$ENV{MOJO_HEARTBEAT_TIMEOUT} = 600;
$ENV{MOJO_TMPDIR} = '/usr/local/fedora/server/management/upload';

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
	my $e = load_class $directory_impl;
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
                options  => { mysql_auto_reconnect => 1}
    };

	if($config->{phaidra}->{triplestore} eq 'localMysqlMPTTriplestore'){
		$databases{'db_triplestore'} = {
				dsn      => $config->{localMysqlMPTTriplestore}->{dsn},
                username => $config->{localMysqlMPTTriplestore}->{username},
                password => $config->{localMysqlMPTTriplestore}->{password},
                options  => { mysql_auto_reconnect => 1}
    	};
	}

  if(exists($config->{frontends})){
    for my $f (@{$config->{frontends}}){
      if(exists($f->{stats})){
        if($f->{stats}->{type} eq 'piwik'){
          $databases{'db_stats_'.$f->{frontend_id}} = {
            dsn      => $f->{stats}->{db_piwik}->{dsn},
            username => $f->{stats}->{db_piwik}->{username},
            password => $f->{stats}->{db_piwik}->{password},
            options  => { mysql_auto_reconnect => 1}
          };
        }   
      }
    }  
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
      if (ref $json eq ref {}) { # only if json is really a hash
  			if($json->{alerts}){
  				if(scalar(@{$json->{alerts}}) > 0){
  					$self->app->log->debug("Alerts:\n".$self->dumper($json->{alerts}));
  				}
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
    # X-Prototype-Version, X-Requested-With - comes from prototype's Ajax.Updater
		$self->res->headers->add('Access-Control-Allow-Headers' => 'Content-Type, X-Prototype-Version, X-Requested-With, '.$config->{authentication}->{token_header});
    # comes from prototype's Ajax.Updater
    $self->res->headers->add('Access-Control-Expose-Headers' => 'x-json');
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

    # PUT vs POST in this API: PUT should be idempotent

  $r->route('languages')                          ->via('get')    ->to('languages#get_languages');
  $r->route('licenses')                           ->via('get')    ->to('licenses#get_licenses');

	$r->route('uwmetadata/tree')                    ->via('get')    ->to('uwmetadata#tree');
  $r->route('uwmetadata/json2xml')                ->via('post')   ->to('uwmetadata#json2xml');
  $r->route('uwmetadata/xml2json')                ->via('post')   ->to('uwmetadata#xml2json');
  $r->route('uwmetadata/validate')                ->via('post')   ->to('uwmetadata#validate');
  $r->route('uwmetadata/json2xml_validate')       ->via('post')   ->to('uwmetadata#json2xml_validate');
  $r->route('uwmetadata/compress')                ->via('post')   ->to('uwmetadata#compress');

  $r->route('mods/tree')                          ->via('get')    ->to('mods#tree');
  $r->route('mods/json2xml')                      ->via('post')   ->to('mods#json2xml');
  $r->route('mods/xml2json')                      ->via('post')   ->to('mods#xml2json');
  $r->route('mods/validate')                      ->via('post')   ->to('mods#validate');
  $r->route('mods/json2xml_validate')             ->via('post')   ->to('mods#json2xml_validate');

  $r->route('rights/json2xml')                    ->via('post')   ->to('rights#json2xml');
  $r->route('rights/xml2json')                    ->via('post')   ->to('rights#xml2json');
  $r->route('rights/validate')                    ->via('post')   ->to('rights#validate');
  $r->route('rights/json2xml_validate')           ->via('post')   ->to('rights#json2xml_validate');

  $r->route('geo/json2xml')                       ->via('post')   ->to('geo#json2xml');
  $r->route('geo/xml2json')                       ->via('post')   ->to('geo#xml2json');
  $r->route('geo/validate')                       ->via('post')   ->to('geo#validate');
  $r->route('geo/json2xml_validate')              ->via('post')   ->to('geo#json2xml_validate');

	$r->route('help/tooltip')                       ->via('get')    ->to('help#tooltip');

	$r->route('directory/get_org_units')            ->via('get')    ->to('directory#get_org_units');
  $r->route('directory/get_parent_org_unit_id')   ->via('get')    ->to('directory#get_parent_org_unit_id');
	$r->route('directory/get_study')                ->via('get')    ->to('directory#get_study');
	$r->route('directory/get_study_name')           ->via('get')    ->to('directory#get_study_name');

	$r->route('search/owner/:username')             ->via('get')    ->to('search#owner');
	$r->route('search/collections/owner/:username') ->via('get')    ->to('search#collections_owner');
	$r->route('search/triples')                     ->via('get')    ->to('search#triples');  
	$r->route('search')                             ->via('get')    ->to('search#search');  
  # lucene query can be long -> post
  $r->route('search/lucene')                      ->via('post')   ->to('search#search_lucene');

  $r->route('utils/get_all_pids')                 ->via('get')    ->to('utils#get_all_pids');

	$r->route('terms/label')                   		  ->via('get')    ->to('terms#label');
	$r->route('terms/children')                	    ->via('get')    ->to('terms#children');
	$r->route('terms/search')                       ->via('get')    ->to('terms#search');
	$r->route('terms/taxonpath')                    ->via('get')    ->to('terms#taxonpath');
	$r->route('terms/parent')                       ->via('get')    ->to('terms#parent');

	# CORS
	$r->any('*')                                    ->via('options')->to('authentication#cors_preflight');

	$r->route('signin')                             ->via('get')    ->to('authentication#signin');
  $r->route('signout')                            ->via('get')    ->to('authentication#signout');
  $r->route('keepalive')                          ->via('get')    ->to('authentication#keepalive');

	$r->route('collection/:pid/members')            ->via('get')    ->to('collection#get_collection_members');
	# does not show inactive objects, not specific to collection (but does ordering)
  $r->route('object/:pid/related')                ->via('get')    ->to('search#related');

  # we will get this datastreams by using intcall credentials
  # (instead of defining a API-A disseminator for each of them)
  $r->route('object/:pid/uwmetadata')             ->via('get')    ->to('uwmetadata#get');
  $r->route('object/:pid/mods')                   ->via('get')    ->to('mods#get');
  $r->route('object/:pid/rights')                 ->via('get')    ->to('rights#get');
  $r->route('object/:pid/geo')                    ->via('get')    ->to('geo#get');
  $r->route('object/:pid/techinfo')               ->via('get')    ->to('techinfo#get');
  # these two are XML  
  $r->route('object/:pid/dc')                     ->via('get')    ->to('dc#get', dsid => 'DC_P');
  $r->route('object/:pid/oai_dc')                 ->via('get')    ->to('dc#get', dsid => 'DC_OAI');

  $r->route('stats/:pid')                         ->via('get')    ->to('stats#stats');
  $r->route('stats/:pid/downloads')               ->via('get')    ->to('stats#stats', stats_param_key => 'downloads');
  $r->route('stats/:pid/detail_page')             ->via('get')    ->to('stats#stats', stats_param_key => 'detail_page');

  # this just extracts the credentials - authentication will be done by fedora
	my $apiauth = $r->under('/')->to('authentication#extract_credentials');

  # we authenticate the user, because we are not going to call fedora
  my $check_auth = $apiauth->under('/')->to('authentication#authenticate');

	if($self->app->config->{allow_userdata_queries}){
  	$check_auth->route('directory/user/:username/data')                    ->via('get')      ->to('directory#get_user_data');
		$check_auth->route('directory/user/:username/name')                    ->via('get')      ->to('directory#get_user_name');
 		$check_auth->route('directory/user/:username/email')                   ->via('get')      ->to('directory#get_user_email');
    $check_auth->route('directory/user/search')                            ->via('get')      ->to('directory#search_user');
  }

  $apiauth->route('my/objects')                                         ->via('get')      ->to('search#my_objects');

  unless($self->app->config->{readonly}){

    $check_auth->route('utils/:pid/update_dc')                          ->via('get')      ->to('utils#update_dc');
    $check_auth->route('utils/update_dc')                               ->via('post')     ->to('utils#update_dc');

    $apiauth->route('object/:pid/octets')                               ->via('get')      ->to('octets#get');

    $apiauth->route('object/:pid/modify')                               ->via('post')     ->to('object#modify');
    $apiauth->route('object/:pid')                                      ->via('delete')   ->to('object#delete');
    $apiauth->route('object/:pid/uwmetadata')                           ->via('post')     ->to('uwmetadata#post');
    $apiauth->route('object/:pid/mods')                                 ->via('post')     ->to('mods#post');
    $apiauth->route('object/:pid/geo')                                  ->via('post')     ->to('geo#post');
    $apiauth->route('object/:pid/rights')                               ->via('post')     ->to('rights#post');
    $apiauth->route('object/:pid/metadata')                             ->via('post')     ->to('object#metadata');
    $apiauth->route('object/create')                                    ->via('post')     ->to('object#create_empty');
    $apiauth->route('object/create/:cmodel')                            ->via('post')     ->to('object#create');
    $apiauth->route('object/:pid/relationship/add')                     ->via('post')     ->to('object#add_relationship');
    $apiauth->route('object/:pid/relationship/remove')                  ->via('post')     ->to('object#purge_relationship');
    $apiauth->route('object/:pid/datastream/:dsid')                     ->via('post')     ->to('object#add_or_modify_datastream');
    $apiauth->route('object/:pid/data')                                 ->via('post')     ->to('object#add_octets');
    $apiauth->route('picture/create')                                   ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:Picture');
    $apiauth->route('document/create')                                  ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:PDFDocument');
    $apiauth->route('video/create')                                     ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:Video');
    $apiauth->route('audio/create')                                     ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:Audio');

    $apiauth->route('collection/create')                                ->via('post')     ->to('collection#create');
    $apiauth->route('collection/:pid/members/remove')                   ->via('post')     ->to('collection#remove_collection_members');
    $apiauth->route('collection/:pid/members/add')                      ->via('post')     ->to('collection#add_collection_members');
    $apiauth->route('collection/:pid/members/order')                    ->via('post')     ->to('collection#order_collection_members');
    $apiauth->route('collection/:pid/members/:itempid/order/:position') ->via('post')     ->to('collection#order_collection_member');

    $check_auth->route('groups')                                        ->via('get')      ->to('groups#get_users_groups');
    $check_auth->route('group/:gid')                                    ->via('get')      ->to('groups#get_group');
    $check_auth->route('group/add')                                     ->via('post')     ->to('groups#add_group');
    $check_auth->route('group/:gid/remove')                             ->via('post')     ->to('groups#remove_group');
    $check_auth->route('group/:gid/members/add')                        ->via('post')     ->to('groups#add_members');
    $check_auth->route('group/:gid/members/remove')                     ->via('post')     ->to('groups#remove_members');
  }

	return $self;
}

1;
