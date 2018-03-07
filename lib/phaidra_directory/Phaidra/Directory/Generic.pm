package Phaidra::Generic;

use strict;
use warnings;
use Data::Dumper;
use utf8;
use MongoDB;
use Data::UUID;
use YAML::Syck;

my $config = undef;
eval { $config = YAML::Syck::LoadFile('/etc/phaidra.yml'); };
if($@)
{
    print "ERR: $@\n";
}

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

sub authenticate($$$$){
	my $app = shift;
	my $username = shift; 
	my $password = shift;
	my $extradata = shift;
	
	my $res = { alerts => [], status => 500 };

	for my $u (@{$config->{users}}){
		if(($u->{username} eq $username) && ($u->{password} eq $password )){
			$res->{status} = 200;   
        	$c->stash({phaidra_auth_result => $res});
            return $username;
		}
	}
	
	unshift @{$res->{alerts}}, { type => 'danger', msg => "User not found" };        
    $res->{status} = 401;   
    $c->stash({phaidra_auth_result => $res});
    return undef;
}

sub validate_user(){
	my $app = shift;
	my $username = shift; 
	my $password = shift;
	my $extradata = shift;
	
	my $ret = authenticate($app, $username, $password, $extradata);
	
	# Mojolicious::Plugin::Authenticate requires that error returns undef and success uid
	if($ret->{status} eq 200){
		$app->log->info("successfuly authenticated $username");
		return $username;
	}else{
		$app->log->error("authentication failed, error code: ".$ret->{status}."\n".$app->dumper($ret->{alerts}));
		return undef;	
	}
}

sub connect_mongodb_groupmanager()
{
	my $uri = "mongodb://"
		. $config->{mongodb_group_manager}->{username}.":".$config->{mongodb_group_manager}->{password}
		. "@"
		. $config->{mongodb_group_manager}->{host}.":".$config->{mongodb_group_manager}->{port}
		. "/".$config->{mongodb_group_manager}->{database};
	my $client = MongoDB->connect($uri);

=cut for 0.45 driver
    my $client = MongoDB::Connection->new(
    	host => $config->{mongodb_group_manager}->{host}, 
    	port => $config->{mongodb_group_manager}->{port},
    	username => $config->{mongodb_group_manager}->{username},
    	password => $config->{mongodb_group_manager}->{password},
    	db_name => $config->{mongodb_group_manager}->{database}
    );
=cut
	return $client;
}

sub get_groups_col()
{
	my $client = connect_mongodb_groupmanager();
	my $db = $client->get_database($config->{mongodb_group_manager}->{database});
	return $db->get_collection($config->{mongodb_group_manager}->{collection});
}

#get the email adress for a specific user
sub get_email
{
	my ($self,$c,$username)=@_;

	die("PHAIDRA ORGANIZATIONAL ERROR: undefined username") unless(defined($username));
	
	for my $user (@{$config->{users}}){
		if($user->{username} eq $username){
      return $user->{email};
    }
	}
}

#get the name to a specific user id
sub get_mame
{
	my ($self,$c,$username)=@_;

	die("PHAIDRA ORGANIZATIONAL ERROR:undefined username") unless(defined($username));

	for my $user (@{$config->{users}}){
		if($user->{username} eq $username){
      return $user->{firstname}.' '.$user->{lastname};
    }
	}
}

#get all departments of a faculty
sub get_org_units
{
	my ($self,$c,$fakcode)=@_;

	$fakcode =~ s/A//g;
	my $values;
	if($fakcode){
		if($fakcode ne '-1') #fakcode A-1 == whole university => has no departments
		{
			for my $f (@{$config->{faculties}}){
			if($f->{fakcode} eq $fakcode){
				for my $d (@{$f->{departments}}){
				push @$values, {value => $d->{inum}, name => $d->{name}};
				}
			}
			}
		}
	}else{
		for my $f (@{$config->{faculties}}){
			push @$values, {value => $f->{fakcode}, name => $f->{name}};
		}
	}
  
  return $values;
}

