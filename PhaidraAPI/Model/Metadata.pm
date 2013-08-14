package PhaidraAPI::Model::Metadata;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;

sub metadata_format {
	
    my ($self, $app) = @_;
 
    return $self->get_metadata_format($app);	
}



sub get_metadata_format {
	
	my ($self, $app, $mid_parent) = @_;
	
	return { root => 'tbd' };
=cut
	my $sth;
	my $ss;

	if (defined($mid_parent)) {
		$ss = qq/SELECT m.mid, m.mandatory, m.xmlname, m.xmlns, m.veid, m.lomref, m.searchable, m.autofield, m.editable, m.oid, m.datatype, m.mid_parent, m.cardinality, m.ordered, m.fgslabel, m.vid, m.defaultvalue, m.sequence, m.valuespace
			FROM metadata m
			WHERE m.mid_parent = ?
			ORDER BY m.sequence ASC/;
			$sth = $app->db_metadata->prepare($ss) or print $app->db_metadata->errstr;
			$sth->execute($mid_parent);
	} else {
		$ss = qq/SELECT m.mid, m.mandatory, m.xmlname, m.xmlns, m.veid, m.lomref, m.searchable, m.autofield, m.editable, m.oid, m.datatype, m.mid_parent, m.cardinality, m.ordered, m.fgslabel, m.vid, m.defaultvalue, m.sequence, m.valuespace
			FROM metadata m
			WHERE m.mid_parent is null
			ORDER BY m.sequence ASC/;
			$sth = $app->db_metadata->prepare($ss) or print $app->db_metadata->errstr;
			$sth->execute();
	}
	my ($mid, $mandatory, $xmlname, $xmlns, $veid, $lomref, $searchable, $autofield, $editable, $oid, $datatype, $mmid_parent, $cardinality, $ordered, $fgslabel, $vid, $defaultvalue, $sequence, $valuespace);
	$sth->bind_columns(undef, \$mid, \$mandatory, \$xmlname, \$xmlns, \$veid, \$lomref, \$searchable, \$autofield, \$editable, \$oid, \$datatype, \$mmid_parent, \$cardinality, \$ordered, \$fgslabel, \$vid, \$defaultvalue, \$sequence, \$valuespace);
	
	my $current_mid = -1;
	my $currentElement;
	my $root;
	
	while($sth->fetch) {
		
		# if $mid == $current_mid then this row is the same as the one before only with another description
		if($mid != $current_mid) {
			
			if(defined($currentElement)) {
				my $metadata_subs = $self->get_metadata_format($app, $current_mid);
				my $children = defined($metadata_subs->{metadatas}) ? scalar @{$metadata_subs->{metadatas}} : 0;
				if ($children > 0) {
					push @{$currentElement->{metadatas}}, $metadata_subs;
				}
				push @{$root->{metadatas}}, $currentElement; 

			}
			
			$currentElement->{mandatory} = defined($mandatory) ? $mandatory : "";
			$currentElement->{ID} = defined($mid) ? $mid : "";
			$currentElement->{forxmlname} = defined($xmlname) ? $xmlname : "";
			$currentElement->{fornamespace} = defined($xmlns) ? $xmlns : "";
			$currentElement->{veid} = defined($veid) ? $veid : "";
			$currentElement->{lomref} = defined($lomref) ? $lomref : "";
			$currentElement->{searchable} = defined($searchable) ? $searchable : "";
			$currentElement->{autofield} = defined($autofield) ? $autofield : "";
			$currentElement->{editable} = defined($editable) ? $editable : "";
			$currentElement->{oid} = defined($oid) ? $oid : "";
			$currentElement->{datatype} = defined($datatype) ? $datatype : "";
			$currentElement->{mid_parent} = defined($mmid_parent) ? $mmid_parent : "";
			$currentElement->{cardinality} = defined($cardinality) ? $cardinality : "";
			$currentElement->{ordered} = defined($ordered) ? $ordered : "";
			$currentElement->{fgslabel} = defined($fgslabel) ? $fgslabel : "";
			$currentElement->{vid} = defined($vid) ? $vid : "";
			$currentElement->{defaultvalue} = defined($defaultvalue) ? $defaultvalue : "";
			$currentElement->{sequence} = defined($sequence) ? $sequence : "";
			$currentElement->{valuespace} = defined($valuespace) ? $valuespace : "";
			
			if($sth->rows <= 2)
            {
				my $metadata_subs = $self->get_metadata_format($app, $current_mid);
				my $children = defined($metadata_subs->{metadatas}) ? scalar @{$metadata_subs->{metadatas}} : 0;
				if ($children > 0) {
					push @{$currentElement->{metadatas}}, $metadata_subs;
				}
				push @{$root->{metadatas}}, $currentElement;
			}
			
			$current_mid = $mid;
		}
	
	}
	push (@{$root->{metadatas}}, $currentElement) if(defined($currentElement));
	
	my $rootchildren = defined($root->{metadatas}) ? scalar @{$root->{metadatas}} : 0;
	my $tmpelmchildren = defined($currentElement->{metadatas}) ? scalar @{$currentElement->{metadatas}} : 0;
	if ($rootchildren > 0 && $tmpelmchildren > 0) {
		my $metadata_subs = $self->get_metadata_format($app, $current_mid);
		my $children = defined($metadata_subs->{metadatas}) ? scalar @{$metadata_subs->{metadatas}} : 0;
		if ($children > 0) {
			push @{$currentElement->{metadatas}}, $metadata_subs;
		}
		push @{$root->{metadatas}}, $currentElement;
	}
	
	return $root;
=cut	
}

1;
__END__
