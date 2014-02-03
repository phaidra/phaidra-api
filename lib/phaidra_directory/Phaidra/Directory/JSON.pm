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

sub get_email {
	my $self = shift;
	my $c = shift;
	my $username = shift;

	$c->app->log->error("This method is not implemented");
}

# getFaculties
# getDepartments
sub get_org_units {
	my $self = shift;
	my $c = shift;
	my $parent_id = shift; # undef if none
	my $lang = shift;
	
	$c->app->log->error("This method is not implemented");
}

# getFacultyId
sub get_parent_org_unit_id {
	my $self = shift;
	my $c = shift;
	my $child_id = shift;
	
	$c->app->log->error("This method is not implemented");
}

# getFacultyName
# getDepartmentName
sub get_org_unit_name {
	my $self = shift;
	my $c = shift;
	my $unit_id = shift;
	my $lang = shift;
	
	$c->app->log->error("This method is not implemented");
}

# getAuthorInstitutionName
# getAuthorInstitutionNameNoCtx
sub get_affiliation {
	my $self = shift;
	my $c = shift;
	my $unit_id = shift;
	my $lang = shift;
	
	$c->app->log->error("This method is not implemented");
}

# getInstitutionName
sub get_org_name {
	my $self = shift;
	my $c = shift;
	my $lang = shift;
	
	$c->app->log->error("This method is not implemented");
}

# uni specific
sub get_study_plans {
	my $self = shift;
	my $c = shift;
	my $lang = shift;
	
	$c->app->log->error("This method is not implemented");
}

# uni specific        
sub get_study {
	my $self = shift;
	my $c = shift;
	my $id = shift;
	my $index = shift;
	my $lang = shift;
	
	$c->app->log->error("This method is not implemented");
}

# uni specific
sub get_study_name {
	my $self = shift;
	my $c = shift;
	my $id = shift;
	my $index = shift;
	my $lang = shift;
	
	$c->app->log->error("This method is not implemented");
}

# getPersFunk
sub get_pers_funktions {
	my $self = shift;
	my $c = shift;
	my $lang = shift;
	
	$c->app->log->error("This method is not implemented");
}
 
# getPersFunkName
sub get_pers_funktion_name {
	my $self = shift;
	my $c = shift;
	my $id = shift;
	my $lang = shift;
	
	$c->app->log->error("This method is not implemented");
}
  
# getLoginData
sub get_login_data {
	my $self = shift;
	my $c = shift;
	my $username = shift;
	
	# $fname,$lname,\@inums,\@fakcodes;
	$c->app->log->error("This method is not implemented");
}

sub is_superuser {
	my $self = shift;
	my $c = shift;
	my $username = shift;
	
	$c->app->log->error("This method is not implemented");
}
      
sub is_superuser_for_user {
	my $self = shift;
	my $c = shift;
	my $username = shift;
	
	# \@users
	$c->app->log->error("This method is not implemented");
}

sub search_user {
	my $self = shift;
	my $c = shift;
	my $query = shift;
	
	# $person = { uid => $uid, name => $name };
	#return \@persons,$hits;
	$c->app->log->error("This method is not implemented");
}        

1;
__END__
