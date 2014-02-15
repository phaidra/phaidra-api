phaidra-api 
===========

Prerequisities:

* Mojolicious Plugins

  /usr/local/bin/cpanm Mojolicious::Plugin::Database
  
  /usr/local/bin/cpanm MooX::Types::MooseLike::Numeric --force
  
  /usr/local/bin/cpanm MooX::Types::MooseLike
  
  /usr/local/bin/cpanm Mojolicious::Plugin::CHI
  
  /usr/local/bin/cpanm Mojolicious::Plugin::I18N
  
  /usr/local/bin/cpanm Mojolicious::Plugin::Authentication
  
  /usr/local/bin/cpanm Net::LDAPS

  /usr/local/bin/cpanm IO::Socket::SSL
  
  
  (On Ubuntu: sudo apt-get install libmojolicious-plugin-i18n-perl)

* Run:

  $# morbo -w PhaidraAPI -w templates -w public -w lib api.cgi

  [debug] Reading config file "PhaidraAPI.json".

  Server available at http://127.0.0.1:3000.

* Apache/Hypnotoad

	Run: 
	
	Hypnotoad:
	
	/usr/local/bin/hypnotoad api.cgi

	or
		
	Morbo:
	
	env MOJO_REVERSE_PROXY=1 /usr/local/bin/morbo -w PhaidraAPI -w PhaidraAPI.json -w PhaidraAPI.pm -w templates -w public -w lib api.cgi
	
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

* Apache/CGI

  $# chown apache:apache api.cgi
  
  $# chmod u+x api.cgi

  Virtual host config:
  
        ScriptAlias /api my_document_root/api.cgi

        RewriteEngine on
        RewriteCond %{HTTP:Authorization} ^(.+)
        RewriteRule ^(.*)$ $1 [E=HTTP_AUTHORIZATION:%1,PT]
  
