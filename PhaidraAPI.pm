package PhaidraAPI;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';
use Log::Log4perl;
use Mojolicious::Static;
use Mojolicious::Plugin::I18N;
use Mojolicious::Plugin::Session;
use Mojolicious::Plugin::Log::Any;
use Mojo::Loader qw(load_class);
use FindBin;
use lib "$FindBin::Bin/lib/phaidra_directory";
use MongoDB 1.8.3;
use Sereal::Encoder qw(encode_sereal);
use Sereal::Decoder qw(decode_sereal);
use Crypt::CBC              ();
use Crypt::Rijndael         ();
use Crypt::URandom          (qw/urandom/);
use Digest::SHA             (qw/hmac_sha256/);
use Math::Random::ISAAC::XS ();
use DBIx::Connector;

BEGIN {
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

$ENV{MOJO_MAX_MESSAGE_SIZE}   = 207374182400;
$ENV{MOJO_INACTIVITY_TIMEOUT} = 1209600;
$ENV{MOJO_HEARTBEAT_TIMEOUT}  = 1209600;

#$ENV{MOJO_TMPDIR} = '/usr/local/fedora/imagemanipulator/tmp';

# This method will run once at server start
sub startup {
  my $self   = shift;
  my $config = $self->plugin('JSONConfig' => {file => 'PhaidraAPI.json'});
  $self->config($config);
  $self->mode($config->{mode});
  $self->secrets([$config->{secret}]);
  push @{$self->static->paths} => 'public';

  Log::Log4perl::init($FindBin::Bin . '/log4perl.conf');

  my $log = Log::Log4perl::get_logger("root");
  $self->plugin('Log::Any' => {logger => 'Log::Log4perl'});

  if ($config->{tmpdir}) {
    $self->app->log->debug("Setting MOJO_TMPDIR: " . $config->{tmpdir});
    $ENV{MOJO_TMPDIR} = $config->{tmpdir};
  }

  if ($config->{ssl_ca_path}) {
    $self->app->log->debug("Setting SSL_ca_path: " . $config->{ssl_ca_path});
    IO::Socket::SSL::set_defaults(SSL_ca_path => $config->{ssl_ca_path},);
  }

  my $directory_impl = $config->{directory_class};
  $self->app->log->debug("Loading directory implementation $directory_impl");
  my $e = load_class $directory_impl;
  if (ref $e) {
    $self->app->log->error("Loading $directory_impl failed: $e");

    #   next;
  }
  my $directory = $directory_impl->new($self, $config);

  $self->helper(directory => sub {return $directory;});

  # init I18N
  $self->plugin(I18N => {namespace => 'PhaidraAPI::I18N', support_url_langs => [qw(en de it sr)]});

  # init cache
  $self->plugin(
    CHI => {
      default => {
        driver => 'Memory',

        #driver     => 'File', # FastMmap seems to have problems saving the metadata structure (it won't save anything)
        #root_dir   => '/tmp/phaidra-api-cache',
        #cache_size => '20m',
        global => 1,

        #serializer => 'Storable',
      },
    }
  );

  # init databases
  my %databases;
  $databases{'db_metadata'} = {
    dsn      => $config->{phaidra_db}->{dsn},
    username => $config->{phaidra_db}->{username},
    password => $config->{phaidra_db}->{password},
    options  => {mysql_auto_reconnect => 1}
  };

  if ($config->{phaidra_user_db}) {
    $databases{'db_user'} = {
      dsn      => $config->{phaidra_user_db}->{dsn},
      username => $config->{phaidra_user_db}->{username},
      password => $config->{phaidra_user_db}->{password},
      options  => {mysql_auto_reconnect => 1}
    };
  }

  if ($config->{phaidra}->{triplestore} eq 'localMysqlMPTTriplestore') {
    $databases{'db_triplestore'} = {
      dsn      => $config->{localMysqlMPTTriplestore}->{dsn},
      username => $config->{localMysqlMPTTriplestore}->{username},
      password => $config->{localMysqlMPTTriplestore}->{password},
      options  => {mysql_auto_reconnect => 1}
    };
  }

  if ($config->{fedora}->{fedora_db}) {
    $databases{'db_fedora'} = {
      dsn      => $config->{fedora}->{fedora_db}->{dsn},
      username => $config->{fedora}->{fedora_db}->{username},
      password => $config->{fedora}->{fedora_db}->{password},
      options  => {mysql_auto_reconnect => 1}
    };
  }

  if ($config->{imagemanipulator_db}) {
    $databases{'db_imagemanipulator'} = {
      dsn      => $config->{imagemanipulator_db}->{dsn},
      username => $config->{imagemanipulator_db}->{username},
      password => $config->{imagemanipulator_db}->{password},
      options  => {mysql_auto_reconnect => 1}
    };
  }

  if ($config->{ir}) {
    $databases{'db_ir'} = {
      dsn      => $config->{ir}->{'db'}->{dsn},
      username => $config->{ir}->{'db'}->{username},
      password => $config->{ir}->{'db'}->{password},
      options  => {mysql_auto_reconnect => 1}
    };
  }

  if (exists($config->{sites})) {
    for my $f (@{$config->{sites}}) {
      if (exists($f->{stats})) {
        if ($f->{stats}->{type} eq 'piwik') {
          $databases{'db_stats_' . $f->{site}} = {
            dsn      => $f->{stats}->{db_piwik}->{dsn},
            username => $f->{stats}->{db_piwik}->{username},
            password => $f->{stats}->{db_piwik}->{password},
            options  => {mysql_auto_reconnect => 1, RaiseError => 1}
          };
        }
      }
    }
  }

  foreach my $helper (keys %databases) {
    my $dbconf = $databases{$helper};
    $self->app->log->error('missing dsn parameter for ' . $helper) unless (defined($dbconf->{dsn}));
    my $attr_name = '_dbh_' . $helper;
    $self->app->attr(
      $attr_name => sub {
        my $cntr = DBIx::Connector->new($dbconf->{dsn}, $dbconf->{username}, $dbconf->{password}, $dbconf->{options});
        $cntr->mode('ping');
        return $cntr;
      }
    );
    $self->app->helper($helper => sub {return shift->app->$attr_name()});
  }

  # MongoDB driver
  $self->helper(
    mongo => sub {
      state $mongo = MongoDB::MongoClient->new(
        host               => $config->{mongodb}->{host},
        port               => $config->{mongodb}->{port},
        username           => $config->{mongodb}->{username},
        password           => $config->{mongodb}->{password},
        connect_timeout_ms => 300000,
        socket_timeout_ms  => 300000,
      )->get_database($config->{mongodb}->{database});
    }
  );

  if (exists($config->{paf_mongodb})) {
    $self->helper(
      paf_mongo => sub {
        state $paf_mongo = MongoDB::MongoClient->new(
          host     => $config->{paf_mongodb}->{host},
          port     => $config->{paf_mongodb}->{port},
          username => $config->{paf_mongodb}->{username},
          password => $config->{paf_mongodb}->{password},
        )->get_database($config->{paf_mongodb}->{database});
      }
    );
  }

  if (exists($config->{irma})) {
    $self->helper(
      irma_mongo => sub {
        state $paf_mongo = MongoDB::MongoClient->new(
          host     => $config->{irma}->{host},
          port     => $config->{irma}->{port},
          username => $config->{irma}->{username},
          password => $config->{irma}->{password},
          db_name  => $config->{irma}->{database}
        )->get_database($config->{irma}->{database});
      }
    );
  }

  # we might possibly save a lot of data to session
  # so we are not going to use cookies, but a database instead
  $self->plugin(
    session => {
      stash_key => 'mojox-session',
      store     => PhaidraAPI::Model::Session::Store::Mongo->new(
        mongo => $self->mongo,
        'log' => $self->log
      ),
      transport => PhaidraAPI::Model::Session::Transport::Header->new(
        header_name => $config->{authentication}->{token_header},
        cookie_name => $config->{authentication}->{token_cookie},
        'log'       => $self->log
      ),
      expires_delta => $config->{session_expiration},
      ip_match      => $config->{session_ip_match}
    }
  );

  $self->hook(
    'before_dispatch' => sub {
      my $self    = shift;
      my $session = $self->stash('mojox-session');
      $session->load;
      if ($session->is_expired) {
        $session->expire;
        $session->flush;
      }
      elsif ($session->sid) {
        $session->extend_expires;
        $session->flush;
      }
    }
  );

  $self->hook(
    'after_dispatch' => sub {
      my $self = shift;
      my $json = $self->res->json;
      if ($json) {
        if (ref $json eq ref {}) {    # only if json is really a hash
          if ($json->{alerts}) {
            if (scalar(@{$json->{alerts}}) > 0) {
              $self->app->log->debug("Alerts:\n" . $self->dumper($json->{alerts}));
            }
          }
        }
      }

      # CORS
      unless ($self->res->headers->header('Access-Control-Allow-Origin')) {
        if ($self->req->headers->header('Origin')) {
          $self->res->headers->add('Access-Control-Allow-Origin' => $self->req->headers->header('Origin'));
        }
        else {
          $self->res->headers->add('Access-Control-Allow-Origin' => $config->{authentication}->{'Access-Control-Allow-Origin'});
        }
      }
      $self->res->headers->add('Access-Control-Allow-Credentials' => 'true');
      $self->res->headers->add('Access-Control-Allow-Methods'     => 'GET, POST, PUT, DELETE, OPTIONS');

      # X-Prototype-Version, X-Requested-With - comes from prototype's Ajax.Updater
      my $allow_headers = 'Authorization, Content-Type, X-Prototype-Version, X-Requested-With, ' . $config->{authentication}->{token_header};
      if ($config->{authentication}->{upstream}->{principalheader}) {
        $allow_headers .= ', ' . $config->{authentication}->{upstream}->{principalheader};
      }
      if ($config->{authentication}->{upstream}->{affiliationheader}) {
        $allow_headers .= ', ' . $config->{authentication}->{upstream}->{affiliationheader};
      }

      $self->res->headers->add('Access-Control-Allow-Headers'  => $allow_headers);
      $self->res->headers->add('Access-Control-Expose-Headers' => 'x-json, Content-Disposition');
    }
  );

  $self->helper(
    save_cred => sub {
      my $self = shift;
      my $u    = shift;
      my $p    = shift;
      my $ru   = shift;

      my $ciphertext;

      my $session = $self->stash('mojox-session');
      $session->load;
      unless ($session->sid) {
        $session->create;
      }
      my $ba;
      if (defined($u)) {
        $ba = encode_sereal({username => $u, password => $p});
      }
      if (defined($ru)) {
        $ba = encode_sereal({remote_user => $ru});
      }
      my $salt = Math::Random::ISAAC::XS->new(map {unpack("N", urandom(4))} 1 .. 256)->irand();
      my $key  = hmac_sha256($salt, $self->app->config->{enc_key});
      my $cbc  = Crypt::CBC->new(-key => $key, -pbkdf => 'pbkdf2');

      eval {$ciphertext = encode_base64url($cbc->encrypt($ba));};
      $self->app->log->error("Encoding error: $@") if $@;
      $session->data(cred => $ciphertext, salt => $salt);

      #$self->app->log->debug("Created session: ".$session->sid);
    }
  );

  $self->helper(
    load_cred => sub {
      my $self = shift;

      my $session = $self->stash('mojox-session');
      $session->load;
      unless ($session->sid) {
        return undef;
      }

      #$self->app->log->debug("Loaded session: ".$session->sid);

      my $salt       = $session->data('salt');
      my $ciphertext = $session->data('cred');
      my $key        = hmac_sha256($salt, $self->app->config->{enc_key});
      my $cbc        = Crypt::CBC->new(-key => $key, -pbkdf => 'pbkdf2');
      my $data;
      eval {$data = decode_sereal($cbc->decrypt(decode_base64url($ciphertext)))};
      $self->app->log->error("Decoding error: $@") if $@;

      return $data;
    }
  );

  # Set Content-Type header for XML rendering (default is 'application/xml', see https://docs.mojolicious.org/Mojolicious/Types) to be consistent with Fedora XML responses
  $self->types->type(xml => 'text/xml; charset=utf-8');

  my $r = $self->routes;
  $r->namespaces(['PhaidraAPI::Controller']);

  #<<< perltidy ignore
  $r->route('')                                   ->via('get')    ->to('authentication#signin_shib');
  $r->route('languages')                          ->via('get')    ->to('languages#get_languages');
  $r->route('licenses')                           ->via('get')    ->to('licenses#get_licenses');

  $r->route('uwmetadata/tree')                    ->via('get')    ->to('uwmetadata#tree');
  $r->route('uwmetadata/json2xml')                ->via('post')   ->to('uwmetadata#json2xml');
  $r->route('uwmetadata/xml2json')                ->via('post')   ->to('uwmetadata#xml2json');
  $r->route('uwmetadata/validate')                ->via('post')   ->to('uwmetadata#validate');
  $r->route('uwmetadata/json2xml_validate')       ->via('post')   ->to('uwmetadata#json2xml_validate');
  $r->route('uwmetadata/compress')                ->via('post')   ->to('uwmetadata#compress');
  $r->route('uwmetadata/decompress')              ->via('post')   ->to('uwmetadata#decompress');

  $r->route('mods/tree')                          ->via('get')    ->to('mods#tree');
  $r->route('mods/json2xml')                      ->via('post')   ->to('mods#json2xml');
  $r->route('mods/xml2json')                      ->via('post')   ->to('mods#xml2json');
  $r->route('mods/validate')                      ->via('post')   ->to('mods#validate');
  # possible parameters: fix, pid
  $r->route('mods/json2xml_validate')             ->via('post')   ->to('mods#json2xml_validate');

  $r->route('rights/json2xml')                    ->via('post')   ->to('rights#json2xml');
  $r->route('rights/xml2json')                    ->via('post')   ->to('rights#xml2json');
  $r->route('rights/validate')                    ->via('post')   ->to('rights#validate');
  $r->route('rights/json2xml_validate')           ->via('post')   ->to('rights#json2xml_validate');

  $r->route('geo/json2xml')                       ->via('post')   ->to('geo#json2xml');
  $r->route('geo/xml2json')                       ->via('post')   ->to('geo#xml2json');
  $r->route('geo/validate')                       ->via('post')   ->to('geo#validate');
  $r->route('geo/json2xml_validate')              ->via('post')   ->to('geo#json2xml_validate');

  $r->route('members/order/json2xml')             ->via('post')   ->to('membersorder#json2xml');
  $r->route('members/order/xml2json')             ->via('post')   ->to('membersorder#xml2json');

  $r->route('annotations/json2xml')               ->via('post')   ->to('annotations#json2xml');
  $r->route('annotations/xml2json')               ->via('post')   ->to('annotations#xml2json');
  $r->route('annotations/validate')               ->via('post')   ->to('annotations#validate');
  $r->route('annotations/json2xml_validate')      ->via('post')   ->to('annotations#json2xml_validate');

  $r->route('help/tooltip')                       ->via('get')    ->to('help#tooltip');

  $r->route('directory/get_study')                ->via('get')    ->to('directory#get_study');
  $r->route('directory/get_study_plans')          ->via('get')    ->to('directory#get_study_plans');
  $r->route('directory/get_study_name')           ->via('get')    ->to('directory#get_study_name');
  # old
  $r->route('directory/get_org_units')            ->via('get')    ->to('directory#get_org_units');
  $r->route('directory/get_parent_org_unit_id')   ->via('get')    ->to('directory#get_parent_org_unit_id');
  # new
  $r->route('directory/org_get_subunits')         ->via('get')    ->to('directory#org_get_subunits');
  $r->route('directory/org_get_superunits')       ->via('get')    ->to('directory#org_get_superunits');
  $r->route('directory/org_get_parentpath')       ->via('get')    ->to('directory#org_get_parentpath');
  $r->route('directory/org_get_units')            ->via('get')    ->to('directory#org_get_units');

  $r->route('search/owner/#username')             ->via('get')    ->to('search#owner');
  $r->route('search/collections/owner/#username') ->via('get')    ->to('search#collections_owner');
  $r->route('search/triples')                     ->via('get')    ->to('search#triples');
  $r->route('search')                             ->via('get')    ->to('search#search');
  # lucene query can be long -> post
  $r->route('search/lucene')                      ->via('post')   ->to('search#search_lucene');

  $r->route('search/get_pids')                    ->via('post')   ->to('search#get_pids');

  $r->route('utils/get_all_pids')                 ->via('get')    ->to('utils#get_all_pids');

  $r->route('vocabulary')                         ->via('get')    ->to('vocabulary#get_vocabulary');

  $r->route('terms/label')                   		  ->via('get')    ->to('terms#label');
  $r->route('terms/children')                	    ->via('get')    ->to('terms#children');
  $r->route('terms/search')                       ->via('get')    ->to('terms#search');
  $r->route('terms/taxonpath')                    ->via('get')    ->to('terms#taxonpath');
  $r->route('terms/parent')                       ->via('get')    ->to('terms#parent');

  $r->route('resolve')                            ->via('get')    ->to('resolve#resolve');

  # CORS
  $r->any('*')                                    ->via('options')->to('authentication#cors_preflight');

  $r->route('signin')                             ->via('get')    ->to('authentication#signin');
  $r->route('signout')                            ->via('get')    ->to('authentication#signout');
  $r->route('keepalive')                          ->via('get')    ->to('authentication#keepalive');

  $r->route('collection/:pid/members')            ->via('get')    ->to('collection#get_collection_members');
  $r->route('collection/:pid/descendants')        ->via('get')    ->to('collection#descendants');

  # does not show inactive objects, not specific to collection (but does ordering)
  $r->route('object/:pid/related')                ->via('get')    ->to('search#related');

  # we will get this datastreams by using intcall credentials
  # (instead of defining a API-A disseminator for each of them)
  $r->route('object/:pid/uwmetadata')             ->via('get')    ->to('uwmetadata#get');
  $r->route('object/:pid/mods')                   ->via('get')    ->to('mods#get');
  $r->route('object/:pid/jsonld')                 ->via('get')    ->to('jsonld#get');
  $r->route('object/:pid/json-ld')                ->via('get')    ->to('jsonld#get', header => '1');
  $r->route('object/:pid/geo')                    ->via('get')    ->to('geo#get');
  $r->route('object/:pid/members/order')          ->via('get')    ->to('membersorder#get');
  $r->route('object/:pid/annotations')            ->via('get')    ->to('annotations#get');
  $r->route('object/:pid/techinfo')               ->via('get')    ->to('techinfo#get');
  $r->route('object/:pid/dc')                     ->via('get')    ->to('dc#get', dsid => 'DC_P');
  $r->route('object/:pid/oai_dc')                 ->via('get')    ->to('dc#get', dsid => 'DC_OAI');
  $r->route('object/:pid/index')                  ->via('get')    ->to('index#get');
  $r->route('object/:pid/index/dc')               ->via('get')    ->to('index#get_dc');
  $r->route('object/:pid/index/relationships')    ->via('get')    ->to('index#get_relationships');
  $r->route('object/:pid/index/members')          ->via('get')    ->to('index#get_object_members');
  $r->route('object/:pid/datacite')               ->via('get')    ->to('datacite#get');
  $r->route('object/:pid/state')                  ->via('get')    ->to('object#get_state');
  $r->route('object/:pid/cmodel')                 ->via('get')    ->to('object#get_cmodel');
  $r->route('object/:pid/relationships')          ->via('get')    ->to('relationships#get');

  $r->route('object/:pid/id')                     ->via('get')    ->to('search#id');

  $r->route('dc/uwmetadata_2_dc_index')           ->via('post')   ->to('dc#uwmetadata_2_dc_index');

  $r->route('stats/aggregates')                   ->via('get')    ->to('stats#aggregates');
  $r->route('stats/disciplines')                  ->via('get')    ->to('stats#disciplines');
  $r->route('stats/:pid')                         ->via('get')    ->to('stats#stats');
  $r->route('stats/:pid/downloads')               ->via('get')    ->to('stats#stats', stats_param_key => 'downloads');
  $r->route('stats/:pid/detail_page')             ->via('get')    ->to('stats#stats', stats_param_key => 'detail_page');
  $r->route('stats/:pid/chart')                   ->via('get')    ->to('stats#chart');

  $r->route('ir/stats/topdownloads')              ->via('get')    ->to('ir#stats_topdownloads');
  $r->route('ir/stats/:pid')                      ->via('get')    ->to('ir#stats');
  $r->route('ir/stats/:pid/downloads')            ->via('get')    ->to('ir#stats', stats_param_key => 'downloads');
  $r->route('ir/stats/:pid/detail_page')          ->via('get')    ->to('ir#stats', stats_param_key => 'detail_page');
  $r->route('ir/stats/:pid/chart')                ->via('get')    ->to('ir#stats_chart');

  $r->route('directory/user/#username/data')      ->via('get')    ->to('directory#get_user_data');
  $r->route('directory/user/#username/name')      ->via('get')    ->to('directory#get_user_name');
  $r->route('directory/user/#username/email')     ->via('get')    ->to('directory#get_user_email');

  $r->route('oai')                                ->via('get')    ->to('oai#handler');
  $r->route('oai')                                ->via('post')   ->to('oai#handler');

  $r->route('termsofuse')                         ->via('get')    ->to('termsofuse#get');

  $r->route('list/token/:token')                  ->via('get')    ->to('lists#get_token_list');

  # this just extracts the credentials - authentication will be done by fedora
  my $proxyauth = $r->under('/')->to('authentication#extract_credentials', creds_must_be_present => 1);
  my $proxyauth_optional = $r->under('/')->to('authentication#extract_credentials', creds_must_be_present => 0);

  my $check_auth = $proxyauth->under('/')->to('authentication#authenticate');

  if ($self->app->config->{fedora}->{version} >= 6) {
    $proxyauth_optional = $proxyauth_optional->under('/')->to('authorization#authorize', op => 'r');
    $proxyauth = $check_auth->under('/')->to('authorization#authorize', op => 'w');
  }

  # check the user sends phaidra admin credentials
  my $check_admin_auth = $proxyauth->under('/')->to('authentication#authenticate_admin');

  if($self->app->config->{allow_userdata_queries}){
    $check_auth->route('directory/user/search')                           ->via('get')      ->to('directory#search_user');
  }

  $check_auth->route('directory/user/data')                               ->via('get')      ->to('directory#get_user_data');

  $check_auth->route('settings')                                          ->via('get')      ->to('settings#get_settings');

  $check_auth->route('groups')                                            ->via('get')      ->to('groups#get_users_groups');
  $check_auth->route('group/:gid')                                        ->via('get')      ->to('groups#get_group');

  $check_auth->route('lists')                                             ->via('get')      ->to('lists#get_lists');
  $check_auth->route('list/:lid')                                         ->via('get')      ->to('lists#get_list');

  $check_auth->route('jsonld/templates')                                  ->via('get')      ->to('jsonld#get_users_templates');
  $check_auth->route('jsonld/template/:tid')                              ->via('get')      ->to('jsonld#get_template');

  $proxyauth_optional->route('authz/check/:pid/:op')                      ->via('get')      ->to('authorization#check_rights');

  $proxyauth_optional->route('streaming/:pid')                            ->via('get')      ->to('utils#streamingplayer');
  $proxyauth_optional->route('streaming/:pid/key')                        ->via('get')      ->to('utils#streamingplayer_key');

  $proxyauth_optional->route('imageserver')                               ->via('get')      ->to('imageserver#get');

  $proxyauth_optional->route('object/:pid/diss/:bdef/:method')            ->via('get')      ->to('object#diss');
  $proxyauth_optional->route('object/:pid/fulltext')                      ->via('get')      ->to('fulltext#get');
  $proxyauth_optional->route('object/:pid/iiifmanifest')                  ->via('get')      ->to('object#get_iiif_manifest');
  $proxyauth_optional->route('object/:pid/metadata')                      ->via('get')      ->to('object#get_metadata');
  $proxyauth_optional->route('object/:pid/info')                          ->via('get')      ->to('object#info');
  $proxyauth_optional->route('object/:pid/thumbnail')                     ->via('get')      ->to('object#thumbnail');
  $proxyauth_optional->route('object/:pid/preview')                       ->via('get')      ->to('object#preview');
  $proxyauth_optional->route('object/:pid/md5')                           ->via('get')      ->to('inventory#get_md5');
  $proxyauth_optional->route('object/:pid/octets')                        ->via('get')      ->to('octets#proxy');
  $proxyauth_optional->route('object/:pid/download')                      ->via('get')      ->to('octets#get', operation => 'download');
  $proxyauth_optional->route('object/:pid/get')                           ->via('get')      ->to('octets#get', operation => 'get');

  $proxyauth_optional->route('imageserver/:pid/status')                   ->via('get')      ->to('imageserver#status');

  $proxyauth->route('object/:pid/jsonldprivate')                          ->via('get')      ->to('jsonldprivate#get');
  $proxyauth->route('object/:pid/rights')                                 ->via('get')      ->to('rights#get');

  $check_auth->route('ir/requestedlicenses')                              ->via('post')     ->to('ir#adminlistdata'); # remove
  $check_auth->route('ir/adminlistdata')                                  ->via('post')     ->to('ir#adminlistdata');
  $check_auth->route('ir/:pid/events')                                    ->via('get')      ->to('ir#events');
  $check_auth->route('ir/allowsubmit')                                    ->via('get')      ->to('ir#allowsubmit');
  $check_auth->route('ir/puresearch')                                     ->via('get')      ->to('ir#puresearch');

  $check_auth->route('termsofuse/getagreed')                              ->via('get')      ->to('termsofuse#getagreed');

  $check_admin_auth->route('test/error')                                  ->via('get')      ->to('utils#testerror');

  unless($self->app->config->{readonly}){

    $check_admin_auth->route('index')                                     ->via('post')     ->to('index#update');
    $check_admin_auth->route('dc')                                        ->via('post')     ->to('dc#update');

    $check_auth->route('settings')                                        ->via('post')     ->to('settings#post_settings');

    $check_admin_auth->route('mint/pid')                                  ->via('post')     ->to('object#mint_pid');
    $check_admin_auth->route('object/:pid/index')                         ->via('post')     ->to('index#update');
    $check_admin_auth->route('object/:pid/dc')                            ->via('post')     ->to('dc#update');

    $check_admin_auth->route('ir/embargocheck')                           ->via('post')     ->to('ir#embargocheck');

    $check_admin_auth->route('imageserver/process')                       ->via('post')     ->to('imageserver#process_pids');

    $proxyauth->route('imageserver/:pid/process')                         ->via('post')     ->to('imageserver#process');

    $proxyauth->route('object/:pid/updateiiifmanifest')                   ->via('post')     ->to('iiifmanifest#update_manifest_metadata');
    $proxyauth->route('object/:pid/modify')                               ->via('post')     ->to('object#modify');
    $proxyauth->route('object/:pid/delete')                               ->via('post')     ->to('object#delete');
    $proxyauth->route('object/:pid/uwmetadata')                           ->via('post')     ->to('uwmetadata#post');
    $proxyauth->route('object/:pid/mods')                                 ->via('post')     ->to('mods#post');
    $proxyauth->route('object/:pid/jsonld')                               ->via('post')     ->to('jsonld#post');
    $proxyauth->route('object/:pid/jsonldprivate')                        ->via('post')     ->to('jsonldprivate#post');
    $proxyauth->route('object/:pid/geo')                                  ->via('post')     ->to('geo#post');
    $proxyauth->route('object/:pid/annotations')                          ->via('post')     ->to('annotations#post');
    $proxyauth->route('object/:pid/rights')                               ->via('post')     ->to('rights#post');
    $proxyauth->route('object/:pid/iiifmanifest')                         ->via('post')     ->to('iiifmanifest#post');
    $proxyauth->route('object/:pid/metadata')                             ->via('post')     ->to('object#metadata');
    $proxyauth->route('object/create')                                    ->via('post')     ->to('object#create_empty');
    $proxyauth->route('object/create/:cmodel')                            ->via('post')     ->to('object#create');
    $proxyauth->route('object/:pid/relationship/add')                     ->via('post')     ->to('object#add_relationship');
    $proxyauth->route('object/:pid/relationship/remove')                  ->via('post')     ->to('object#purge_relationship');
    $proxyauth->route('object/:pid/id/add')                               ->via('post')     ->to('object#add_or_remove_identifier', operation => 'add');
    $proxyauth->route('object/:pid/id/remove')                            ->via('post')     ->to('object#add_or_remove_identifier', operation => 'remove');
    $proxyauth->route('object/:pid/datastream/:dsid')                     ->via('post')     ->to('object#add_or_modify_datastream');
    $proxyauth->route('object/:pid/data')                                 ->via('post')     ->to('object#add_octets');

    $proxyauth->route('picture/create')                                   ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:Picture');
    $proxyauth->route('document/create')                                  ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:PDFDocument');
    $proxyauth->route('video/create')                                     ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:Video');
    $proxyauth->route('audio/create')                                     ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:Audio');
    $proxyauth->route('unknown/create')                                   ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:Asset');
    $proxyauth->route('resource/create')                                  ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:Resource');
    $proxyauth->route('page/create')                                      ->via('post')     ->to('object#create_simple', cmodel => 'cmodel:Page');

    $proxyauth->route('container/create')                                 ->via('post')     ->to('object#create_container');
    $proxyauth->route('container/:pid/members/order')                     ->via('post')     ->to('membersorder#post');
    $proxyauth->route('container/:pid/members/:itempid/order/:position')  ->via('post')     ->to('membersorder#order_object_member');

    $proxyauth->route('collection/create')                                ->via('post')     ->to('collection#create');
    $proxyauth->route('collection/:pid/members/remove')                   ->via('post')     ->to('collection#remove_collection_members');
    $proxyauth->route('collection/:pid/members/add')                      ->via('post')     ->to('collection#add_collection_members');
    $proxyauth->route('collection/:pid/members/order')                    ->via('post')     ->to('membersorder#post');
    $proxyauth->route('collection/:pid/members/:itempid/order/:position') ->via('post')     ->to('membersorder#order_object_member');

    $check_auth->route('group/add')                                       ->via('post')     ->to('groups#add_group');
    $check_auth->route('group/:gid/remove')                               ->via('post')     ->to('groups#remove_group');
    $check_auth->route('group/:gid/members/add')                          ->via('post')     ->to('groups#add_members');
    $check_auth->route('group/:gid/members/remove')                       ->via('post')     ->to('groups#remove_members');

    $check_auth->route('list/add')                                        ->via('post')     ->to('lists#add_list');
    $check_auth->route('list/:lid/token/create')                          ->via('post')     ->to('lists#token_create');
    $check_auth->route('list/:lid/token/delete')                          ->via('post')     ->to('lists#token_delete');
    $check_auth->route('list/:lid/remove')                                ->via('post')     ->to('lists#remove_list');
    $check_auth->route('list/:lid/members/add')                           ->via('post')     ->to('lists#add_members');
    $check_auth->route('list/:lid/members/remove')                        ->via('post')     ->to('lists#remove_members');

    $check_auth->route('jsonld/template/add')                             ->via('post')     ->to('jsonld#add_template');
    $check_auth->route('jsonld/template/:tid/remove')                     ->via('post')     ->to('jsonld#remove_template');

    $proxyauth->route('ir/submit')                                        ->via('post')     ->to('ir#submit');
    $check_auth->route('ir/notifications')                                ->via('post')     ->to('ir#notifications');
    $check_auth->route('ir/:pid/accept')                                  ->via('post')     ->to('ir#accept');
    $check_auth->route('ir/:pid/reject')                                  ->via('post')     ->to('ir#reject');
    $check_auth->route('ir/:pid/approve')                                 ->via('post')     ->to('ir#approve');

    $check_auth->route('feedback')                                        ->via('post')     ->to('feedback#feedback');

    $check_auth->route('termsofuse/agree/:version')                       ->via('post')     ->to('termsofuse#agree');
  }
  #>>>

  return $self;
}

1;
