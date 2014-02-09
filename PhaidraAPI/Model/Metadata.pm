package PhaidraAPI::Model::Metadata;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use Storable qw(dclone);
use Switch;
use Data::Dumper;
use Mojo::ByteStream qw(b);
use Mojo::Home;
use XML::Writer;
use XML::LibXML;
use lib "lib/phaidra_binding";
use Phaidra::API;
my $home = Mojo::Home->new;
$home->detect('PhaidraAPI');

sub metadata_tree {
	
    my ($self, $c, $v) = @_;
 
 	my $cachekey = 'metadata_tree_'.$v;
 	if($v eq '1'){
 		
 		my $res = $c->app->chi->get($cachekey);
  		
    	if($res){    		
    		$c->app->log->debug("[cache hit] $cachekey");
    	}else{    		
    		$c->app->log->debug("[cache miss] $cachekey");
    		
    		$res = $self->get_metadata_tree($c);		
  
    		$c->app->chi->set($cachekey, $res, '1 day');    
  
  			# save and get the value. the serialization can change integers to strings so 
  			# if we want to get the same structure for cache miss and cache hit we have to run it through
  			# the cache serialization process even if cache miss [when we already have the structure]
  			# so instead of using the structure created we will get the one just saved from cache.  		
    		$res = $c->app->chi->get($cachekey);
    		#$c->app->log->debug($c->app->dumper($res));			
    	}    	 		
 		return $res;
		
 	}else{
 		$c->app->log->error($c->stash->{'message'}); 		
 		$c->stash( 'message' => 'Unknown metadata format version requested.'); 		 		
		return -1;
 	}
  
}

sub get_languages {
	my ($self, $c) = @_;
	
	my $cachekey = 'languages';
	
	my $res = $c->app->chi->get($cachekey);
  		
    if($res){    		
    	$c->app->log->debug("[cache hit] $cachekey");
    }else{    		
    	$c->app->log->debug("[cache miss] $cachekey");
	
		my %l;
		
		my $sth;
		my $ss;
		
		$ss = qq/SELECT l.isocode, ve.isocode, ve.entry FROM language AS l LEFT JOIN vocabulary_entry AS ve ON l.VEID = ve.VEID/;
		$sth = $c->app->db_metadata->prepare($ss) or $c->app->log->error($c->app->db_metadata->errstr);
		$sth->execute();
		my $isocode;
		my $ve_isocode;
		my $ve_entry;			
		$sth->bind_columns(undef, \$isocode, \$ve_isocode, \$ve_entry);				 
		while($sth->fetch) {		
			$l{$isocode}{$ve_isocode} = $ve_entry if defined($ve_isocode); 
			#$l->{$isocode}{isocode} = {$ve_isocode} = $ve_entry ;
		}
		
		$c->app->chi->set($cachekey, \%l, '1 day');    
  
  		$res = $c->app->chi->get($cachekey);
    }
	
	#$c->app->log->debug($c->app->dumper($res));
	return $res;
}

