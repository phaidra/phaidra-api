package Phaidra::Directory::Univie;

use strict;
use warnings;
use v5.10;
use Mojo::JSON;
use DBI;
use base 'Phaidra::Directory';


sub connect_db()
{
	my $self = shift;
	my $c = shift;			
   	my $dbh = DBI->connect($c->app->config->{directory}->{connect_string}, $c->app->config->{directory}->{username}, $c->app->config->{directory}->{password}) or return $self->db_error_handler($c, $DBI::errstr);
    return $dbh;
}

sub db_error_handler {
	
	my $c = shift;	
	my $err = shift;
	
	my $res = { alerts => [], status => 500 };
	unshift @{$res->{alerts}}, { type => 'danger', msg => $err };
	
	return $res;
}

sub _init {
	# this is the app config
	my $self = shift;
	my $mojo = shift;
	my $config = shift;

	return $self;
}

# usage in controller $self->app->directory->get_name($self, 'hudakr4'); 
sub get_name {
	
	my $self = shift;
	my $c = shift;
	my $username = shift;    
	
	$username = lc($username);

	my $dbh = $self->connect_db($c);
	my ($ss,$sth,$fname,$lname,$name) = (undef,undef,undef,undef,undef);

	if($username=~m/^a?\d{7}$/i)
    {
		$ss = qq/SELECT vorname,zuname FROM unet.unet WHERE username=RPAD(?,8)/;
		$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->execute($username) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->bind_columns(undef, \$fname, \$lname) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->fetch();
		$name = $fname.' '.$lname;
    }
    else
    {
		$ss = qq/SELECT pkey,RTRIM(type) FROM pers.user_main WHERE username=RPAD(?,8)/;
		$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
	    $sth->execute($username) or return $self->db_error_handler($c, $dbh->errstr);
		my ($pkey,$type);
		$sth->bind_columns(undef, \$pkey, \$type) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->fetch();
		return undef if(!defined($type));
	
        if($type eq 'PERS' || $type eq 'EDVZ')
        {
			$ss = qq/SELECT vorname,zuname,titel_vorne,titel_hinten FROM pers.persstam WHERE pkey=?/;
			$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
	        $sth->execute($pkey) or return $self->db_error_handler($c, $dbh->errstr);
			my ($titleV,$titleH);
			$sth->bind_columns(undef, \$fname, \$lname, \$titleV, \$titleH) or return $self->db_error_handler($c, $dbh->errstr);
			$sth->fetch();
			$name = $fname.' '.$lname;
        }
        elsif($type eq 'LIGHT')
        {
			$ss = qq/SELECT vorname,zuname,titel FROM pers.lights WHERE username=RPAD(?,8)/;
			$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
	        $sth->execute($username) or return $self->db_error_handler($c, $dbh->errstr);
			my $title;
			$sth->bind_columns(undef, \$fname, \$lname,\$title) or return $self->db_error_handler($c, $dbh->errstr);
			$sth->fetch();
			$name = $fname.' '.$lname;
        }
        else
        {
            $c->app->log->error("Unknown type: $type");
        }
    }
	$sth->finish;
    undef $sth;
	$name =~ s/\s+$//g ;
    $name =~ s/^\s+//g ;
	return $name;
}

sub get_email {
	
	my $self = shift;
	my $c = shift;
	my $username = shift;

	my $email = undef;
	$username = lc($username);

	if($username=~m/^a\d{7}$/i)
	{
		$email = "$username\@unet.univie.ac.at";
	}
	elsif($username=~m/^\d{7}$/)
    {
    	$email = "a$username\@unet.univie.ac.at";
	}
    else
    {
		my $dbh = $self->connect_db($c);
		my $ss = qq/SELECT email FROM pers.canonical_email WHERE username=RPAD(?,8)/;
		my $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->execute($username) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->bind_columns(undef, \$email) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->fetch();
		$email .= '@univie.ac.at' if defined($email);	        
		$sth->finish;
	    undef $sth;
    }
    return $email;
}

