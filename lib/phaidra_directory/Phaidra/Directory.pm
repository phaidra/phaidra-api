package Phaidra::Directory;

use strict;
use warnings;
use v5.10;

sub new 
{
	my ($class, $mojo, $config) = @_;

	my $self = {};
	bless($self, $class);
	$self->_init($mojo, $config);
	return $self;	
}

sub _init {
	my $self = shift;
  	my $mojo = shift;
  	my $config = shift;	
  	return $self;	
}

sub get_name {    
	my $username = shift;
	return 'base name';   
}

sub get_email {
	my $username = shift;
	return $username.'@xx.com';
}

1;
__END__