sub get_metadata_tree {
	
	my ($self, $c) = @_;
	
	my %format;
	my @metadata_tree;
	my %id_hash;
	my %license_veid_lid_map;
	
	my $sth;
	my $ss;
	
	# create mapping of veid to licence id
	$ss = qq/SELECT LID, name FROM licenses/;
	$sth = $c->app->db_metadata->prepare($ss) or $c->app->log->error($c->app->db_metadata->errstr);
	$sth->execute();
	my $l_lid;
	my $l_veid;			
	$sth->bind_columns(undef, \$l_lid, \$l_veid);				 
	while($sth->fetch) {
		$license_veid_lid_map{$l_veid} = $l_lid; 
	}
	
	#$c->app->log->debug($c->app->dumper(\%license_veid_lid_map));
	
	$ss = qq/SELECT 
			m.MID, m.VEID, m.xmlname, m.xmlns, m.lomref, 
			m.searchable, m.mandatory, m.autofield, m.editable, m.OID,
			m.datatype, m.valuespace, m.MID_parent, m.cardinality, m.ordered, m.fgslabel,
			m.VID, m.defaultvalue, m.sequence
			FROM metadata m
			ORDER BY m.sequence, m.MID ASC/;
	$sth = $c->app->db_metadata->prepare($ss) or $c->app->log->error($c->app->db_metadata->errstr);
	$sth->execute();
	
	my $mid; # id of the element 
	my $veid; # id of the vocabulary entry defining the label of the element (in multiple languages)
	my $xmlname; # name of the element (name and namespace constitute URI)
	my $xmlns; # namespace of the element (name and namespace constitute URI)
	my $lomref; # id in LOM schema (if the element comes from LOM)
	my $searchable; # 1 if the element is visible in advanced search
	my $mandatory; # 1 if the element is mandatory
	my $autofield; # ? i found no use for this one
	my $editable; # 1 if the element is available in metadataeditor
	my $oid; # this was meant for metadata-owner feature 
	my $datatype; # Phaidra datatype (/usr/local/fedora/cronjobs/XSD/datatypes.xsd)
	my $valuespace; # regex constraining the value
	my $mid_parent; # introduces structure, eg firstname is under entity, etc
	my $cardinality; # eg 1, 2, * - any
	my $ordered; # Y if the order of elements have to be preserved (eg entity is ordered as the order of authors is important)
	my $fgslabel; # label for the search engine (is used in index and later in search queries)
	my $vid; # if defined then id of the controlled vocabulary which represents the possible values
	my $defaultvalue; # currently there's only #FIRSTNAME, #LASTNAME and #TODAY or NULL
	my $field_order; # order of the element among it's siblings
	
	$sth->bind_columns(undef, \$mid, \$veid, \$xmlname, \$xmlns, \$lomref, \$searchable, \$mandatory, \$autofield, \$editable, \$oid, \$datatype, \$valuespace, \$mid_parent, \$cardinality, \$ordered, \$fgslabel, \$vid, \$defaultvalue, \$field_order);
	
	# fill the hash with raw table data
	my $i = 0;
	while($sth->fetch) {		
		$i++;	
		$format{$mid} = {
			mid => $mid, # needed for sort
			debug_id => int(rand(9999)), 
			veid => $veid, 
			xmlname => $xmlname, 
			xmlns => $xmlns, 
			lomref => $lomref, 
			searchable => $searchable, 
			mandatory => ($mandatory eq 'N' ? 0 : 1), 
			autofield => $autofield, 
			editable => $editable, 
			oid => $oid, 
			datatype => $datatype,  
			mid_parent => $mid_parent, 
			cardinality => $cardinality, 
			ordered => ($ordered eq 'Y' ? 1 : 0), 
			fgslabel => $fgslabel, 
			vid => $vid, 
			defaultvalue => $defaultvalue, 
			field_order => (defined($field_order) ? $field_order : 9999), # as defined in metadata format, value must be defined because we are going to sort by this
			data_order => '', # as defined in object's metadata (for objects which have 'ordered = 1')		
			help_id => 'helpmeta_'.$mid, # used ot get the help tooltip content via ajax
			value => '', # what's expected in uwmetadata
			value_lang => '', # language of the value if any
			ui_value => '', # what's expected on the form (eg ns/id for vocabularies)
			loaded_ui_value => '', # the initial value which was loaded from the object, ev transformed for frontend use
			loaded_value => '', # the initial uwmetadata value which was loaded from the object
			loaded_value_lang => '', # the initial language for the value, if any
			loaded => 0, # 1 if this element was filled with a value loaded from object's metadata
			#field_id => 'field_'.$i,
			input_type => '', # which html control to use, we will specify this later
			hidden => 0, # we will specify later which fields are to be hidden
			disabled => 0 # we will specify later which fields are to be disabled
		};
		
		$format{$mid}->{input_regex} = $valuespace;
		
		# mapping of "Phaidra Datatypes" to form input types
		#
		# possible values (with schema restrictions):
		#  Duration PT(\d{1,2}H){0,1}(\d{1,2}M){0,1}(\d{1,2}S){0,1}
		#  CharacterString (string)
		#  LangString (string)
		#  Vocabulary (int)
		#  FileSize (nonNegativeInteger)
		#  Node (string)
		#  License (nonNegativeInteger)
		#  DateTime -{0,1}\d{4}(-\d{2}){0,1}(-\d{2}){0,1} or \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z
		#  GPS \d{1,3}°\d{1,2}'\d{1,2}''[EW]{1}\|\d{1,2}°\d{1,2}'\d{1,2}''[NS]{1}
		#  Boolean 'yes' or 'no'
		#  Faculty (string)
		#  Department (string)
		#  SPL (string)
		#  Curriculum (string)
		#  Taxon (int)
		#
		# at the beginning just a basic definition, for some fields we will redefine this later 
		# because eg description is just defined as LangString, the same way as eg title, but description must be textarea 
		# not just a simple text input
		switch ($datatype) {
			
			case "LangString" { 
				$format{$mid}->{input_type} = "input_text_lang";
				$format{$mid}->{value_lang} =  $c->app->config->{defaults}->{metadata_field_language}; 
			}
			
			case "DateTime"	{ $format{$mid}->{input_type} = "input_datetime" }
						
			case "Vocabulary" { $format{$mid}->{input_type} = "select" }			
			case "License" { $format{$mid}->{input_type} = "select" }
			case "Faculty" { $format{$mid}->{input_type} = "select" }
			case "Department" { $format{$mid}->{input_type} = "select" }
			case "SPL" { $format{$mid}->{input_type} = "select" }
			case "Curriculum" { $format{$mid}->{input_type} = "select" }
			
			case "Language" { $format{$mid}->{input_type} = "language_select" }
			
			case "Boolean"	{
				if($format{$mid}->{mandatory}){
					$format{$mid}->{input_type} = "select_yesno";
				}else{ 
					$format{$mid}->{input_type} = "input_checkbox";
				} 
			}
			
			case "Node"	{ $format{$mid}->{input_type} = "node" }
			
			case "CharacterString" { $format{$mid}->{input_type} = "input_text" }						
			case "GPS" { $format{$mid}->{input_type} = "input_text" }
			case "Duration" { $format{$mid}->{input_type} = "input_duration" }
			case "FileSize" { $format{$mid}->{input_type} = "input_text" }			
			else { $format{$mid}->{input_type} = "input_text" }
		}
		
		# special input types
		switch ($format{$mid}->{xmlname}) {
			case "description"	{ 
				$format{$mid}->{input_type} = "input_textarea_lang";
				$format{$mid}->{value_lang} =  $c->app->config->{defaults}->{metadata_field_language}; 
				}
			case "identifier" {
				# because there is also an 'identifier' in the http://phaidra.univie.ac.at/XML/metadata/extended/V1.0 namespace
				if($format{$mid}->{xmlns} eq 'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0'){
					$format{$mid}->{input_type} = "static";					
				}				
			}
			case "upload_date" {
				$format{$mid}->{input_type} = "static";
			}
			case "orcomposite" {
				$format{$mid}->{input_type} = "label_only";
			}
		}
		
		# hidden fields
		switch ($format{$mid}->{xmlname}) {
			case "irdata" { $format{$mid}->{hidden} = 1 } # system field
			case "metadataqualitycheck" { $format{$mid}->{hidden} = 1 } # system field
			case "classification" { $format{$mid}->{hidden} = 1 } # i think this should be edited elsewhere
			case "annotation" { $format{$mid}->{hidden} = 1 } # was removed from editor
			case "etheses" { $format{$mid}->{hidden} = 1 } # should not be edited in phaidra (i guess..)			
		}		
		
		$id_hash{$mid} = $format{$mid}; # we will use this later for direct id -> element access 		
	}	 	
	
	# create the hierarchy
	my @todelete;
	my %parents;
	foreach my $key (keys %format){
		if($format{$key}{mid_parent}){
			$parents{$format{$key}{mid_parent}} = $format{$format{$key}{mid_parent}};
			push @todelete, $key;
			push @{$format{$format{$key}{mid_parent}}{children}}, $format{$key};			
		}
	}	
	delete @format{@todelete};
	
	# now just as children are just an array, also the top level will be only an array
	# we do this because we don't want to hardcode the mids anywhere
	# we should just work with namespace and name
	while ( my ($key, $element) = each %format ){	
		push @metadata_tree, $element;
	}
	
	# and sort it
	@metadata_tree = sort { $a->{field_order} <=> $b->{field_order} ||  $a->{mid} <=> $b->{mid} } @metadata_tree;	
	
	# and sort the children
	foreach my $key (keys %parents){
		@{$id_hash{$key}{children}} = sort { $a->{field_order} <=> $b->{field_order} ||  $a->{mid} <=> $b->{mid} } @{$parents{$key}{children}};		
	}
	
	# get the element labels
	$ss = qq/SELECT m.mid, ve.entry, ve.isocode FROM metadata AS m LEFT JOIN vocabulary_entry AS ve ON ve.veid = m.veid;/;
	$sth = $c->app->db_metadata->prepare($ss) or $c->app->log->error($c->app->db_metadata->errstr);
	$sth->execute();	

	my $entry; # element label (name of the field, eg 'Title')
	my $isocode; # 2 letter isocode defining language of the entry	
	
	$sth->bind_columns(undef, \$mid, \$entry, \$isocode);	
	while($sth->fetch) {		
		$id_hash{$mid}->{'labels'}->{$isocode} = $entry;		 			
	}

	# get the vocabularies (HINT: this crap will be overwritten when we have vocabulary server)
	while ( my ($key, $element) = each %id_hash ){	
		if($element->{vid}){

			my %vocabulary;
			
			# get vocabulary info
			$ss = qq/SELECT description FROM vocabulary WHERE vid = (?);/;
			$sth = $c->app->db_metadata->prepare($ss) or $c->app->log->error($c->app->db_metadata->errstr);
			$sth->execute($element->{vid});
			
			my $desc; # some short text describing the vocabulary (it's not multilanguage, sorry)
			
			$sth->bind_columns(undef, \$desc);
			$sth->fetch;
			
			$vocabulary{description} = $desc;
			
			# there's none, i'm fabricating this
			$vocabulary{namespace} = $element->{xmlns}.'/voc_'.$element->{vid}.'/';
			
			# get vocabulary values/codes
			$ss = qq/SELECT veid, entry, isocode FROM vocabulary_entry WHERE vid = (?);/;
			$sth = $c->app->db_metadata->prepare($ss) or $c->app->log->error($c->app->db_metadata->errstr);
			$sth->execute($element->{vid});
			
			my $veid; # the code, together with namespace this creates URI, that's the current hack
			my $entry; # value label (eg 'Wood-engraver')
			my $isocode; # 2 letter isocode defining language of the entry
			
			$sth->bind_columns(undef, \$veid, \$entry, \$isocode);
			
			# fetching data using hash, so that we quickly find the place for the entry but later ... [x] 
			while($sth->fetch) {
				
				my $termkey;
				if($element->{vid} == 21){		
					# license metadata field uses license id as value, not veid		
					$termkey = $license_veid_lid_map{$veid};
				}else{				
					$termkey = $veid; 
				}
				
				$vocabulary{'terms'}->{$termkey}->{uri} = $vocabulary{namespace}.$termkey; # this gets overwritten for the same entry
				$vocabulary{'terms'}->{$termkey}->{$isocode} = $entry; # this should always contain another language for the same entry								
			}
			
			# [x] ... we remove the id hash
			# because we should work with URI - namespace and code, ignoring the current 'id' structure

			my @termarray;
			while ( my ($key, $element) = each %{$vocabulary{'terms'}} ){	
				push @termarray, $element;
			}
			$vocabulary{'terms'} = \@termarray;
			
			# maybe we want to support multiple vocabularies for one field in future
			push @{$element->{vocabularies}}, \%vocabulary;
					
		}		
		# get organisational structure vocabularies
		# faculties and stdy plans at the moment, 
		# departments depends on chosen faculty and curriculums on chosen study plan
		# so we won't load departments and curriculums (although this is a bit uni specific)
		elsif($element->{datatype} eq "Faculty"){
			
			my %vocabulary;
			
			$vocabulary{namespace} = $element->{xmlns}.'/voc_'.$element->{xmlname}.'/';
			my $langs = $c->app->config->{directory}->{org_units_languages};
			foreach my $lang (@$langs){
				
				my $res = $c->app->directory->get_org_units($c, undef, $lang);
				if(exists($res->{alerts})){
					if($res->{status} != 200){
						# there are only alerts
						return { alerts => $res->{alerts}, status => $res->{status} }; 
					}
				}
				
				my $org_units = $res->{org_units};
				
				foreach my $u (@$org_units){
					$vocabulary{'terms'}->{$u->{value}}->{uri} = $vocabulary{namespace}.$u->{value};
					$vocabulary{'terms'}->{$u->{value}}->{$lang} = $u->{name};
										
				}											
			}
			my @termarray;
			while ( my ($key, $element) = each %{$vocabulary{'terms'}} ){	
				push @termarray, $element;
			}
			$vocabulary{'terms'} = \@termarray;
			
			push @{$element->{vocabularies}}, \%vocabulary;
			
		}elsif($element->{datatype} eq "Department"){
			my %vocabulary;
			$vocabulary{namespace} = $element->{xmlns}.'/voc_'.$element->{xmlname}.'/';
			$vocabulary{terms} = [];
			push @{$element->{vocabularies}}, \%vocabulary;
				
		}elsif($element->{datatype} eq "SPL"){
			
			my %vocabulary;
			
			$vocabulary{namespace} = $element->{xmlns}.'/voc_'.$element->{xmlname}.'/';
			my $langs = $c->app->config->{directory}->{study_plans_languages};
			foreach my $lang (@$langs){
				
				my $res = $c->app->directory->get_study_plans($c, undef, $lang);
				if(exists($res->{alerts})){
					if($res->{status} != 200){
						# there are only alerts
						return { alerts => $res->{alerts}, status => $res->{status} }; 
					}
				}
				
				my $study_plans = $res->{study_plans};
				
				foreach my $sp (@$study_plans){
					$vocabulary{'terms'}->{$sp->{value}}->{uri} = $vocabulary{namespace}.$sp->{value};
					$vocabulary{'terms'}->{$sp->{value}}->{$lang} = $sp->{name};
										
				}											
			}
			my @termarray;
			while ( my ($key, $element) = each %{$vocabulary{'terms'}} ){	
				push @termarray, $element;
			}
			$vocabulary{'terms'} = \@termarray;
			
			push @{$element->{vocabularies}}, \%vocabulary;						
		
		}elsif($element->{datatype} eq "Curriculum"){
			my %vocabulary;
			$vocabulary{namespace} = $element->{xmlns}.'/voc_'.$element->{xmlname}.'/';
			$vocabulary{terms} = [];
			push @{$element->{vocabularies}}, \%vocabulary;
		}
		
	}

	# delete ids, we don't need them
	while ( my ($key, $element) = each %id_hash ){
		delete $element->{vid};
		delete $element->{veid};
		delete $element->{mid_parent};
	}
	
	return \@metadata_tree;
}