#get the id of a faculty
sub get_parent_org_unit_id
{
	my($self,$c,$inum)=@_;
	
	die("Internal error: undefined inum") unless(defined($inum));

  for my $f (@{$config->{faculties}}){
    for my $d (@{$f->{departments}}){
      if($d->{inum} eq $inum){
        return $f->{fakcode};
      }
    }
  }
}

#get the name of a faculty
sub get_org_unit_name
{
	my ($self,$c,$id,$lang)=@_;

	die("PHAIDRA get_org_unit_name ERROR: undefined id") unless(defined($id));
	my $name;
	for my $f (@{$config->{faculties}}){
		if($f->{fakcode} eq $id){
		return $f->{name};
		}
		for my $d (@{$f->{departments}}){
		if($d->{inum} eq $id){
			return $d->{name};
		}
		}
	}
	return $name;
}

#get the full name of the author's affiliation 
sub get_affiliation
{
	my ($self,$c,$inum,$lang)=@_;
	return $self->get_org_unit_name($c,$inum);
}

sub get_org_name
{
	my $self = shift;
	my $c = shift;
	my $lang = shift;
	return $config->{institutionName};	
}

#get all branch of studies
sub get_study_plans
{
	my ($self,$c, $lang) = @_;

	my @values = ();
	
	push @values,{value => 1, name=> 'Study 1'};
	push @values,{value => 2, name=> 'Study 2'};
	return \@values;
}

#get studies
sub get_study
{
	my $self = shift;
	my $c = shift;
	my $id = shift;
	my $index = shift;
	my $lang = shift;

	my @values = ();

	my $taxonnr = undef;	
	$taxonnr = @$index if(defined($index));

	if(!defined($index->[0]) && defined($id))
	{
		push @values,{value=>'001',name=>'001'} if($id eq '1');
		push @values,{value=>'002',name=>'002'} if($id eq '1');
		push @values,{value=>'003',name=>'003'} if($id eq '2');
	}
	elsif($taxonnr eq '1')
	{
		if($index->[0] eq '001')
		{
			push @values,{value=>'0011',name=>'0011'};
			push @values,{value=>'0012',name=>'0012'};
			push @values,{value=>'0013',name=>'0013'};
		}
		elsif ($index->[0] eq '002')
		{
			push @values,{value=>'0021',name=>'0021'};
            push @values,{value=>'0022',name=>'0022'};
            push @values,{value=>'0023',name=>'0023'};
		}
	}
	return \@values;
}

#get the name of a study
sub get_study_name
{
	my $self = shift;
	my $c = shift;
	my $id = shift;
	my $index = shift;
	my $lang = shift;

	my $taxonnr = @$index;
	my $name = '';
	if($taxonnr eq '1')
	{
		$name =  "Study 3" if($index->[0] eq '003');
	}
	elsif($taxonnr eq '2')
	{
		CASE:
		{
			$index->[1] eq '0011' && do {$name = 'Study 1-1'; last CASE;};
			$index->[1] eq '0012' && do {$name = 'Study 1-2'; last CASE;};
			$index->[1] eq '0013' && do {$name = 'Study 1-3'; last CASE;};
			$index->[1] eq '0021' && do {$name = 'Study 2-1'; last CASE;};
      $index->[1] eq '0022' && do {$name = 'Study 2-2'; last CASE;};
      $index->[1] eq '0023' && do {$name = 'Study 2-3'; last CASE;};
		}
	}
	return $name;
}

#all staff positions at the university
sub get_pers_funktions
{
	my ($self,$c, $lang) = @_;

	my $functions;
	push @$functions, {code => 'func1',name => 'func1'};
	push @$functions, {code => 'func2',name => 'func2'};
	push @$functions, {code => 'func3',name => 'func3'};
	
    return $functions;
}

