package PhaidraAPI::Controller::Terms;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';

our $classification_ns = "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/classification";

our %namespaces = (
	"http://phaidra.univie.ac.at/XML/metadata/V1.0" => undef,
	"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0" => ['2','3','6','21'],  	
	"http://phaidra.univie.ac.at/XML/metadata/extended/V1.0" => ['31','36','38','40'], 
	"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/entity" => undef,
	"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/requirement" => ['4','5'],
	"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational" => ['10','11','12','14','15','16'],
	"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/annotation" => undef,
	$classification_ns => ['9','18','20','26','27','28','29','30','33','34','35','39','41','42','43'],
	"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/organization" => ['17'],
	"http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0" => ['22','23','24','25'],
	"http://phaidra.univie.ac.at/XML/metadata/provenience/V1.0" => ['3','24'],
	"http://phaidra.univie.ac.at/XML/metadata/provenience/V1.0/entity" => undef,
	"http://phaidra.univie.ac.at/XML/metadata/digitalbook/V1.0" => ['32'],
	"http://phaidra.univie.ac.at/XML/metadata/etheses/V1.0" => undef
);

sub label {
    my $self = shift;  
    
    my $res = { alerts => [], status => 200 };	

	my $uri = $self->param('uri');
	my %labels;
	
	my $r = $self->_parse_uri($uri);
	if($r->{status} != 200){
		$self->render(json => $res, status => $res->{status}) ;		
		return;
	}
	
	my $veid;	
	if($r->{tid}){
		my $ss = qq/SELECT veid FROM taxon_vocentry WHERE tid = (?) AND preferred = 1;/;
		my $sth = $self->app->db_metadata->prepare($ss) or $self->app->log->error($self->app->db_metadata->errstr);
		$sth->execute($r->{tid});
		$sth->bind_columns(undef, \$veid);
		$sth->fetch;
		$sth->finish;
        undef $sth;
	}else{
		$veid = $r->{veid};	
	}
	
	my $ss = qq/SELECT entry, isocode FROM vocabulary_entry WHERE vid = (?) AND veid = (?);/;
	my $sth = $self->app->db_metadata->prepare($ss) or $self->app->log->error($self->app->db_metadata->errstr);
	$sth->execute($r->{vid}, $veid);
		
	my $entry; # value label (eg 'Wood-engraver')
	my $isocode; # 2 letter isocode defining language of the entry
			
	$sth->bind_columns(undef, \$entry, \$isocode);
			
	# fetching data using hash, so that we quickly find the place for the entry but later ... [x] 
	while($sth->fetch) {				
		$labels{$isocode} = $entry; # this should always contain another language for the same entry								
	}
	$sth->finish;
    undef $sth;
	
	$self->app->log->debug("Resolved: ".$self->app->dumper(\%labels));

	$res->{labels} = \%labels;
	$self->render(json => $res , status => $res->{status}) ;
}

sub _parse_uri {
	
	my $self = shift;
	my $uri = shift;
	
	my $res = { alerts => [], status => 200 };	
	
	my $xmlns;
	my $vid;
	my $id;

	#$self->app->log->debug("uri=$uri");
	foreach my $ns (keys %namespaces){
		
		#$self->app->log->debug("xmlns=$ns");
		
		# keep $ at the end otherwise eg ns
		# http://phaidra.univie.ac.at/XML/metadata/lom/V1.0
		# will be matched even if the sent namespace is
		# http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/classification
		$uri =~ m/($ns)\/voc_(\d+)\/(\w+)\/?$|($ns)\/voc_(\d+)\/?$|($ns)\/?$/;
		
		#$self->app->log->debug("1=$1 2=$2 3=$3 4=$4 5=$5 6=$6");
		
		if($3){
			$xmlns = $1;
			$vid = $2;
			$id = $3;
		}
		
		if($5){
			$xmlns = $4;
			$vid = $5;
		}
		
		if($6){
			$xmlns = $6;			
		}
		
		last if $xmlns eq $ns;
	}
		
	# $self->app->log->debug("xmlns=$xmlns vid=$vid id=$id");
		
	unless($xmlns){
		push @{$res->{alerts}}, { type => 'danger', msg => 'Cannot parse URI' };
		$res->{status} = 400;
		return $res;
	}
	
	if($vid){
		unless($vid ~~ $namespaces{$xmlns}){
			push @{$res->{alerts}}, { type => 'danger', msg => "The specified vocabulary ($vid) is not allowed in the specified namespace ($xmlns)" };
			$res->{status} = 400;
			return $res;
		}
	}
		
	# if this is a classification get the classification id
	if( $vid ~~ $namespaces{$classification_ns} ){		
		# get classification id
		my $cid;
		my $ss = qq/SELECT cid FROM classification_db WHERE vid = (?);/;
		my $sth = $self->app->db_metadata->prepare($ss) or $self->app->log->error($self->app->db_metadata->errstr);
		$sth->execute($vid);
		$sth->bind_columns(undef, \$cid);
		$sth->fetch;	
		$sth->finish;
    	undef $sth;	
		unless($cid){		
			push @{$res->alerts}, { type => 'danger', msg => 'Cannot find classification id.' };
			$res->{status} = 500;
			return $res;
		}
		$res->{cid} = $cid;
	}
	
	if($id){
		# id is vocabulary entry id in case of vocabularies and taxon id in case of classifications
		if($res->{cid}){		
			$res->{tid} = $id;
		}else{
			$res->{veid} = $id;
		}
	}
	
	if($vid){
		$res->{vid} = $vid;
	}
	
	$res->{xmlns} = $xmlns;
	
	$self->app->log->debug("Parsing uri: ".$self->app->dumper($res));
	
	return $res;
}