sub get_object_metadata {
	
	my ($self, $c, $v, $pid) = @_;

	# this structure contains the metadata default structure (equals to empty metadataeditor) to which
	# we are going to load the data of some real object 
	my $metadata_tree = $self->metadata_tree($c, $v);
	if($metadata_tree == -1){
		$self->render(json => { message => $self->stash->{'message'}} , status => 500) ;		
		return;
	}
	
	# this is a hash where the key is 'ns/id' and value is a default representation of a node
	# -> we use this when adding nodes (eg a second title) to get a new empty node
	my %metadata_nodes_hash;
	my $metadata_tree_copy = dclone($metadata_tree);
	$self->create_md_nodes_hash($c, $metadata_tree_copy, \%metadata_nodes_hash);
	#$c->app->log->debug($c->app->dumper(\%metadata_nodes_hash));
	
	# get object metadata
	my $uwmd = $self->get_uwmetadata($c, $pid);	
	my $dom = Mojo::DOM->new($uwmd);
	
	#$c->app->log->debug($c->app->dumper($dom->tree));
	
	#my $e = $dom->tree;
	my $nsattr = $dom->find('uwmetadata')->first->attr;
	my $nsmap  = $nsattr;
	# replace xmlns:ns0 with ns0
	foreach my $key (keys %{$nsmap}) {
		my $newkey = $key;		
		$newkey =~ s/xmlns://g;
		$nsmap->{$newkey} = delete $nsmap->{$key}; 
    }
	#$c->app->log->debug($c->app->dumper($nsmap));	
	$self->fill_object_metadata($c, $dom, $metadata_tree, undef, $nsmap, \%metadata_nodes_hash);
	#$c->app->log->debug($c->app->dumper($metadata_tree));		
	return $metadata_tree;
}

