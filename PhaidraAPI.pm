package PhaidraAPI;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';
use Mojo::Log;

# This method will run once at server start
sub startup {
    my $self = shift;

    my $config = $self->plugin( 'JSONConfig' => { file => 'PhaidraAPI.json' } );

	$self->mode($config->{mode});     
    $self->secret($config->{secret});
    
  	$self->log(Mojo::Log->new(path => $config->{log_path}, level => $config->{log_level}));
   
    my $r = $self->routes;
    $r->namespaces(['PhaidraAPI::Controller']);

	$r->route                            ->via('post')  ->to('objects#create');
    $r->route('/:pid', pid => qr/o:\d+/) ->via('get')   ->to('objects#getobject');    
    $r->route('/:pid', pid => qr/o:\d+/) ->via('put')   ->to('objects#update');
    $r->route('/:pid', pid => qr/o:\d+/) ->via('delete')->to('objects#delete');

	$r->route('info/metadata_format')    ->via('get')   ->to('info#metadata_format');      

    # init databases 
    $self->plugin('database', { 
    	databases => {
        	'db_metadata' => { 
				dsn      => $config->{phaidra_db}->{dsn},
                username => $config->{phaidra_db}->{username},
                password => $config->{phaidra_db}->{password},
            },
            'db_api' => {
                dsn      => $config->{api_db}->{dsn},
                username => $config->{api_db}->{username},
                password => $config->{api_db}->{password},
            },
        },
    });

}

1;
