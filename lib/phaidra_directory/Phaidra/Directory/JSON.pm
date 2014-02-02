package Phaidra::Directory::JSON;

use strict;
use warnings;
use v5.10;
use Mojo::JSON;
use base 'Phaidra::Directory';

my $directory = {};

sub _init {
  # this is the app config
  my $self = shift;
  my $mojo = shift;
  my $config = shift;
  
  my $json_text = do {
  	open(my $json_fh, "<:encoding(UTF-8)", 'lib/phaidra_directory/Phaidra/Directory/directory.json')
    or $mojo->log->error("Can't open \$filename\": $!\n");
   	local $/;
   	<$json_fh>
  };

  my $json  = Mojo::JSON->new;
  $directory = $json->decode($json_text);
  
  return $self;
}

# usage in controller: $self->app->directory->get_name($self, 'madmax');
sub get_name {
	my $self = shift;
	my $c = shift;
	my $username = shift;    
	
	return $directory->{users}->{$username}->{firstname}.' '.$directory->{users}->{$username}->{firstname};   
}

1;
__END__