sub get_org_units_terms {
	my $self = shift;
	my $c = shift;
	my $parent_id = shift;
	my $value_namespace = shift;
	
	my %vocabulary;
	my $langs = $c->app->config->{directory}->{org_units_languages};
	foreach my $lang (@$langs){
				
		my $res = $c->app->directory->get_org_units($c, $parent_id, $lang);
				
		my $org_units = $res->{org_units};
				
		foreach my $u (@$org_units){	
			$vocabulary{'terms'}->{$u->{value}}->{uri} = $value_namespace.$u->{value};
			$vocabulary{'terms'}->{$u->{value}}->{$lang} = $u->{name};								
		}											
	}
	my @termarray;
	while ( my ($key, $element) = each %{$vocabulary{'terms'}} ){	
		push @termarray, $element;
	}
	
	return \@termarray;
}

sub get_study_terms {
	
	my $self = shift;
	my $c = shift;
	my $spl = shift;
	my $ids = shift;
	my $values_namespace = shift;
	
	my %vocabulary;	
	my $langs = $c->app->config->{directory}->{study_plans_languages};
	
	foreach my $lang (@$langs){
		my $res = $c->app->directory->get_study($c, $spl, $ids, $lang);
					
		my $study = $res->{'study'};
					
		foreach my $s (@$study){	
			$vocabulary{'terms'}->{$s->{value}}->{uri} = $values_namespace.$s->{value};
			$vocabulary{'terms'}->{$s->{value}}->{$lang} = $s->{name};								
		}	
	}										
	
	my @termarray;
	while ( my ($key, $element) = each %{$vocabulary{'terms'}} ){	
		push @termarray, $element;
	}
	
	return \@termarray;
}

