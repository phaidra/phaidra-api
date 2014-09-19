package PhaidraAPI::Model::Rights;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;

sub json_2_xml {
	
    my ($self, $c, $rights) = @_;
    
    my $xml = '<uwr:rights xmlns:uwr="http://phaidra.univie.ac.at/XML/V1.0/rights"><uwr:allow>';
    while(my($k, $v) = each %{$rights}){
    	if($k eq 'username'){
    		if(ref($v) eq 'ARRAY'){
    			foreach my $it (@{$v}){
    				$xml .= "<uwr:username>$it</uwr:username>"
    			}
    		}else{
    			$xml .= "<uwr:username>$v</uwr:username>"
    		}	
    	}
    	if($k eq 'department'){
    		if(ref($v) eq 'ARRAY'){
    			foreach my $it (@{$v}){
    				$xml .= "<uwr:department>$it</uwr:department>"
    			}
    		}else{
    			$xml .= "<uwr:department>$v</uwr:department>"
    		}
    			
    	}
    }
        
    $xml .= '</uwr:allow></uwr:rights>';
    
	return $xml;
 
}

1;
__END__