sub children {
    my $self = shift;  
    
    my $res = { alerts => [], status => 200 };	

	my $uri = $self->param('uri');
	my %children;
	my @children;
	
	my $r = $self->_parse_uri($uri);
	if($r->{status} != 200){
		$self->render(json => $r, status => $r->{status}) ;		
		return;
	}
	
	if($r->{xmlns} ne $classification_ns){		
		push @{$res->{alerts}}, { type => 'danger', msg => 'Children can be obtained only for classifications.' };
		$res->{status} = 400;
		return $res;
	}
	
	unless($r->{cid}){
		# no vocabulary id specified, return all the classification ids
		my ($vid, $entry, $isocode);
		my $ss = "SELECT c.vid, ve.entry, ve.isocode FROM classification_db c LEFT JOIN vocabulary_entry ve on c.veid = ve.veid;";
		my $sth = $self->app->db_metadata->prepare($ss) or $self->app->log->error($self->app->db_metadata->errstr);
		$sth->execute();
		$sth->bind_columns(undef, \$vid, \$entry, \$isocode);		
		my %classes;
		my %isocodes;
		while($sth->fetch){
			$classes{$vid}{$isocode} = $entry;
			$isocodes{$isocode} = 1;
		}
		$sth->finish;
    	undef $sth;

    	# create an array (just as in the metadata tree)
    	my @classes;
    	foreach my $vid (keys %classes){
    		my %class;
    		$class{uri} = "$classification_ns/voc_$vid";
    		foreach my $iso (keys %isocodes){
    			 $class{$iso} = $classes{$vid}{$iso};
    		}
    		push @classes, \%class;
    	}
    	
		$res->{terms} = \@classes;
		$self->render(json => $res, status => $res->{status});
		return;
	}
		
	# get children
	my ($child_tid, $entry, $isocode, $preferred, $upstream_identifier, $term_id);
	my %isocodes;	
	my $ss = "SELECT t.tid, t.upstream_identifier, tv.term_id, ve.entry, ve.isocode, tv.preferred FROM taxon t LEFT JOIN taxon_vocentry tv ON tv.tid = t.tid LEFT JOIN vocabulary_entry ve ON tv.veid = ve.veid WHERE t.cid = (?)";
	if($r->{tid}){
		$ss .= "AND t.tid_parent = (?);";
	}else{
		$ss .= "AND t.tid_parent IS NULL;";
	}
	my $sth = $self->app->db_metadata->prepare($ss) or $self->app->log->error($self->app->db_metadata->errstr);
	if($r->{tid}){
		$sth->execute($r->{cid}, $r->{tid});
	}else{
		$sth->execute($r->{cid});
	}
	$sth->bind_columns(undef, \$child_tid, \$upstream_identifier, \$term_id, \$entry, \$isocode, \$preferred);
	while($sth->fetch){
		
		$children{$child_tid}{upstream_identifier} = $upstream_identifier;
		
		if($preferred){
			$children{$child_tid}{preferred}{$isocode} = $entry;
			$children{$child_tid}{preferred}{term_id} = $term_id;						
		}else{
			$children{$child_tid}{nonpreferred}{$term_id}{$isocode} = $entry;
		}	
			
		$isocodes{$isocode} = 1;
	}		
	$sth->finish;
    undef $sth;
    
    #$self->app->log->debug("ch: ".$self->app->dumper(\%children));
    
    # create an array (just as in the metadata tree)
    foreach my $tid (keys %children){
    	my %child;
    	$child{uri} = $r->{xmlns}.'/voc_'.$r->{vid}.'/'.$tid;    	
    	$child{upstream_identifier} = $children{$tid}{upstream_identifier};        	
    	foreach my $iso (keys %isocodes){
    		if($children{$tid}{preferred}{$iso}){    		
    			$child{$iso} = $children{$tid}{preferred}{$iso};
    			$child{term_id} = $children{$tid}{preferred}{term_id};
    		}    		    			
    	}
    	if($children{$tid}{nonpreferred}){
    		foreach my $termid (keys %{$children{$tid}{nonpreferred}}){
    			my %ch;
    			$ch{term_id} = $termid;
    			foreach my $iso (keys %{$children{$tid}{nonpreferred}{$termid}}){
   					$ch{$iso} = $children{$tid}{nonpreferred}{$termid}{$iso};
    			}
    			push @{$child{nonpreferred}}, \%ch;
    		}    		
    	}
    	push @children, \%child;
    }
    
    #$self->app->log->debug("ch: ".$self->app->dumper(\@children));
    
	$res->{terms} = \@children;
	$self->render(json => $res, status => $res->{status});
}