sub get_study_name {
	
	my $self = shift;
	my $c = shift;
	my $spl = shift;
	my $ids = shift;
	
	my $langs = $c->app->config->{directory}->{study_plans_languages};
	
	my %names;
	foreach my $lang (@$langs){
		my $name = $c->app->directory->get_study_name($c, $spl, $ids, $lang);
		$names{$lang} = $name;				
	}										
	
	return \%names;
}

sub fill_object_metadata {
	
	my $self = shift;
	my $c = shift;
	my $uwmetadata = shift;
	my $metadata_tree = shift;
	my $metadata_tree_parent = shift;
	my $nsmap = shift;
	my $metadata_nodes_hash = shift;
	
	my $tidy = shift;
	$tidy .= '  ';
			
	unless(defined($metadata_tree_parent)){
		my %h = (
			'children' => $metadata_tree
		);	
		$metadata_tree_parent = \%h;
	}
			
	for my $e ($uwmetadata->children->each) {
		
		#$self->app->log->debug($self->app->dumper($e));		
		
	    my $type = $e->type;
	    
	    # type looks like this: ns1:general
	    # get namespace and identifier from it
	    # namespace = 'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0'
	    # identifier = 'general'
	    $type =~ m/(ns\d+):([0-9a-zA-Z_]+)/;
	    my $ns = $1;
	    my $id = $2;
	    my $node;
	    if($id ne 'uwmetadata'){	    
		    # search this node in the metadata tree
		    # get one where metadata from uwmetadata were not yet loaded
		    $ns = $nsmap->{$ns};
		    $node = $self->get_empty_node($c, $ns, $id, $metadata_tree_parent, $metadata_nodes_hash); 

			if($e->text){
	    		# fill in values
	    		#
	    		# if the node has a vocabulary, then it's a select box 
	    		# so there is a difference between
	    		# value (value) and text (ui_value)    		
	    		if(defined($node->{vocabularies})){
	    			
	    			foreach my $voc (@{$node->{vocabularies}}){
		    			my $node_value = $e->text;
		    			
		    			$node->{value} = $voc->{namespace}.$node_value;
		    			$node->{loaded_value} = $voc->{namespace}.$node_value;
		    			$node->{ui_value} = $voc->{namespace}.$node_value;
		    			$node->{loaded_ui_value} = $voc->{namespace}.$node_value;
	    			}
	    				    			
	    			if($node->{xmlname} eq 'department'){
	    			
	    				# get the selected faculty, if any, and fill the department vocabulary	
		    			if($e->parent){
		    				my $faculty = undef;
			    			for my $child ($e->parent->children->each) {
							    if($child->tree eq $e->tree){
							    	if($faculty){
							    		if($faculty->text){
							    			foreach my $voc (@{$node->{vocabularies}}){
							    				$voc->{terms} = $self->get_org_units_terms($c, $faculty->text, "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/organization/voc_department/");	
							    			}
							    		}
							    		
							    	}
							    	last;
							    }
							    $faculty = $child;
							}
		    			}	    			
	    			}
	    			
	    			if($node->{xmlname} eq 'kennzahl'){
	    				# get the previous sibling and study plan and fill the study plan vocabulary	
		    			if($e->parent){
		    				my $prev = undef;
		    				my $spl = undef;
		    				my $current_seq = undef;
		    				my $ids_all;
 							my $last_kennzahl = 0;
			    			for my $child ($e->parent->children->each) {

			    				if($e->parent->children->reverse->first->tree eq $e->tree){			    					
			    					$last_kennzahl = 1;			    					
			    				}
			    				
			    				my $child_type = $child->type;
			    				$child_type =~ m/(ns\d+):([0-9a-zA-Z_]+)/;
							    my $ns = $1;
							    my $id = $2;
							    if($id eq 'spl'){
							    	$spl = $child->text;
							    	next;
							    }
							    if($id eq 'kennzahl'){
							    	push @$ids_all, { text => $child->text, seq => $child->attr('seq')};
							    	if($child->tree eq $e->tree){
							    		$current_seq = $child->attr('seq');
							    	}
							    }							    
							}							
							@$ids_all = sort { $a->{seq} <=> $b->{seq} } @$ids_all;

							# for the get_study method we need all the ids until the current one
							my @ids;
							for my $id (@$ids_all){
								if($id->{seq} eq $current_seq){
									last;	
								}else{
									push @ids, $id->{text}; 	
								}									
							}
												    		
							foreach my $voc (@{$node->{vocabularies}}){
								$voc->{terms} = $self->get_study_terms($c, $spl, \@ids, "http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/organization/voc_kennzahl/");	
							}							    		
							
							# try to get the study name
							if($last_kennzahl){
							
								my @ids;
								for my $id (@$ids_all){							
									push @ids, $id->{text}; 	
								}									
															
								$metadata_tree_parent->{study_name} = $self->get_study_name($c, $spl, \@ids);
																
							}
		    			}	
	    			}
	    			
	    		}elsif($node->{input_type} eq "input_checkbox" || $node->{input_type} eq "select_yesno"){
	    			my $v;
	    			if($e->text eq 'yes'){
	    				$v = '1';
	    			}
	    			if($e->text eq 'no'){
	    				$v = '0';
	    			}
	    			#$node->{value} = $v;
				    $node->{loaded_value} = $v;
				    $node->{ui_value} = $v;
				    $node->{loaded_ui_value} = $v;
	    		}else{
	    			my $v = b($e->text)->decode('UTF-8');
	    			#$node->{value} = $v;
				    $node->{loaded_value} = $v;
				    $node->{ui_value} = $v;
				    $node->{loaded_ui_value} = $v;
	    		}

			}
			
			if(defined($e->attr)){			
			   	if($e->attr->{language}){
			    	$node->{value_lang} = $e->attr->{language};
			    	$node->{loaded_value_lang} = $e->attr->{language};
			   	}
			   	if(defined($e->attr->{seq}) && $node->{ordered}){			   		
			   		$node->{data_order} = $e->attr->{seq}; 	
			   		@{$metadata_tree_parent->{children}} = sort { sort_ordered($a) <=> sort_ordered($b) } @{$metadata_tree_parent->{children}};			   				
			  	}
			}
	    }
	    if($e->children->size > 0){
	    	$self->fill_object_metadata($c, $e, $metadata_tree, $node, $nsmap, $metadata_nodes_hash, $tidy);
	    }
	}
	
}

