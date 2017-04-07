package PhaidraAPI::Model::Relationships;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;
use PhaidraAPI::Model::Search;

our %version_map = (
  'info:eu-repo/semantics/draft' => 1,
  'info:eu-repo/semantics/submittedVersion' => 1,
  'info:eu-repo/semantics/acceptedVersion' => 1,
  'info:eu-repo/semantics/publishedVersion' => 1,
  'info:eu-repo/semantics/updatedVersion' => 1
);

sub get {
  my ($self, $c, $pid, $search_model) = @_;

  my $res = { alerts => [], status => 200 };

  my %rels;

  # collection relationships
  my $r_col = $self->_get_collection_relationships($c, $pid, $search_model);
  if($r_col->{status} ne 200){
    $res->{alerts} = [{ type => 'danger', msg => "Error getting collection relationships for $pid, skipping" }];
    for $a (@{$r_col->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }else{  
    if(scalar @{$r_col->{haspart}} > 0){
      $rels{haspart} = $r_col->{haspart};
    }
    if(scalar @{$r_col->{ispartof}} > 0){
      $rels{ispartof} = $r_col->{ispartof};
    }
  }

  # isBackSideOf  
  my $r_bs = $search_model->triples($c, "<info:fedora/$pid> <http://phaidra.org/XML/V1.0/relations#isBackSideOf> *", 0);
  if($r_bs->{status} ne 200){
    $res->{alerts} = [{ type => 'danger', msg => "Error getting isBackSideOf relationships for $pid, skipping" }];
    for $a (@{$r_bs->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }else{  
  	for my $t (@{$r_bs->{result}}){
  	  my $object = @$t[2];
      $object =~ m/^<info:fedora\/(.*)>$/;
      $rels{isbacksideof} = $1; 
    } 
  }

  my $r_rbs = $search_model->triples($c, "* <http://phaidra.org/XML/V1.0/relations#isBackSideOf> <info:fedora/$pid>", 0);
  if($r_rbs->{status} ne 200){
    $res->{alerts} = [{ type => 'danger', msg => "Error getting reverse isBackSideOf relationships for $pid, skipping" }];
    for $a (@{$r_rbs->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }else{  
    for my $t (@{$r_rbs->{result}}){
      my $object = @$t[2];
      $object =~ m/^<info:fedora\/(.*)>$/;
      $rels{hasbackside} = $1; 
    } 
  }

  # later versions
  my $r_lv = $search_model->triples($c, "<info:fedora/$pid> <http://phaidra.univie.ac.at/XML/V1.0/relations#hasSuccessor> *", 0);
  if($r_lv->{status} ne 200){
    $res->{alerts} = [{ type => 'danger', msg => "Error getting hasSuccessor relationships for $pid, skipping" }];
    for $a (@{$r_lv->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }else{  
  	for my $t (@{$r_lv->{result}}){
  	  my $object = @$t[2];
      $object =~ m/^<info:fedora\/(.*)>$/;
      $rels{successor} = $1;  
    }
  }

  # previous versions
  my $r_pv = $search_model->triples($c, "* <http://phaidra.univie.ac.at/XML/V1.0/relations#hasSuccessor> <info:fedora/$pid>", 0);
  if($r_pv->{status} ne 200){
    $res->{alerts} = [{ type => 'danger', msg => "Error getting reverse hasSuccessor relationships for $pid, skipping" }];
    for $a (@{$r_pv->{alerts}}){
      push @{$res->{alerts}}, $a;
    }
  }else{  
  	for my $t (@{$r_pv->{result}}){
  	  my $subject = @$t[0];
      $subject =~ m/^<info:fedora\/(.*)>$/;
      $rels{predecessor} = $1;  
    }
  }

  # alternative versions and formats
  my %graph = ( 
    $pid => { 
      "http://phaidra.org/XML/V1.0/relations#isAlternativeFormatOf_checked" => 0,
      "http://phaidra.org/XML/V1.0/relations#isAlternativeVersionOf_checked" => 0 
    }
  );
  $self->_get_relations_rec($c, $search_model, \%graph);

  my %formats;
  my %checked = ($pid => 0);
  $self->_get_alt_formats_rec($c, $search_model, $pid, $pid, \%graph, \%formats, \%checked);
  if(%formats){
    $rels{altformats} = \%formats;
  }

  my %versions;
  my %checkedv = ($pid => 0);
  $self->_get_alt_versions_rec($c, $search_model, $pid, $pid, \%graph, \%versions, \%checkedv);
  if(%versions){
    $rels{altversions} = \%versions;
  }

  $res->{relationships} = \%rels;
  return $res;

}

sub _get_collection_relationships {

  my ($self, $c, $pid, $search_model) = @_;

  my @haspart;
  my $r_mem = $search_model->triples($c, "<info:fedora/$pid> <info:fedora/fedora-system:def/relations-external#hasCollectionMember> *", 0);
  if($r_mem->{status} ne 200){
    return $r_mem;
  }
  for my $t (@{$r_mem->{result}}){
    my $object = @$t[2];
    $object =~ m/^<info:fedora\/(.*)>$/;
    push @haspart, $1;  
  }

  my @ispart;
  my $r_trip_r = $search_model->triples($c, "* <info:fedora/fedora-system:def/relations-external#hasCollectionMember> <info:fedora/$pid>", 0);
  if($r_trip_r->{status} ne 200){
    return $r_trip_r;
  }
  for my $t (@{$r_trip_r->{result}}){
    my $subject = @$t[0];
    $subject =~ m/^<info:fedora\/(.*)>$/;
    push @ispart, $1;  
  }

  return { ispartof => \@ispart, haspart => \@haspart, status => 200 };
}

sub _get_alt_versions_rec {
  my ($self, $c, $search_model, $mainpid, $pid, $graph, $versions, $checked) = @_;
  my $r = "http://phaidra.org/XML/V1.0/relations#isAlternativeVersionOf";
  if($checked->{$pid}){
    return; 
  }
  for my $subject (keys %$graph){
    # get objects where pid is subject
    if($subject eq $pid){
      for my $object (@{$graph->{$subject}->{$r}}){               
        if(!exists($versions->{$object}) && ($object ne $mainpid)){                                                                     
          $versions->{$object} = $self->_get_version_type($c, $search_model, $object);
          $checked->{$pid} = 1;
          $self->_get_alt_versions_rec($c, $search_model, $mainpid, $object, $graph, $versions, $checked);
        }
      }       
    }
    # get subject where pid is object
    for my $object (@{$graph->{$subject}->{$r}}){
      if($object eq $pid && !exists($versions->{$subject}) && ($subject ne $mainpid)){                
        $versions->{$subject} = $self->_get_version_type($c, $search_model, $subject);
        $checked->{$pid} = 1;
        $self->_get_alt_versions_rec($c, $search_model, $mainpid, $subject, $graph, $versions, $checked);
      }       
    }
  }
       
  return $versions;       
}

sub _get_version_type {
  my ($self, $c, $search_model, $pid) = @_;

  my $r_trip = $search_model->triples($c, "<info:fedora/$pid> <http://purl.org/dc/elements/1.1/type> *", 0);
  if($r_trip->{status} ne 200){
    return;
  }   
  for my $t (@{$r_trip->{result}}){
  	if($version_map{@$t[2]}){
    	return @$t[2];
	  }
  }
}

sub _get_alt_formats_rec {
  my ($self, $c, $search_model, $mainpid, $pid, $graph, $formats, $checked) = @_;
  my $r = "http://phaidra.org/XML/V1.0/relations#isAlternativeFormatOf";
  if($checked->{$pid}){
    return; 
  }
  for my $subject (keys %$graph){
    # get objects where pid is subject
    if($subject eq $pid){
      for my $object (@{$graph->{$subject}->{$r}}){               
        if(!exists($formats->{$object}) && ($object ne $mainpid)){                                                                      
          $formats->{$object} = $self->_get_format($c, $search_model, $object);
          $checked->{$pid} = 1;
          $self->_get_alt_formats_rec($c, $search_model, $mainpid, $object, $graph, $formats, $checked);
        }
      }       
    }
    # get subject where pid is object
    for my $object (@{$graph->{$subject}->{$r}}){
      if($object eq $pid && !exists($formats->{$subject}) && ($subject ne $mainpid)){         
        $formats->{$subject} = $self->_get_format($c, $search_model, $subject);
        $checked->{$pid} = 1;
        $self->_get_alt_formats_rec($c, $search_model, $mainpid, $subject, $graph, $formats, $checked);
      }       
    }
  }
        
  return $formats;        
}

sub _get_format {
  my ($self, $c, $search_model, $pid) = @_;

  my $r_trip = $search_model->triples($c, "<info:fedora/$pid> <http://purl.org/dc/elements/1.1/format> *", 0);
  if($r_trip->{status} ne 200){
    return;
  }   
  for my $t (@{$r_trip->{result}}){
  	# we want the mime type, but who knows what's in dc.format, hence this dirty check
  	return @$t[2] if @$t[2] =~ /(\w+)\/(\w+)/; 
  }     
}

sub _get_relations_rec {
  my ($self, $c, $search_model, $elements) = @_; 

  my $newFound = 0;
  my @relations = ("http://phaidra.org/XML/V1.0/relations#isAlternativeFormatOf", "http://phaidra.org/XML/V1.0/relations#isAlternativeVersionOf");
  for my $relation (@relations){
    for my $pid (keys %$elements){                              
      # if not already checked..
      if($elements->{$pid}->{$relation."_checked"} eq 0){                                                     
        # ..then get all it's related elements ('what pids' are alternative version to 'this pid')..
        my $r_trip_r = $search_model->triples($c, "* <$relation> <info:fedora/$pid>", 0);
        if($r_trip_r->{status} ne 200){
          return;
        }   
        for my $t (@{$r_trip_r->{result}}){
		      my $subject = @$t[0];
		      $subject =~ m/^<info:fedora\/(.*)>$/;
		      my $neighbour = $1;
    		  # ..and if the related elements are not already in set, add them (as not checked)               
          if(!exists($elements->{$neighbour}->{$relation.'_checked'})){           
            for my $rel (@relations){           
              $elements->{$neighbour}->{$rel.'_checked'} = 0;
            }
            push @{$elements->{$neighbour}->{$relation}}, $pid;                     
            $newFound = 1;
          }  
		    }
                      
        # now the other direction of the relation ('this pid' is alternative version to 'what pids')
        my $r_trip = $search_model->triples($c, "<info:fedora/$pid> <$relation> *", 0);
        if($r_trip->{status} ne 200){
          return;
        }   
        for my $t (@{$r_trip->{result}}){
		      my $subject = @$t[0];
		      $subject =~ m/^<info:fedora\/(.*)>$/;
		      my $neighbour = $1;
		      if(!exists($elements->{$neighbour}->{$relation.'_checked'})){
            for my $rel (@relations){           
              $elements->{$neighbour}->{$rel.'_checked'} = 0;
            }                                               
            push @{$elements->{$pid}->{$relation}}, $neighbour;
            $newFound = 1;
          }        
        }

        $elements->{$pid}->{$relation.'_checked'} = 1;
      }
    }
  }

  if($newFound){    
    $self->_get_relations_rec($c, $search_model, $elements);  
  }
}

1;
__END__