#get the name of a staff position
sub get_pers_funktion_name
{
  my ($self,$c,$code, $lang) = @_;

  die("undefined code for perfsunk") unless(defined($code));

	return 'func1' if($code eq 'func1');
	return 'func2' if($code eq 'func2');
	return 'func3' if($code eq 'func3');
}

#get user data at the login
sub get_user_data
{
	my ($self,$c) = @_;
	
	my ($fname,$lname);
	my @inums = ();
	my @fakcodes = ();

  	for my $user (@{$config->{users}}){
		if($user->{username} eq $c->session->{username}){
			$fname = $user->{firstname};
			$lname = $user->{lastname};
			push @fakcodes, $user->{fakcode};
			push @inums, $user->{inum};
			last;
    	}
	}

	return $fname,$lname,\@inums,\@fakcodes;
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

=head2 searchUser

search a user

TODO: remove old example users

=cut

sub search_user
{
	my ($self,$c,$searchstring) = @_;

	my @persons = ();
  for my $user (@{$config->{users}}){
	  push @persons, {
      uid => $user->{username},
      type => '',
      value => $user->{firstname}.' '.$user->{lastname},
    };
  }
	my $hits=@persons;
	return \@persons,$hits;
} 

# get groups of a user
sub get_users_groups
{
	my ($self, $c, $username)= @_;

	my $groups = get_groups_col();

	my $user_groups = $groups->find({"owner" => $username});
	my $active_group_name;
	my @grps = ();
	while (my $doc = $user_groups->next) {
		$active_gid = $doc->{'groupid'};
        $active_group_name = $doc->{'name'};		
    	push @grps, { gid => $doc->{'groupid'}, group_name => $doc->{'name'} };
	}

	return \@grps, $active_group_name, $active_gid;
}

#get Members of a group
sub get_group
{
	my ($self,$c,$gid) = @_;
	
	my $groups = get_groups_col();

	my $g = $groups->find_one({"groupid" => $gid});	

	my @members = ();
	for my $m (@{$g->{members}}){
		push (@members, { member_id => $m, group_member => $self->get_group_member_name($c, $m) });
	}

    my $count = @members;
	return \@members,$count;	
}

sub get_group_member_name
{
	my($self,$c,$username) = @_;

	die("Internal error: undefined username") unless(defined($username));

	$username = lc($username);
        
    return $self->get_mame($c,$username);       
}

sub add_group_member
{
  	my ($self, $c, $gid, $uid)= @_;
	
	my $groups = get_groups_col();

  	# check if not already there
  	my $g = $groups->find_one({"groupid" => $gid});	

  	my @members = ();
	for my $m (@{$g->{members}}){
		return if $m eq $uid;
	}

	$groups->update({"groupid" => $gid}, {'$push' => {'members' => $uid}, '$set' => {"updated" => time}});

	return;
}
 
sub create_group
{
	my ($self, $c, $groupname, $username)= @_;

  	die ("Internal error: undefined groupname") unless (defined ($groupname));
  	die ("Internal error: undefined username") unless (defined ($username));

  	my $groups = get_groups_col();

	my $ug = Data::UUID->new;
	my $bgid = $ug->create();
	my $gid = $ug->to_string($bgid);
  	my @members = ();
  	$groups->insert({
    	"groupid" => $gid,
    	"owner" => $username,
    	"name" => $groupname,
    	"members" => \@members,
    	"created" => time,
    	"updated" => time
  	});
  
  	return $gid; 
}

sub remove_group_member
{
	my ($self,$c,$gid,$uid)=@_;
	die("Internal error: undefined glid")unless(defined($gid));
	die("Internal error: undefined uid")unless(defined($uid));

	my $groups = get_groups_col();	
	$groups->update({"groupid" => $gid}, {'$pull' => {'members' => $uid}, '$set' => {"updated" => time} });

	return;      
}

sub delete_group
{
	my ($self, $c, $gid) = @_;

	my $groups = get_groups_col();
  	my $g = $groups->remove({"groupid" => $gid});	

  	return;
}

1;