sub sort_ordered {
	
	my $node = shift;

	# upload_date, version, etc needs to be ordered by field_order, as well as contribute
	# but among contribute nodes, the order is defined by seq (data_order)
	# => field_order takes preference
	#
	# <ns1:lifecycle>
	# <ns1:upload_date>2013-06-12T11:02:28.665Z</ns1:upload_date>
	# <ns1:version language="de">2</ns1:version>
	# <ns1:status>44</ns1:status>
	# <ns2:peer_reviewed>no</ns2:peer_reviewed>
	# <ns1:contribute seq="1">...</ns1:contribute>
	# <ns1:contribute seq="2">...</ns1:contribute>
	# <ns1:contribute seq="3">...</ns1:contribute>
	# <ns1:contribute seq="4">...</ns1:contribute>
	# <ns1:contribute seq="0">...</ns1:contribute>
	# <ns2:infoeurepoversion>1556249</ns2:infoeurepoversion>
	# </ns1:lifecycle>

	if($node->{data_order} eq ''){
		return int($node->{field_order});	
	}else{		
		return int($node->{field_order}) + ("0.".$node->{data_order});
	}		
	
}

sub get_empty_node {
	
	my $self = shift;
	my $c = shift;
	my $ns = shift;
	my $id = shift;
	my $parent = shift;
	my $metadata_nodes_hash = shift;
	
	#$c->app->log->debug("searching empty node $id under ".$parent->{xmlname}.' ['.$parent->{debug_id}.']');
	
	my $node;
	my $i = 0;
	foreach my $n (@{$parent->{children}}){
			
		$i++;
			
		my $xmlns = $n->{xmlns};
		my $xmlname = $n->{xmlname};	
		my $children_size = defined($n->{children}) ? scalar (@{$n->{children}}) : 0;
			
		if(($xmlns eq $ns) && ($xmlname eq $id)){
			#$c->app->log->debug("found ".($n->{loaded} ? "used" : "empty")." node ".$xmlname.' ['.$n->{debug_id}.']');
		
			# found it! is this node already used?
			if($n->{loaded}){
				# yes, create a new one					
				my $new_node = dclone($metadata_nodes_hash->{$xmlns.'/'.$xmlname});
				# and add it to the structure
				splice @{$parent->{children}}, $i, 0, $new_node;
				$node = $new_node;
			}else{
				# no, use the found one
				$node = $n;	
			}			
			
			$node->{loaded} = 1;
		}
		
		elsif($children_size > 0){					
			$node = $self->get_empty_node($c, $ns, $id, $n, $metadata_nodes_hash);			
		}
		
		last if defined $node;
	}
	
	return $node;	
}


sub create_md_nodes_hash {
	
	my $self = shift;
	my $c = shift;
	my $children = shift;
	my $h = shift;

	foreach my $n (@{$children}){
		
		$h->{$n->{xmlns}.'/'.$n->{xmlname}} = $n;
					
		my $children_size = defined($n->{children}) ? scalar (@{$n->{children}}) : 0;		
		if($children_size > 0){						
			$self->create_md_nodes_hash($c, $n->{children}, $h);			
		}
		
	}
	
}

sub get_uwmetadata {
	
	my $self = shift;
	my $c = shift;
	my $pid = shift; 
		
	my $uwmdurl = $c->app->config->{phaidra}->{getuwmetadataurl};
	$uwmdurl =~ s/{PID}/$pid/g;
	
	my $ua = Mojo::UserAgent->new;
  	my $uwmd = $ua->get($uwmdurl)->res->body;  	
	
	return $uwmd;		
}

sub save_to_object(){
	
	my $self = shift;
	my $c = shift;
	my $pid = shift;
	my $metadata = shift;
	
	my $res = { alerts => [], status => 200 };
	
	my $uwmetadata = $self->json_2_uwmetadata($c, $metadata);
	
	unless($uwmetadata){
		$res->{status} = 500;
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error coverting metadata'};
		return $res
	}
	
	my $saveres = $self->save_uwmetadata($c, $pid, $uwmetadata);
	if($saveres->{status} != 200){
		$res->{status} = 500;
		unshift @{$res->{alerts}}, @{$saveres->{alerts}};
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error saving metadata to object'};
		return $res;
	}else{
		unshift @{$res->{alerts}}, @{$saveres->{alerts}};
	}
	
	return $res
}

sub validate_uwmetadata(){
	
	my $self = shift;
	my $c = shift;	
	my $pid = shift;
	my $uwmetadata = shift;	
	
	my $res = { alerts => [], status => 200 };

	my $xsdpath = $home->rel_file('public/xsd/uwmetadata/ns0.xsd');
	
	unless(-f $xsdpath){
		unshift @{$res->{alerts}}, { type => 'danger', msg => "Cannot find XSD files: $xsdpath"};
		$res->{status} = 500;
	};

	my $schema = XML::LibXML::Schema->new(location => $xsdpath);
	my $parser = XML::LibXML->new;

	eval {
		my $document = $parser->parse_string($uwmetadata);
		
		unless(defined($pid)){
			$self->add_dummy_metadata($c, $document);
		}	
		
		#$c->app->log->debug("Validating: ".$document->toString(1));	
		
		$schema->validate($document) 
	};
		
	if($@){
		$c->app->log->error("Error validating uwmetadata: $@");
		unshift @{$res->{alerts}}, { type => 'danger', msg => $@ };
		$res->{status} = 500;		
	}

	return $res;
}