sub search {
	
    my $self = shift;  
    
    my $res = { alerts => [], status => 200 };	

	my $q = $self->param('q');
	
	# get a list of all classifications
	my ($cid, $vid, $entry, $isocode);
	my $ss = "SELECT c.cid, c.vid, ve.entry, ve.isocode FROM classification_db c LEFT JOIN vocabulary_entry ve on c.veid = ve.veid;";
	my $sth = $self->app->db_metadata->prepare($ss) or $self->app->log->error($self->app->db_metadata->errstr);
	$sth->execute();
	$sth->bind_columns(undef, \$cid, \$vid, \$entry, \$isocode);		
	my %classes;
	my %isocodes;
	while($sth->fetch){	
		$classes{$cid}{$isocode} = $entry;
		$classes{$cid}{vid} = $vid;
		$isocodes{$isocode} = 1;
	}
	$sth->finish;
    
    my @classes;
    foreach my $cid (keys %classes){
    	
    	my %class;
    	$class{uri} = "$classification_ns/voc_$vid";
    	foreach my $iso (keys %isocodes){
    		 $class{$iso} = $classes{$cid}{$iso};
    	}
    	
    	# get search results for each classification
    	my $limit = $self->app->{config}->{terms}->{search_results_limit};
    	my ($veid, $isocode, $entry ,$vid, $tid, $upstream_identifier, $term_id, $preferred);
    	$ss = "SELECT ve.veid, ve.isocode, ve.entry, ve.vid, t.tid, t.upstream_identifier, tv.term_id, tv.preferred FROM vocabulary_entry ve LEFT JOIN taxon_vocentry tv ON ve.veid = tv.veid LEFT JOIN taxon t on tv.tid = t.tid  WHERE MATCH (entry) AGAINST(?) AND tv.TID IS NOT NULL AND t.cid = (?) LIMIT $limit;";
		$sth = $self->app->db_metadata->prepare($ss) or $self->app->log->error($self->app->db_metadata->errstr);
		$sth->execute($q, $cid);
		$sth->bind_columns(undef, \$veid, \$isocode, \$entry ,\$vid, \$tid, \$upstream_identifier, \$term_id, \$preferred);
		my %terms;
		while($sth->fetch){		
			
			#$self->app->log->debug("veid=$veid iso=$isocode entry=$entry vid=$vid tid=$tid upid=$upstream_identifier term=$term_id pref=$preferred");

			$terms{$tid.$term_id}{upstream_identifier} = $upstream_identifier;
			$terms{$tid.$term_id}{vid} = $vid;
			$terms{$tid.$term_id}{preferred} = $preferred;
			$terms{$tid.$term_id}{term_id} = $term_id;
			$terms{$tid.$term_id}{$isocode} = $entry;
			$terms{$tid.$term_id}{tid} = $tid; # we will make it array later
			$isocodes{$isocode} = 1;
		}		
				
		# make array
		my @terms;
		foreach my $id (keys %terms){
			push @terms, $terms{$id};
		}
				
		$class{terms} = \@terms;	
		
		push @classes, \%class;	
	}		
	$sth->finish;
	undef $sth;
	
	$res->{terms} = \@classes;
	$self->render(json => $res, status => $res->{status});
}

1;
