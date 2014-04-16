phaidra-api 
===========

Prerequisities:

* Mojolicious Plugins

  /usr/local/bin/cpanm Mango

  /usr/local/bin/cpanm MooX::Types::MooseLike::Numeric --force

  /usr/local/bin/cpanm MooX::Types::MooseLike

  /usr/local/bin/cpanm Mojolicious::Plugin::Database
  
  /usr/local/bin/cpanm Mojolicious::Plugin::Session
  
  /usr/local/bin/cpanm Mojolicious::Plugin::CHI
  
  /usr/local/bin/cpanm Mojolicious::Plugin::I18N
  
  /usr/local/bin/cpanm Mojolicious::Plugin::Authentication
  
  /usr/local/bin/cpanm Net::LDAPS

  /usr/local/bin/cpanm IO::Socket::SSL

  /usr/local/bin/cpanm Sereal
 
  /usr/local/bin/cpanm Crypt::CBC

  /usr/local/bin/cpanm Crypt::Rijndael

  /usr/local/bin/cpanm Crypt::URandom

  /usr/local/bin/cpanm Math::Random::ISAAC::XS
 
  /usr/local/bin/cpanm MIME::Base64 

  /usr/local/bin/cpanm 
  
  (On Ubuntu: sudo apt-get install libmojolicious-plugin-i18n-perl)


* Config

  vi PhaidraAPI.json (see PhaidraAPI.json.example) Make sure log directory exists.

  vi lib/phaidra_directory/Phaidra/Directory/directory.json (ev also JSON.pm or add the class you are using) 

* Run:

  $# morbo -w PhaidraAPI -w templates -w public -w lib phaidra-api.cgi

  [debug] Reading config file "PhaidraAPI.json".

  Server available at http://127.0.0.1:3000.

* Apache/Hypnotoad

	Run: 
	
	Hypnotoad:
	
	/usr/local/bin/hypnotoad phaidra-api.cgi

	or
		
	Morbo:
	
	env MOJO_REVERSE_PROXY=1 /usr/local/bin/morbo -w PhaidraAPI -w PhaidraAPI.json -w PhaidraAPI.pm -w templates -w public -w lib phaidra-api.cgi
	
	Apache virtual host conf (among other stuff, eg SSLEngine config):
	
		RewriteEngine on
        RewriteCond %{HTTP:Authorization} ^(.+)
        RewriteRule ^(.*)$ $1 [E=HTTP_AUTHORIZATION:%1,PT]

        <Proxy *>
                Order deny,allow
                Allow from all
        </Proxy>

        ProxyRequests Off
        ProxyPreserveHost On

		# not used
        #RewriteCond %{HTTPS} =off
        #RewriteRule . - [E=protocol:http]
        #RewriteCond %{HTTPS} =on
        #RewriteRule . - [E=protocol:https]
        #RewriteRule ^/api/(.*) %{ENV:protocol}://localhost:3000/$1 [P]

        ProxyPassReverse  /api/ http://localhost:3000/
        ProxyPassReverse  /api/ https://localhost:3000/

        ProxyPass /api/ http://localhost:3000/ keepalive=On

        RequestHeader set X-Forwarded-HTTPS "1"

	Hypnotoad config (PhaidraAPI.json):
		proxy: 1	