sub add_dummy_metadata(){
	
	my $self = shift;
	my $c = shift;	
	my $doc = shift;
	
	my $cfg;
	foreach my $node ($doc->findnodes('//namespace::*')) {
    	$cfg->{namespace}{$node->getLocalName()} = $node->getValue();
    	$cfg->{short}{$node->getValue()} = $node->getLocalName();
	}
	
	my $xc = XML::LibXML::XPathContext->new($doc);	
	for my $ns (keys %{$cfg->{namespace}})
	{
		$xc->registerNs($ns => $cfg->{namespace}->{$ns});
	}
	
	my $uwmetans = $cfg->{short}->{"http://phaidra.univie.ac.at/XML/metadata/V1.0"};
	my $lomns = $cfg->{short}->{"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0"};
		
	# add pid	
	my $xpath = "/$uwmetans:uwmetadata/$lomns:general";
	my $nodeset = $xc->findnodes($xpath);
	my $generalnode;
	foreach my $gnode ($nodeset->get_nodelist){
		$generalnode = $gnode;
		last;
	}			
	$xpath = "/$uwmetans:uwmetadata/$lomns:general/$lomns:identifier";	
	$nodeset = $xc->findnodes($xpath);	
	my $pidnode = undef;
	foreach my $node ($nodeset->get_nodelist){
		$pidnode = $node;	
		my $pidnodenew = $doc->parse_balanced_chunk('<'.$lomns.':identifier xmlns:'.$lomns.'="http://phaidra.univie.ac.at/XML/metadata/extended/V1.0">o:1</'.$lomns.':identifier>');	
		$generalnode->insertAfter($pidnodenew, $pidnode);
		$generalnode->removeChild($pidnode);
		last;	 
	}
	
	#add upload_date
	$xpath = "/$uwmetans:uwmetadata/$lomns:lifecycle";
	$nodeset = $xc->findnodes($xpath);
	my $lifecyclenode;
	foreach my $lnode ($nodeset->get_nodelist){
		$lifecyclenode = $lnode;
		last;
	}			
	$xpath = "/$uwmetans:uwmetadata/$lomns:lifecycle/$lomns:upload_date";	
	$nodeset = $xc->findnodes($xpath);	
	my $upload_date_node = undef;
	foreach my $node ($nodeset->get_nodelist){
		$upload_date_node = $node;	
		my $upload_date_node_new = $doc->parse_balanced_chunk('<'.$lomns.':upload_date xmlns:'.$lomns.'="http://phaidra.univie.ac.at/XML/metadata/extended/V1.0">1970-01-01T00:00:00.000Z</'.$lomns.':upload_date>');	
		$generalnode->insertAfter($upload_date_node_new, $upload_date_node);
		$generalnode->removeChild($upload_date_node);
		last;	 
	}
}

sub json_2_uwmetadata(){
	
	my $self = shift;
	my $c = shift;	
	my $metadata = shift;

	# 1) unfortunately in UWMETADATA, the namespace prefixes are numbered (ns0, ns1,...)
	# 2) unfortunately the namespace prefixes are numbered rather randomly
	# 3) unfortunately some scripts have the prefixes hardcoded (@xyz = $class->getChildrenByTagName("ns7:source");)
	# If this api would only edit objects, we could now sacrifice one call to get the current uwmetadata and read out 
	# the prefix-namespace mapping, so that we don't change a thing.
	# But this api also creates objects, so it will impose it's prefix-namespace mapping anyway.
	# To be transparent, we should just number the namespaces as they appear in this json tree, but some
	# elements (namely all optional fields) might not even be there - and UWMETADATA files without those namespaces
	# might create problems. So to minimize the damage, we will simply statically define the mapping here,
	# in the way they usually occure in an object. Howgh.
	my $prefixmap = {
		"http://phaidra.univie.ac.at/XML/metadata/V1.0" => 'ns0', 
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0" => 'ns1',  	
		"http://phaidra.univie.ac.at/XML/metadata/extended/V1.0" => 'ns2', 
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/entity" => 'ns3',
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/requirement" => 'ns4',
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational" => 'ns5',
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/annotation" => 'ns6',
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/classification" => 'ns7',
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/organization" => 'ns8',
		"http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0" =>	'ns9',
		"http://phaidra.univie.ac.at/XML/metadata/provenience/V1.0" => 'ns10',
		"http://phaidra.univie.ac.at/XML/metadata/provenience/V1.0/entity" => 'ns11', 
		"http://phaidra.univie.ac.at/XML/metadata/digitalbook/V1.0" => 'ns12',
		"http://phaidra.univie.ac.at/XML/metadata/etheses/V1.0" => 'ns13'
	};
	my $forced_declarations = [
		"http://phaidra.univie.ac.at/XML/metadata/V1.0", 
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0",  	
		"http://phaidra.univie.ac.at/XML/metadata/extended/V1.0", 
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/entity",
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/requirement",
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/educational",
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/annotation",
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/classification",
		"http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/organization",
		"http://phaidra.univie.ac.at/XML/metadata/histkult/V1.0",
		"http://phaidra.univie.ac.at/XML/metadata/provenience/V1.0",
		"http://phaidra.univie.ac.at/XML/metadata/provenience/V1.0/entity", 
		"http://phaidra.univie.ac.at/XML/metadata/digitalbook/V1.0",
		"http://phaidra.univie.ac.at/XML/metadata/etheses/V1.0"
	];
	
	my $xml = '';
	my $writer = XML::Writer->new( 
		OUTPUT => \$xml,
		NAMESPACES => 1,
        PREFIX_MAP => $prefixmap,
        FORCED_NS_DECLS => $forced_declarations,
        DATA_MODE => 1
	);
	
	$writer->startTag(["http://phaidra.univie.ac.at/XML/metadata/V1.0", "uwmetadata"]);
	$self->json_2_uwmetadata_rec($c, $metadata, $writer);
	$writer->endTag(["http://phaidra.univie.ac.at/XML/metadata/V1.0", "uwmetadata"]);
	
	$writer->end();
	
	return $xml;
}

