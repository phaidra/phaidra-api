package PhaidraAPI::Model::Geo;

use strict;
use warnings;
use v5.10;
use Mojo::Util qw(encode decode);
use base qw/Mojo::Base/;

sub json_2_xml {

    my ($self, $c, $geo) = @_;

    my $xml = '<?xml version="1.0" encoding="UTF-8"?><kml xmlns="http://www.opengis.net/kml/2.2"><Document>';
    foreach my $pm (@{$geo->{kml}->{document}->{placemark}}){

      $xml .= "<Placemark>";

      $xml .= "<name>".$pm->{name}."</name>" if $pm->{name};
      $xml .= "<description>".$pm->{description}."</description>" if $pm->{description};

      if($pm->{point}){
        if($pm->{point}->{coordinates}){
          $xml .= "<Point><coordinates>";
          if($pm->{point}->{coordinates}->{longitude} && $pm->{point}->{coordinates}->{latitude}){
            $xml .= $pm->{point}->{coordinates}->{longitude}.",".$pm->{point}->{coordinates}->{latitude}.",0";
          }
          $xml .= "</coordinates></Point>";
        }
      }

      if($pm->{polygon}){
        if($pm->{polygon}->{outerboundaryis}){
          if($pm->{polygon}->{outerboundaryis}->{linearring}){
            if($pm->{polygon}->{outerboundaryis}->{linearring}->{coordinates}){
              $xml .= "<Polygon><outerBoundaryIs><LinearRing><coordinates>";
              my $i = 0;
              foreach $c (@{$pm->{polygon}->{outerboundaryis}->{linearring}->{coordinates}}){
                $i++;
                $xml .= " " if($i > 1);
                if($c->{longitude} && $c->{latitude}){
                  $xml .= $c->{longitude}.",".$c->{latitude}.",0";
                }
              }
              $xml .= "</coordinates></LinearRing></outerBoundaryIs></Polygon>";
            }
          }
        }
      }

      $xml .= "</Placemark>";
    }

    $xml .= '</Document></kml>';

    return encode 'UTF-8', $xml;
}

1;
__END__