# getFaculties
# getDepartments
sub get_org_units {
	
	my $self = shift;
	my $c = shift;
	my $parent_id = shift; # undef if none
	my $lang = shift;
	
	unless(defined($parent_id)){
		my $dbh = $self->connect_db($c);
		my @values = ();
	
        my ($name1col, $name2col)=('name1', 'name2');
        if($lang eq 'en')
        {
        	($name1col, $name2col)=('name1_e', 'name2_e');
        }
        my $ss=qq/
        	SELECT DISTINCT RTRIM(lj.inum), LTRIM(lj.$name1col || ' ' || lj.$name2col)
        	FROM pers.instic li
        	INNER JOIN pers.instic lj
        	ON lj.inum = RPAD('A' || li.fakcode, 6)
        	WHERE li.aktiv = 'A'
        	ORDER BY 1
        /;
        my $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
        $sth->execute() or return $self->db_error_handler($c, $dbh->errstr);

        push @values, { value => '-1', name => $c->l('Please choose...') };
        push @values, { value => 'A0', name => $c->l('Support facilities') };        
        my $rows = $sth->fetchall_arrayref;   
        foreach my $row (@{$rows})
        {
             push @values, { value => $row->[0], name => "$row->[0]: $row->[1]"};
        }


		$sth->finish;
        undef $sth;

		return { org_units => \@values };	
		
	}else{
		
		my $dflg= ($parent_id =~ m#^\d+$#) ? 0 : 1;

  		
=begin comment

see #2062:
fakcode='[A391  ]' throws an DBD exception because that's not a valid
number that can be used for fakcode.  That's no surprise since fakcode
is defined as NUMBER.

=end comment
=cut
		# fakcode could be "A391" or even "[A391  ]"
  		$parent_id=~ s/^\[?A//;
  		$parent_id=~ s/\s*\]?$//;

  		my $entries=undef;
  		my ($name1col, $name2col)= ('name1', 'name2');
  		if ($lang eq 'en')
  		{
    		($name1col, $name2col)= ('name1_e', 'name2_e');
  		}
  		my $values= undef;
	
  		if ($parent_id ne '-1')
  		{
    		my $dbh = $self->connect_db($c);
    		my $ss= qq/
				SELECT RTRIM(inum),LTRIM($name1col || ' ' || $name2col) 
				  FROM pers.instic
				 WHERE fakcode=? AND aktiv='A' ORDER BY inum
				/;

		    push @$values, { 
		    	value => '-1', 
		    	name => $c->l('(whole organisational unit)')		    	
		    };
		    my $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
		    $sth->execute($parent_id) or return $self->db_error_handler($c, $dbh->errstr);
		    my ($child_id, $name);
		    $sth->bind_columns(undef, \$child_id, \$name) or return $self->db_error_handler($c, $dbh->errstr);

		    while ($sth->fetch())
		    {
		      push @$values, {value => $child_id, name => $child_id.': '.$name}; 
		    }
		    $sth->finish;
  		}
 
  		return { org_units => $values };
	}
	
}

# getFacultyId
sub get_parent_org_unit_id {
	
	my $self = shift;
	my $c = shift;
	my $child_id = shift;
	
	$child_id = $child_id." "x(6-length($child_id));

	my $dbh = $self->connect_db($c);
	my $ss = qq/SELECT fakcode FROM pers.instic WHERE inum=?/;
	my $sth=$dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
    $sth->execute($child_id) or return $self->db_error_handler($c, $dbh->errstr);
	my $parentid;
	$sth->bind_columns(undef, \$parentid) or return $self->db_error_handler($c, $dbh->errstr);
	$sth->fetch();

    if($sth->rows < 1)
    {
	  # die("Internal error: undefined fakcode for inum $child_id");
	  # don't die here, otherwise the owner does not have a chance
	  # to change a fakcode that is no longer valid.  This fakcode
      # is not shown in the output anyway, so maybe this should
      # be reported somehow:
      $parentid= "{unknown child_id=[$child_id]}";
	}

    $sth->finish;
    undef $sth;
    return $parentid;
}

# getFacultyName
# getDepartmentName
sub get_org_unit_name {
	
	my $self = shift;
	my $c = shift;
	my $unit_id = shift;
	my $lang = shift;
	
	$unit_id=~s/^A//;

    # Spezialfall
    if($unit_id eq '0')
    {
    	return $c->l('Support facilities');
    }

    my ($name1col, $name2col)=('name1', 'name2');
    if($lang eq 'en')
    {
    	($name1col, $name2col)=('name1_e', 'name2_e');
    }

	my $dbh = $self->connect_db($c);
	my $ss = qq/SELECT LTRIM($name1col || ' ' || $name2col) FROM pers.instic WHERE inum=RPAD(?,6)/;
	my $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
    $sth->execute('A'.$unit_id) or return $self->db_error_handler($c, $dbh->errstr);
	my $name;
	$sth->bind_columns(undef, \$name) or return $self->db_error_handler($c, $dbh->errstr);
	$sth->fetch();
	$sth->finish;
    undef $sth;
	return undef if(!defined($name));
	return $name;
}

# getAuthorInstitutionName
# getAuthorInstitutionNameNoCtx
sub get_affiliation {
	
	my $self = shift;
	my $c = shift;
	my $unit_id = shift;
	my $lang = shift;
	
	my $unit_name = $self->get_org_unit_name($c, "A".$unit_id);
	my $parent_unit_id = $self->get_parent_org_unit_id($c, "A".$unit_id);
	my $parent_unit_name = '';
	if($parent_unit_id ne $unit_id){
		$parent_unit_name = $self->getFacultyName($c, $parent_unit_id);
	}
			
	if($parent_unit_name ne ''){
		return $unit_name.', '.$parent_unit_name.', '. $self->get_org_name($c);
	}elsif($unit_name ne ''){
		return $unit_name.', '. $self->get_org_name($c);
	}else{
		return $self->get_org_name($c);
	}
	
}

# getInstitutionName
sub get_org_name {
	
	my $self = shift;
	my $c = shift;
	my $lang = shift;
	
	return $c->l('University of Vienna');
}

# uni specific
sub get_study_plans {
	
	my $self = shift;
	my $c = shift;
	my $lang = shift;
	
	my $dbh = $self->connect_db($c);

	my @values = ();
	
	my $ss = qq/SELECT RTRIM(inum),name2 FROM pers.instic WHERE inum LIKE 'A85%'/;
	my $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
    $sth->execute() or return $self->db_error_handler($c, $dbh->errstr);
    my ($inum,$name);
    $sth->bind_columns(undef, \$inum, \$name) or return $self->db_error_handler($c, $dbh->errstr);
    while($sth->fetch())
	{
		my $spl=$inum;
        $spl=~s/^A85//;
		push @values, {value => $spl, name => "SPL $spl: ".$name};
	}
	$sth->finish;
    undef $sth;
    
	return \@values;
}

# uni specific        
sub get_study {
	
	my $self = shift;
	my $c = shift;
	my $id = shift;
	my $index = shift;
	my $lang = shift;
	
	my $dbh = $self->connect_db($c);
    my ($ss,$sth);
    my @values = ();

    my $taxonnr = undef;
    $taxonnr = @$index if(defined($index));

    if(!defined($index->[0]) && defined($id))
    {
    	$ss=qq/SELECT DISTINCT kennzahl1 FROM pers.studien WHERE spl_nr=? /;
        $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
        $sth->execute($id) or return $self->db_error_handler($c, $dbh->errstr);
    }
    elsif($taxonnr eq '1')
    {
        return $self->db_error_handler($c, "Internal error: undefined index1") unless(defined($index->[0]));
        $ss=qq/SELECT DISTINCT kennzahl2 FROM pers.studien WHERE spl_nr=? AND kennzahl1=?/;
        $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
        $sth->execute($id,$index->[0]) or return $self->db_error_handler($c, $dbh->errstr);
    }
	elsif($taxonnr eq '2')
    {
        return $self->db_error_handler($c, "Internal error: undefined index1") unless(defined($index->[0]));
        return $self->db_error_handler($c, "Internal error: undefined index2") unless(defined($index->[1]));
        $ss=qq/SELECT DISTINCT kennzahl3 FROM pers.studien WHERE spl_nr=? AND kennzahl1=? AND kennzahl2=?/;
        $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
        $sth->execute($id,$index->[0],$index->[1]) or return $self->db_error_handler($c, $dbh->errstr);
    }
    else
    {
        $ss=qq/SELECT DISTINCT kennzahl1 FROM pers.studien WHERE spl_nr=0 AND kennzahl1=0 AND kennzahl2=0 AND kennzahl3=0/;
        $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
        $sth->execute() or return $self->db_error_handler($c, $dbh->errstr);
    }
    
    my $code;
    $sth->bind_columns(undef, \$code) or return $self->db_error_handler($c, $dbh->errstr);
    while($sth->fetch())
    {
        push @values,{value=>$code,name=>$code} if($code !~ /^\s*$/);
    }
    $sth->finish;
    undef $sth;
	return \@values;
}

# uni specific
sub get_study_name {
	
	my $self = shift;
	my $c = shift;
	my $id = shift;
	my $index = shift;
	my $lang = shift;
	
	my $dbh = $self->connect_db($c);
    my ($ss,$sth);
    my $taxonnr = @$index;

    if($taxonnr eq '1')
    {
		$ss=qq/SELECT DISTINCT bez_studienvorschrift,von FROM pers.studien WHERE spl_nr=? AND kennzahl1=? ORDER BY von DESC/;
		$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->execute($id,$index->[0]) or return $self->db_error_handler($c, $dbh->errstr);
	}
	elsif($taxonnr eq '2')
	{
		die("Internal error: undefined code2") unless(defined($index->[1]));
		$ss=qq/SELECT DISTINCT bez_studienvorschrift,von FROM pers.studien WHERE spl_nr=? AND kennzahl1=? AND kennzahl2=? ORDER BY von DESC/;
		$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->execute($id,$index->[0],$index->[1]) or return $self->db_error_handler($c, $dbh->errstr);
	}
	elsif($taxonnr eq '3')
	{
		die("Internal error: undefined code2") unless(defined($index->[1]));
		die("Internal error: undefined code3") unless(defined($index->[2]));
		$ss=qq/SELECT DISTINCT bez_studienvorschrift,von FROM pers.studien WHERE spl_nr=? AND kennzahl1=? AND kennzahl2=? AND kennzahl3=? ORDER BY von DESC/;
		$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->execute($id,$index->[0],$index->[1],$index->[2]) or return $self->db_error_handler($c, $dbh->errstr);
	}
	
	my ($name,$von);
	$sth->bind_columns(undef, \$name,\$von) or return $self->db_error_handler($c, $dbh->errstr);
	$sth->fetch();
	$sth->finish;
	undef $sth;
	return $name;
}

# getPersFunk
sub get_pers_funktions {
	
	my $self = shift;
	my $c = shift;
	my $lang = shift;
	
	my $dbh = $c->connect_db($c);

	my $ss = qq/
    	SELECT DISTINCT p.code,pc.description,pc.PRIORITY FROM pers.perfunk p
		INNER JOIN pers.funktc pc ON (p.code = pc.code)
		WHERE p.von < SYSDATE AND p.bis > SYSDATE ORDER BY pc.PRIORITY
	/;

	my $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
	$sth->execute() or return $self->db_error_handler($c, $dbh->errstr);

	my ($code,$description,$priority);
	my @functions = ();
	$sth->bind_columns(undef, \$code, \$description, \$priority) or return $self->db_error_handler($c, $dbh->errstr);
	while ($sth->fetch())
	{
		push @functions, { code => $code, name => $description };
	}
	$sth->finish;
    undef $sth;
    return \@functions;
}
 
# getPersFunkName
sub get_pers_funktion_name {
	
	my $self = shift;
	my $c = shift;
	my $id = shift;
	my $lang = shift;
	
	my $dbh = $self->connect_db($c);

    my $ss = qq/SELECT pf.description FROM pers.funktc pf WHERE pf.code = ?/;

	my $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
	$sth->execute($id) or return $self->db_error_handler($c, $dbh->errstr);

	my ($description);
	$sth->bind_columns(undef, \$description) or return $self->db_error_handler($c, $dbh->errstr);
	$sth->fetch();
	$sth->finish;
	undef $sth;
	return $self->db_error_handler($c, "undefined description for staff function $id") unless(defined($description));
	return $description;
}
  
# getLoginData
sub get_login_data {
	
	my $self = shift;
	my $c = shift;
	my $username = shift;
	
	my $dbh = $self->connect_db($c);
	my ($ss,$sth,$fname,$lname);
	my @inums = ();
	my @fakcodes = ();
	
	#Im Falle der Uni Wien ist der Username (MailboxID,UNet) immer klein - 
	#Name usw. sind die ersten Schritte beim Login - gleich mal den Session USERNAME lc'en :)
	$username = lc($username);

	if($username =~ /^a?\d{7}$/i)
	{
		$ss = qq/SELECT vorname,zuname FROM unet.unet WHERE username=RPAD(?,8)/;
		$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
        $sth->execute($username) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->bind_columns(undef, \$fname,\$lname) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->fetch();
	}
	else
	{
		$ss = qq/SELECT pkey,RTRIM(type) FROM pers.user_main WHERE username=RPAD(?,8)/;
		$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->execute($username) or return $self->db_error_handler($c, $dbh->errstr);
		my ($pkey,$type);
		$sth->bind_columns(undef, \$pkey, \$type) or return $self->db_error_handler($c, $dbh->errstr);
		$sth->fetch();
		return $self->db_error_handler($c, "Internal error: can't determine user type") unless(defined($type));

		if($type eq "PERS" or $type eq "EDVZ")
		{
			$ss=qq/
                        	SELECT p.vorname, p.zuname, RTRIM(i.inum), fakcode
                                FROM pers.persstam p,
                                	pers.dienstverhaeltnis d,
                                        pers.instic i
                                WHERE p.pkey = ?
                                AND d.pkey = p.pkey
                                AND d.eintritt <= SYSDATE
                                AND d.austritt >= SYSDATE
                                AND i.inum = d.inum
				UNION
				SELECT p.vorname, p.zuname, RTRIM(i.inum), fakcode
                                FROM pers.persstam p,
                                        pers.perfunk pf,
                                        pers.instic i
                                WHERE p.pkey = ?
                                AND pf.pkey = p.pkey
                                AND pf.von <= SYSDATE
                                AND pf.bis >= SYSDATE
                                AND i.inum = pf.inum
                                /;
			$sth=$dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
			$sth->execute($pkey, $pkey) or return $self->db_error_handler($c, $dbh->errstr);
			my ($inum, $fakcode);
			$sth->bind_columns(undef, \$fname, \$lname, \$inum, \$fakcode) or return $self->db_error_handler($c, $dbh->errstr);
			while($sth->fetch){
				push @inums, $inum;
				push @fakcodes, $fakcode;
			}
		}
		elsif($type eq 'LIGHT')
		{
			$ss = qq/SELECT vorname,zuname,inum FROM pers.lights WHERE username=RPAD(?,8)/;
			$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
			$sth->execute($username) or return $self->db_error_handler($c, $dbh->errstr);
			my ($inum);
			$sth->bind_columns(undef, \$fname, \$lname,\$inum) or return $self->db_error_handler($c, $dbh->errstr);
			$sth->fetch();
			if(defined($inum) && $inum ne '')
			{
				push @inums,$inum;
				$ss=qq/SELECT fakcode FROM pers.instic WHERE inum=?/;
				$sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
				$sth->execute($inum) or return $self->db_error_handler($c, $dbh->errstr);
				my $fakcode;
				$sth->bind_columns(undef, \$fakcode) or return $self->db_error_handler($c, $dbh->errstr);
				$sth->fetch();
				return $self->db_error_handler($c, "Internal error: undefined faculty for department $inum") if(!defined($fakcode));
				push @fakcodes,$fakcode;				
			}
		}
	}
	$sth->finish;
    undef $sth;
	return $fname,$lname,\@inums,\@fakcodes;
}

sub is_superuser {
	
	my $self = shift;
	my $c = shift;
	my $username = shift;
	
	my $dbh = $self->connect_db($c);
	my $ss = qq/SELECT username FROM pers.phaidra_superusers WHERE username = RPAD(?, 8)/;
    my $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
	$sth->execute($username) or return $self->db_error_handler($c, $dbh->errstr);
	my $dummy;
	$sth->bind_columns(undef, \$dummy) or return $self->db_error_handler($c, $dbh->errstr);
	$sth->fetch;
	$sth->finish;
	undef $sth;
	return defined($dummy);	
}
      
sub is_superuser_for_user {
	
	my $self = shift;
	my $c = shift;
	my $username = shift;
	
	my $dbh = $self->connect_db($c);
	
	my $ss=qq/
                                SELECT RTRIM(u.username)
                                FROM pers.user_main u,
                                     pers.dienstverhaeltnis d
                                WHERE u.pkey = d.pkey
                                AND d.eintritt <= SYSDATE
                                AND d.austritt >= SYSDATE
                                AND u.type IN ('PERS', 'EDVZ')
                                AND u.status='A'
                                AND u.locked='N'
                                AND d.inum IN (
                                                SELECT d.inum
                                                FROM pers.user_main u,
                                                     pers.dienstverhaeltnis d,
                                                     pers.phaidra_superusers p
                                                WHERE u.username = RPAD(?, 8)
                                                AND p.username = u.username
                                                AND p.inum = d.inum
                                                AND u.pkey = d.pkey
                                                AND d.eintritt <= SYSDATE
                                                AND d.austritt >= SYSDATE
                                                AND u.type IN ('PERS', 'EDVZ')
                                                AND u.status='A'
                                                AND u.locked='N'
                                                UNION
                                                SELECT l.inum
                                                FROM pers.user_main u,
                                                     pers.lights l,
                                                     pers.phaidra_superusers p
                                                WHERE u.username = RPAD(?, 8)
                                                AND p.username = u.username
                                                AND l.username = u.username
                                                AND l.inum = p.inum
                                                AND u.type = 'LIGHT'
                                                AND u.status = 'A'
                                                AND u.locked='N'
                                )
                                UNION
                                SELECT RTRIM(u.username)
                                FROM pers.user_main u,
                                     pers.lights l
                                WHERE u.username = l.username
                                AND u.type='LIGHT'
                                AND u.status='A'
                                AND u.locked='N'
                                AND l.inum IN (
						SELECT d.inum
                                                FROM pers.user_main u,
                                                     pers.dienstverhaeltnis d,
                                                     pers.phaidra_superusers p
                                                WHERE u.username = RPAD(?, 8)
                                                AND p.username = u.username
                                                AND p.inum = d.inum
                                                AND u.pkey = d.pkey
                                                AND d.eintritt <= SYSDATE
                                                AND d.austritt >= SYSDATE
                                                AND u.type IN ('PERS', 'EDVZ')
                                                AND u.status='A'
                                                AND u.locked='N'
                                                UNION
                                                SELECT l.inum
                                                FROM pers.user_main u,
                                                     pers.lights l,
                                                     pers.phaidra_superusers p
                                                WHERE u.username = RPAD(?, 8)
                                                AND p.username = u.username
                                                AND l.username = u.username
                                                AND l.inum = p.inum
                                                AND u.type = 'LIGHT'
                                                AND u.status = 'A'
                                                AND u.locked='N'
                                )
                                UNION
                                SELECT RTRIM(u.username)
                                FROM pers.user_main u,
                                     pers.dienstverhaeltnis d,
                                     pers.instic i
                                WHERE u.pkey = d.pkey
                                AND d.inum = i.inum
                                AND d.eintritt <= SYSDATE
                                AND d.austritt >= SYSDATE
                                AND u.type IN ('PERS', 'EDVZ')
                                AND u.status='A'
                                AND u.locked='N'
                                AND i.fakcode IN (
							SELECT i.fakcode
                                                FROM pers.user_main u,
                                                     pers.dienstverhaeltnis d,
                                                     pers.instic i,
                                                     pers.phaidra_superusers p
                                                WHERE u.username = RPAD(?, 8)
                                                AND p.username = u.username
                                                AND p.fakcode = i.fakcode
                                                AND u.pkey = d.pkey
                                                AND d.inum = i.inum
                                                AND d.eintritt <= SYSDATE
                                                AND d.austritt >= SYSDATE
                                                AND u.type IN ('PERS', 'EDVZ')
                                                AND u.status='A'
                                                AND u.locked='N'
                                                UNION
                                                SELECT i.fakcode
                                                FROM pers.user_main u,
                                                     pers.lights l,
                                                     pers.phaidra_superusers p,
                                                     pers.instic i
                                                WHERE u.username = RPAD(?, 8)
                                                AND p.username = u.username
                                                AND l.username = u.username
                                                AND i.inum = l.inum
                                                AND p.fakcode = i.fakcode
                                                AND u.type = 'LIGHT'
                                                AND u.status = 'A'
                                                AND u.locked='N'
                                )
                                UNION
                                SELECT RTRIM(u.username)
                                FROM pers.user_main u,
                                     pers.lights l,
                                     pers.instic i
                                WHERE u.username = l.username
                                AND i.inum = l.inum
                                AND u.type='LIGHT'
                                AND u.status='A'
                                AND u.locked='N'
                                AND i.fakcode IN (
							SELECT i.fakcode
                                                FROM pers.user_main u,
                                                     pers.dienstverhaeltnis d,
                                                     pers.instic i,
                                                     pers.phaidra_superusers p
                                                WHERE u.username = RPAD(?, 8)
                                                AND p.username = u.username
                                                AND p.fakcode = i.fakcode
                                                AND u.pkey = d.pkey
                                                AND d.inum = i.inum
                                                AND d.eintritt <= SYSDATE
                                                AND d.austritt >= SYSDATE
                                                AND u.type IN ('PERS', 'EDVZ')
                                                AND u.status='A'
                                                AND u.locked='N'
                                                UNION
                                                SELECT i.fakcode
                                                FROM pers.user_main u,
                                                     pers.lights l,
                                                     pers.phaidra_superusers p,
                                                     pers.instic i
                                                WHERE u.username = RPAD(?, 8)
                                                AND p.username = u.username
                                                AND l.username = u.username
                                                AND i.inum = l.inum
                                                AND p.fakcode = i.fakcode
                                                AND u.type = 'LIGHT'
                                                AND u.status = 'A'
                                                AND u.locked='N'
                                )
                        /;
	my $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
	$sth->execute( $username, $username, $username, $username, $username, $username, $username, $username ) or return $self->db_error_handler($c, $dbh->errstr);
	my ($knecht,$users) = (undef,undef);
	$sth->bind_columns(undef, \$knecht) or return $self->db_error_handler($c, $dbh->errstr);
	while($sth->fetch)
	{
		push @$users, $knecht;
	}
	$sth->finish;
	undef $sth;
	return $users;
}

sub search_user {
	
	my $self = shift;
	my $c = shift;
	my $query = shift;
	
	my $dbh = $self->connect_db($c);

	#Eingabe splitten
    my @searchstrings = split(/ /,$query);

    my $num_expressions = @searchstrings;

	my ($i,$persons) = (undef,undef);
	my @pers_OR1 = ();
	my @pers_OR2 = ();
	my @pers_light_OR1 = ();
	my @pers_light_OR2 = ();
	my @unet_OR1 = ();
	my @unet_OR2 = ();
	my @search_data1 = ();
	my @search_data2 = ();

	# Sehr performante Query mit Schmaeh (http://www.iherve.com/oracle/case_ins.htm)
	for ($i = 0; $i < $num_expressions; $i++)
	{
     	my @searchstring_arr = split(//, $searchstrings[$i]);
       	push @search_data1, ($searchstrings[$i],(lc $searchstring_arr[0]).'%',(uc $searchstring_arr[0]).'%',(uc $searchstrings[$i])."%");
       	push @search_data2, ($searchstrings[$i],(lc $searchstring_arr[0]).(lc $searchstring_arr[1]).'%',(lc $searchstring_arr[0]).(uc $searchstring_arr[1]).'%',(uc $searchstring_arr[0]).(lc $searchstring_arr[1]).'%',(uc $searchstring_arr[0]).(uc $searchstring_arr[1]).'%',(uc $searchstrings[$i])."%");
       	push @pers_OR1, "(u.username=RPAD(?,8) OR ((p.zuname LIKE ? OR p.zuname LIKE ?) AND upper(p.zuname) LIKE ?))";
       	push @pers_light_OR1, "(l.username=RPAD(?,8)OR ((l.zuname LIKE ? OR l.zuname LIKE ?) AND upper(l.zuname) LIKE ?))";
       	push @unet_OR1, "(u.username=? OR ((u.zuname LIKE ? OR u.zuname LIKE ? OR u.zuname LIKE ? OR u.zuname LIKE ?) AND UPPER(u.zuname) LIKE ?))";
       	push @pers_OR2, "(u.username=RPAD(?,8) OR ((p.vorname LIKE ? OR p.vorname LIKE ?) AND upper(p.vorname) LIKE ?))";
       	push @pers_light_OR2, "(l.username=RPAD(?,8)OR ((l.vorname LIKE ? OR l.vorname LIKE ?) AND upper(l.vorname) LIKE ?))";
       	push @unet_OR2, "(u.username=? OR ((u.vorname LIKE ? OR u.vorname LIKE ? OR u.vorname LIKE ? OR u.vorname LIKE ?) AND UPPER(u.vorname) LIKE ?))";
    }

	my ($pers_search,$pers_ext_search,$pers_light_search,$unet_search) = (undef,undef,undef,undef);
	if ($num_expressions > 1)
	{
		$pers_search = '('.join(' OR ' , @pers_OR1).') AND ('.join(' OR ' , @pers_OR2).')';
		$pers_light_search = '('.join(' OR ' , @pers_light_OR1).') AND ('.join(' OR ' , @pers_light_OR2).')';
		$unet_search = '('.join(' OR ' , @unet_OR1).') AND ('.join(' OR ' , @unet_OR2).')';
	}
	else
	{	
		$pers_search = $pers_OR1[0]." OR ".$pers_OR2[0];
		$pers_light_search = $pers_light_OR1[0]." OR ".$pers_light_OR2[0];
		$unet_search = $unet_OR1[0]." OR ".$unet_OR2[0];
	}

	my $ss=qq/
                   SELECT * FROM
                   (
                        SELECT RTRIM(u.username), p.vorname, p.zuname, 'Mailbox', 1
                        FROM pers.user_main u,
                             pers.persstam p
                        WHERE u.pkey = p.pkey
                        AND u.type IN ('EDVZ', 'PERS')
                        AND u.status='A'
                        AND ($pers_search)
                        UNION
                        SELECT RTRIM(u.username), l.vorname, l.zuname, 'Light', 3
                        FROM pers.user_main u,
                             pers.lights l
                        WHERE u.username = l.username
                        AND u.type = 'LIGHT'
                        AND u.status='A'
                        AND ($pers_light_search)
                        UNION
                        SELECT RTRIM(u.username), u.vorname, u.zuname, 'u:net', 4
                        FROM unet.unet u
                        WHERE ($unet_search)
                        AND u.locked='N'
                        AND u.geloescht='N'
                        AND u.angemeldet='J'
                    )
                    ORDER BY 5, 2
                /;

	my $sth = $dbh->prepare($ss) or return $self->db_error_handler($c, $dbh->errstr);
    $sth->execute(
     	@search_data1, @search_data1,
       	@search_data1, @search_data1,
       	@search_data2, @search_data2
    ) or return $self->db_error_handler($c, $dbh->errstr);

    my ($username, $vorname, $zuname, $type, $dummyorder);
	$sth->bind_columns(undef, \$username, \$vorname, \$zuname, \$type, \$dummyorder) or return $self->db_error_handler($c, $dbh->errstr);

	if($sth->rows <= 50)
	{
		while($sth->fetch)
		{
			my %zeile=();

			$zeile{'uid'}=$username;
			$zeile{'type'}=$type;
			if($type eq 'u:net')
			{
				($vorname, $zuname)=unet_format($vorname, $zuname);
			}
			$zeile{'value'}="$zuname, $vorname";
			push @$persons, \%zeile;
		}
	}
	
	my $hits = $sth->rows;
	$sth->finish;
	undef $sth;
	return $persons, $hits;
}        

1;
__END__