# we need that an element in the json structure contains at least
# - xmlns
# - xmlname
# - ui_value
# - ordered
# - datatype
# - data_order (if any)
# - language (if any)
sub json_2_uwmetadata_rec(){
	
	my $self = shift;
	my $c = shift;	
	my $children = shift;
	my $writer = shift;		
	
	foreach my $child (@{$children}){
		
		my $children_size = defined($child->{children}) ? scalar (@{$child->{children}}) : 0;
		
		# some elements are not allowed to be empty, so if these are empty
		# we cannot add them to uwmetadata
		if($child->{ui_value} eq '' && $children_size == 0){
			next;	
		}
		
		my %attrs;
		if($child->{ordered}){
			$attrs{seq} = $child->{data_order};
		}
		if($child->{value_lang} ne ''){
			$attrs{language} = $child->{value_lang};
		}
	
		if (%attrs){
			$writer->startTag([$child->{xmlns}, $child->{xmlname}], %attrs);
		}else{
			$writer->startTag([$child->{xmlns}, $child->{xmlname}]);
		}
		
		if($children_size > 0){
			$self->json_2_uwmetadata_rec($c, $child->{children}, $writer);
		}else{				
			
			# copy the 'ui_value' to 'value' (or transform, if needed)
			if($child->{value} eq ''){
				$child->{value} = $child->{ui_value};
			}
			
			if(defined($child->{vocabularies})){
				# the value is an uri (namespace/id), but this is currently
				# not supported by phaidra, we have to strip it of the namespace
				foreach my $voc (@{$child->{vocabularies}}){
					if($child->{value} =~ m/($voc->{namespace})(\w+)/){
						$writer->characters($2);
					}	
				}
			}else{
				if($child->{datatype} eq 'Boolean'){
					$writer->characters($child->{value} ? 'yes' : 'no');
				}else{
					$writer->characters($child->{value});
				}
			}	
		}
		
		$writer->endTag([$child->{xmlns}, $child->{xmlname}]);	
	}		
}

sub save_uwmetadata(){
	
	my $self = shift;
	my $c = shift;	
	my $pid = shift;
	my $uwmetadata = shift;	
	
	my $res = { alerts => [], status => 200 };
	
	unless(defined($pid)){
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Missing PID. UWMETADATA datastream can only be saved to an existing object.'};
		$res->{status} = 500;	
		return $res;
	}
	unless($pid =~ m/^[a-zA-Z\-]+:[0-9]+$/){
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Malformed PID: $pid'};
		$res->{status} = 500;	
		return $res;
	}
	
	if($c->app->config->{validate_uwmetadata}){
		$c->app->log->info("Validating UWMETADATA for object $pid...");
		my $valres = $self->validate_uwmetadata($c, $pid, $uwmetadata);
		if($valres->{status} != 200){
			$c->app->log->info("Validating UWMETADATA for object $pid...failed:".$c->app->dumper($valres->{alerts}));
			$res->{status} = $valres->{status};
			unshift @{$res->{alerts}}, @{$valres->{alerts}};
			unshift @{$res->{alerts}}, { type => 'danger', msg => 'Error validating metadata'};
			return $res;
		}else{
			$c->app->log->info("Validating UWMETADATA for object $pid...success.");
			unshift @{$res->{alerts}}, @{$valres->{alerts}};
		}
	}
	
	$c->app->log->debug("Connecting to ".$c->app->config->{phaidra}->{fedorabaseurl}."...");
	my $phaidra = Phaidra::API->new(
		$c->app->config->{phaidra}->{fedorabaseurl}, 
		$c->app->config->{phaidra}->{staticbaseurl}, 
		$c->app->config->{phaidra}->{fedorastylesheeturl}, 
		$c->app->config->{phaidra}->{proaiRepositoryIdentifier}, 
		$c->app->config->{phaidra}->{username}, 
		$c->app->config->{phaidra}->{password}
	);
	
	# we are only changing UWMETADATA so we don't have to load & save object	
	my $soap = $phaidra->getSoap("apim");
	unless(defined($soap)){
		unshift @{$res->{alerts}}, { type => 'danger', msg => 'Cannot create SOAP connection to '.$c->app->config->{phaidra}->{fedorabaseurl}};
		$res->{status} = 500;	
		return $res;
	}
	$c->app->log->debug("Connected");
	my $soapres = $soap->modifyDatastreamByValue($pid, "UWMETADATA", '', $c->app->config->{phaidra}->{uwmetadatalabel}, "text/xml", '', SOAP::Data->type(base64 => $uwmetadata), 'DISABLED', 'none', 'Modified by PhaidraAPI (rest)', SOAP::Data->type(boolean => 0));
	if($soapres->fault)
	{
		$c->app->log->error("Saving UWMETADATA for $pid failed.");		
		$res->{status} = 500;	
		unshift @{$res->{alerts}}, { type => 'danger', msg => "Saving UWMETADATA failed: ".$soapres->faultcode.": ".$soapres->faultstring};
		return $res;
	}
	$c->app->log->debug("Saving UWMETADATA for $pid successful.");
	
	return $res;
}

1;
__END__
