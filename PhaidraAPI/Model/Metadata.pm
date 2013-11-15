package PhaidraAPI::Model::Metadata;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use Switch;

sub metadata_format {
	
    my ($self, $c, $v) = @_;
 
 	my $cachekey = 'metadata_format_'.$v;
 	if($v eq '1'){
 		
 		my $res = $c->app->chi->get($cachekey);
  		
    	if($res){    		
    		$c->app->log->debug("[cache hit] $cachekey");
    	}else{    		
    		$c->app->log->debug("[cache miss] $cachekey");
    		
    		$res = $self->get_metadata_format($c);		
  
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

sub get_metadata_format {
	
	my ($self, $c) = @_;
	
	my %format;
	my @metadata_format;
	my %id_hash;
	
	my $sth;
	my $ss;
	
	$ss = qq/SELECT 
			m.MID, m.VEID, m.xmlname, m.xmlns, m.lomref, 
			m.searchable, m.mandatory, m.autofield, m.editable, m.OID,
			m.datatype, m.valuespace, m.MID_parent, m.cardinality, m.ordered, m.fgslabel,
			m.VID, m.defaultvalue, m.sequence
			FROM metadata m
			ORDER BY m.sequence ASC/;
	$sth = $c->app->db_metadata->prepare($ss) or print $c->app->db_metadata->errstr;
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
	my $sequence; # order of the element among it's siblings
	
	$sth->bind_columns(undef, \$mid, \$veid, \$xmlname, \$xmlns, \$lomref, \$searchable, \$mandatory, \$autofield, \$editable, \$oid, \$datatype, \$valuespace, \$mid_parent, \$cardinality, \$ordered, \$fgslabel, \$vid, \$defaultvalue, \$sequence);
	
	# fill the hash with raw table data
	while($sth->fetch) {			
		$format{$mid} = { 
			veid => $veid, 
			xmlname => $xmlname, 
			xmlns => $xmlns, 
			lomref => $lomref, 
			searchable => $searchable, 
			mandatory => $mandatory, 
			autofield => $autofield, 
			editable => $editable, 
			oid => $oid, 
			datatype => $datatype,  
			mid_parent => $mid_parent, 
			cardinality => $cardinality, 
			ordered => $ordered, 
			fgslabel => $fgslabel, 
			vid => $vid, 
			defaultvalue => $defaultvalue, 
			sequence => $sequence, 
			helptext => 'No helptext defined.' 
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
			case ("CharacterString" || "Faculty" || "Department" || "SPL" || "Curriculum" || "GPS" || "Duration" || "FileSize") { $format{$mid}->{input_type} = "input_text" }
			
			case "LangString"	{ $format{$mid}->{input_type} = "input_text_lang" }
			
			case "DateTime"	{ $format{$mid}->{input_type} = "input_datetime" }
						
			case ("Vocabulary" || "License" || "Taxon") { $format{$mid}->{input_type} = "select" }
			
			case "Boolean"	{ $format{$mid}->{input_type} = "input_checkbox" }
			
			case "Node"	{ $format{$mid}->{input_type} = "node" }
			
			else { $format{$mid}->{input_type} = "" }
		}
		
		# TODO
		# irdata - input_hidden
		# description - input_textarea_lang
		# contribution - input_contribution
		
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
		push @metadata_format, $element;
	}
	
	# and sort it
	@metadata_format = sort { $a->{sequence} <=> $b->{sequence} } @metadata_format;	
	
	# and sort the children
	foreach my $key (keys %parents){
		@{$id_hash{$key}{children}} = sort { $a->{sequence} <=> $b->{sequence} } @{$parents{$key}{children}};		
	}
	
	# get the element labels
	$ss = qq/SELECT m.mid, ve.entry, ve.isocode FROM metadata AS m LEFT JOIN vocabulary_entry AS ve ON ve.veid = m.veid;/;
	$sth = $c->app->db_metadata->prepare($ss) or print $c->app->db_metadata->errstr;
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
			$sth = $c->app->db_metadata->prepare($ss) or print $c->app->db_metadata->errstr;
			$sth->execute($element->{vid});
			
			my $desc; # some short text describing the vocabulary (it's not multilanguage, sorry)
			my $vocabulary_namespace; # there's none, i'm fabricating this
			
			$sth->bind_columns(undef, \$desc);
			$sth->fetch;
			
			$vocabulary{description} = $desc;
			$vocabulary{namespace} = $element->{xmlns}.'/voc_'.$element->{vid}.'/';
			
			# get vocabulary values/codes
			$ss = qq/SELECT veid, entry, isocode FROM vocabulary_entry WHERE vid = (?);/;
			$sth = $c->app->db_metadata->prepare($ss) or print $c->app->db_metadata->errstr;
			$sth->execute($element->{vid});
			
			my $veid; # the code, together with namespace this creates URI, that's the current hack
			my $entry; # value label (eg 'Wood-engraver')
			my $isocode; # 2 letter isocode defining language of the entry
			
			$sth->bind_columns(undef, \$veid, \$entry, \$isocode);
			
			# fetshing data using hash, so that we quickly find the place for the entry but later ... [x] 
			while($sth->fetch) {
				$vocabulary{'terms'}->{$veid}->{uri} = $vocabulary{namespace}.$veid; # this gets overwritten for the same entry
				$vocabulary{'terms'}->{$veid}->{$isocode} = $entry; # this should always contain another language for the same entry
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

	}

	# delete ids, we don't need them
	while ( my ($key, $element) = each %id_hash ){
		delete $element->{vid};
		delete $element->{veid};
		delete $element->{mid_parent};
	}
	
	return \@metadata_format;
}


1;
__END__
