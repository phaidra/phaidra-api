package PhaidraAPI::Controller::Oai;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Data::MessagePack;
use MIME::Base64 qw(encode_base64url decode_base64url);
use DateTime;
use DateTime::Format::ISO8601;
use DateTime::Format::Strptime;
use Clone qw(clone);

my $DEFAULT_LIMIT = 100;

my $VERBS = {
  GetRecord => {
    valid    => {metadataPrefix => 1, identifier => 1},
    required => [qw(metadataPrefix identifier)],
  },
  Identify        => {valid => {}, required => []},
  ListIdentifiers => {
    valid => {
      metadataPrefix  => 1,
      from            => 1,
      until           => 1,
      set             => 1,
      resumptionToken => 1
    },
    required => [qw(metadataPrefix)],
  },
  ListMetadataFormats =>
    {valid => {identifier => 1, resumptionToken => 1}, required => []},
  ListRecords => {
    valid => {
      metadataPrefix  => 1,
      from            => 1,
      until           => 1,
      set             => 1,
      resumptionToken => 1
    },
    required => [qw(metadataPrefix)],
  },
  ListSets => {valid => {resumptionToken => 1}, required => []},
};

sub _deserialize {
  my ($data) = @_;
  my $mp = Data::MessagePack->new->utf8;
  return $mp->unpack(decode_base64url($data));
}

sub _serialize {
  my ($data) = @_;
  my $mp = Data::MessagePack->new->utf8;
  return encode_base64url($mp->pack($data));
}

sub _new_token {
  my ($settings, $hits, $params, $from, $until, $old_token) = @_;

  my $n = $old_token && $old_token->{_n} ? $old_token->{_n} : 0;
  $n += $hits->size;

  return unless $n < $hits->total;

  my $strategy = $settings->{search_strategy};

  my $token;

  if ($hits->more) {
    $token = {start => $hits->start + $hits->limit};
  } else {
    return;
  }

  $token->{_n} = $n;
  $token->{_s} = $params->{set} if defined $params->{set};
  $token->{_m} = $params->{metadataPrefix} if defined $params->{metadataPrefix};
  $token->{_f} = $from if defined $from;
  $token->{_u} = $from if defined $until;
  return $token;
}

=cut1
sub _search {
    my ($settings, $bag, $q, $token) = @_;

    my $strategy = $settings->{search_strategy};

    my %args = (
        %{$settings->{default_search_params}},
        limit     => $settings->{limit} // $DEFAULT_LIMIT,
        cql_query => $q,
    );
    if ($token) {
        if ($strategy eq 'paginate' && exists $token->{start}) {
            $args{start} = $token->{start};
        }
        elsif ($strategy eq 'es.scroll' && exists $token->{scroll_id}) {
            $args{scroll_id} = $token->{scroll_id};
        }
    }

    $bag->search(%args);
}

sub oai_provider {
    my ($path, %opts) = @_;

    my $setting = clone(plugin_setting);

    my $bag = Catmandu->store($opts{store} || $setting->{store})
        ->bag($opts{bag} || $setting->{bag});

    $setting->{granularity} //= "YYYY-MM-DDThh:mm:ssZ";

    # TODO this was for backwards compatibility. Remove?
    if ($setting->{filter}) {
        $setting->{cql_filter} = delete $setting->{filter};
    }

    $setting->{default_search_params} //= {};

    $setting->{search_strategy} //= 'paginate';

    # TODO expire scroll_id if finished
    # TODO set resumptionToken expirationDate
    if ($setting->{search_strategy} eq 'es.scroll') {
        $setting->{default_search_params}{scroll} //= '10m';
    }

    my $branding = "";
    if (my $icon = $setting->{collectionIcon}) {
        if (my $url = $icon->{url}) {
            $branding .= <<TT;
<description>
<branding xmlns="http://www.openarchives.org/OAI/2.0/branding/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/branding/ http://www.openarchives.org/OAI/2.0/branding.xsd">
<collectionIcon>
<url>$url</url>
TT
            for my $tag (qw(link title width height)) {
                my $val = $icon->{$tag} // next;
                $branding .= "<$tag>$val</$tag>\n";
            }

            $branding .= <<TT;
</collectionIcon>
</branding>
</description>
TT
        }
    }

   

    my $admin_email = $setting->{adminEmail} // [];
    $admin_email = [$admin_email] unless is_array_ref($admin_email);
    $admin_email
        = join('', map {"<adminEmail>$_</adminEmail>"} @$admin_email);

    my @identify_extra_fields;
    for my $i_field (qw(description compression)) {
        my $i_value = $setting->{$i_field} // [];
        $i_value = [$i_value] unless is_array_ref($i_value);
        push @identify_extra_fields,
            join('', map {"<$i_field>$_</$i_field>"} @$i_value);
    }

    my $template_identify = <<TT;
$template_header
<Identify>
<repositoryName>$setting->{repositoryName}</repositoryName>
<baseURL>[% uri_base %]</baseURL>
<protocolVersion>2.0</protocolVersion>
$admin_email
<earliestDatestamp>[% earliest_datestamp %]</earliestDatestamp>
<deletedRecord>$setting->{deletedRecord}</deletedRecord>
<granularity>$setting->{granularity}</granularity>
<description>
    <oai-identifier xmlns="http://www.openarchives.org/OAI/2.0/oai-identifier"
                    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                    xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai-identifier http://www.openarchives.org/OAI/2.0/oai-identifier.xsd">
        <scheme>oai</scheme>
        <repositoryIdentifier>$setting->{repositoryIdentifier}</repositoryIdentifier>
        <delimiter>$setting->{delimiter}</delimiter>
        <sampleIdentifier>$setting->{sampleIdentifier}</sampleIdentifier>
    </oai-identifier>
</description>
@identify_extra_fields
$branding
</Identify>
$template_footer
TT

    my $template_list_identifiers = <<TT;
$template_header
<ListIdentifiers>
[%- FOREACH records %]
$template_record_header
[%- END %]
[%- IF resumption_token %]
<resumptionToken completeListSize="[% total %]">[% resumption_token %]</resumptionToken>
[%- ELSE %]
<resumptionToken completeListSize="[% total %]"/>
[%- END %]
</ListIdentifiers>
$template_footer
TT

    my $template_list_records = <<TT;
$template_header
<ListRecords>
[%- FOREACH records %]
<record>
$template_record_header
[%- UNLESS deleted %]
<metadata>
[% metadata %]
</metadata>
[%- END %]
</record>
[%- END %]
[%- IF resumption_token %]
<resumptionToken completeListSize="[% total %]">[% resumption_token %]</resumptionToken>
[%- ELSE %]
<resumptionToken completeListSize="[% total %]"/>
[%- END %]
</ListRecords>
$template_footer
TT

    my $template_list_metadata_formats = "";
    $template_list_metadata_formats .= <<TT;
$template_header
<ListMetadataFormats>
TT
    for my $format (values %$metadata_formats) {
        $template_list_metadata_formats .= <<TT;
<metadataFormat>
    <metadataPrefix>$format->{metadataPrefix}</metadataPrefix>
    <schema>$format->{schema}</schema>
    <metadataNamespace>$format->{metadataNamespace}</metadataNamespace>
</metadataFormat>
TT
    }
    $template_list_metadata_formats .= <<TT;
</ListMetadataFormats>
$template_footer
TT

    my $template_list_sets = <<TT;
$template_header
<ListSets>
TT
    for my $set (values %$sets) {
        $template_list_sets .= <<TT;
<set>
    <setSpec>$set->{setSpec}</setSpec>
    <setName>$set->{setName}</setName>
TT

        my $set_descriptions = $set->{setDescription} // [];
        $set_descriptions = [$set_descriptions]
            unless is_array_ref($set_descriptions);
        $template_list_sets .= "<setDescription>$_</setDescription>"
            for @$set_descriptions;

        $template_list_sets .= <<TT;
</set>
TT
    }
    $template_list_sets .= <<TT;
</ListSets>
$template_footer
TT

    my $fix = $opts{fix} || $setting->{fix};
    if ($fix) {
        $fix = Catmandu::Fix->new(fixes => $fix);
    }
    my $sub_deleted       = $opts{deleted}       || sub {0};
    my $sub_set_specs_for = $opts{set_specs_for} || sub {[]};


=cut

sub _get_fields {
  my $self = shift;
  my $rec = shift;

  my @fields;
  for my $k (keys %{$rec}) {
    if ($k =~ m/dc_([a-z]+)_?([a-z]+)?/) {
      my %field;
      $field{name} = $1;
      $field{values} = $rec->{$k};
      $field{lang} = $2 if $2;
      push @fields, \%field;
    }
  }
  return \@fields;
}

sub handler {
  my $self = shift;

  my $ns = "oai:".$self->config->{phaidra}->{proaiRepositoryIdentifier}.":";
  my $uri_base = $self->config->{baseurl} . '/' . $self->config->{basepath};
  my $response_date = DateTime->now->iso8601 . 'Z';
  my $params = $self->req->params->to_hash;
  my $errors = [];
  my $set;
  my $sets;
  my $verb = $params->{'verb'};
  $self->stash(
    uri_base      => $uri_base,
    request_uri   => $uri_base,
    response_date => $response_date,
    errors        => $errors,
    params        => $params,
    ns            => $ns
  );

  if ($verb and my $spec = $VERBS->{$verb}) {
    my $valid    = $spec->{valid};
    my $required = $spec->{required};

    if ($valid->{resumptionToken} and exists $params->{resumptionToken})
    {
      if (keys(%$params) > 2) {
        push @$errors, [badArgument => "resumptionToken cannot be combined with other parameters"];
      }
    } else {
      for my $key (keys %$params) {
        next if $key eq 'verb';
        unless ($valid->{$key}) {
          push @$errors, [badArgument => "parameter $key is illegal"];
        }
      }
      for my $key (@$required) {
        unless (exists $params->{$key}) {
          push @$errors, [badArgument => "parameter $key is missing"];
        }
      }
    }
  }
  else {
    push @$errors, [badVerb => "illegal OAI verb"];
  }

  if (@$errors) {
    $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
    return;
  }

  if (exists $params->{resumptionToken}) {
    if ($verb eq 'ListSets') {
      push @$errors, [badResumptionToken => "resumptionToken isn't necessary"];
    } else {
      eval {
        my $token = $self->_deserialize($params->{resumptionToken});
        $params->{set}            = $token->{_s} if defined $token->{_s};
        $params->{metadataPrefix} = $token->{_m} if defined $token->{_m};
        $params->{from}           = $token->{_f} if defined $token->{_f};
        $params->{until}          = $token->{_u} if defined $token->{_u};
        $self->stash(token => $token);
      };
      if($@){
        push @$errors, [badResumptionToken => "resumptionToken is not in the correct format"];
      };
    }
  }

  if (exists $params->{set}) {
    my $mongosets = $self->mongo->get_collection('oai_sets')->find();
    while (my $s = $mongosets->next) {
      $sets->{$s->{setSpec}} = $s;
    }
    unless ($sets) {
      push @$errors, [noSetHierarchy => "sets are not supported"];
    }
    unless ($set = $sets->{$params->{set}}) {
      push @$errors, [badArgument => "set does not exist"];
    }
  }

  if (exists $params->{metadataPrefix}) {
    unless ($params->{metadataPrefix} eq 'oai_dc') {
      push @$errors, [cannotDisseminateFormat => "metadataPrefix $params->{metadataPrefix} is not supported" ];
    }
  }

  if (@$errors) {
    $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
    return;
  }

  if ($verb eq 'GetRecord') {
    my $id = $params->{identifier};
    $id =~ s/^$ns//;

    my $rec = $self->mongo->get_collection('oai_records')->find_one({"pid" => $id});

    if (defined $rec) {
      # $self->app->log->debug("XXXXXXXXXXXXXX ".$self->app->dumper($self->_get_fields($rec)));
      $self->stash(r => $rec, fields => $self->_get_fields($rec));
      $self->render(template => 'oai/get_record', format => 'xml', handler => 'ep');
      return;
    }
    push @$errors, [idDoesNotExist => "identifier ".$params->{identifier}." is unknown or illegal"];
    $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
    return;

  } elsif ($verb eq 'Identify') {
    # $vars->{earliest_datestamp} = $setting->{earliestDatestamp} || do {
    #   my $hits = $bag->search(
    #     %{$setting->{default_search_params}},
    #     cql_query => $setting->{cql_filter} || 'cql.allRecords',
    #     limit     => 1,
    #     sru_sortkeys => $setting->{datestamp_field},
    #   );
    #   if (my $rec = $hits->first) {
    #     $format_datestamp->($rec->{$setting->{datestamp_field}});
    #   }
    #   else {
    #     '1970-01-01T00:00:01Z';
    #   }
    # };
    # return $render->(\$template_identify, $vars);
  } elsif ($verb eq 'ListIdentifiers' || $verb eq 'ListRecords') {
    # my $from  = $params->{from};
    # my $until = $params->{until};

    # for my $datestamp (($from, $until)) {
    #     $datestamp || next;
    #     if ($datestamp !~ /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}Z)?$/) {
    #         push @$errors, [badArgument => "datestamps must have the format YYYY-MM-DD or YYYY-MM-DDThh:mm:ssZ"];
    #         $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
    #         return;
    #     }
    # }

    # if ($from && $until && length($from) != length($until)) {
    #   push @$errors, [ badArgument => "datestamps must have the same granularity" ];
    #   $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
    #   return;
    # }

    # if ($from && $until && $from gt $until) {
    #   push @$errors, [badArgument => "from is more recent than until"];
    #   $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
    #   return;
    # }

    # if ($from && length($from) == 10) {
    #   $from = "${from}T00:00:00Z";
    # }
    # if ($until && length($until) == 10) {
    #   $until = "${until}T23:59:59Z";
    # }

    # my @cql;
    # my $cql_from  = $from;
    # my $cql_until = $until;
    # if (my $pattern = $setting->{datestamp_pattern}) {
    #     $cql_from
    #         = DateTime::Format::ISO8601->parse_datetime($from)
    #         ->strftime($pattern)
    #         if $cql_from;
    #     $cql_until
    #         = DateTime::Format::ISO8601->parse_datetime($until)
    #         ->strftime($pattern)
    #         if $cql_until;
    # }

    # push @cql, qq|($setting->{cql_filter})| if $setting->{cql_filter};
    # push @cql, qq|($format->{cql})|         if $format->{cql};
    # push @cql, qq|($set->{cql})|            if $set && $set->{cql};
    # push @cql, qq|($setting->{datestamp_field} >= "$cql_from")|
    #     if $cql_from;
    # push @cql, qq|($setting->{datestamp_field} <= "$cql_until")|
    #     if $cql_until;
    # unless (@cql) {
    #     push @cql, "(cql.allRecords)";
    # }

    # my $search = _search($setting, $bag, join(' and ', @cql), $vars->{token});

    # unless ($search->total) {
    #   push @$errors, [noRecordsMatch => "no records found"];
    #   $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
    #   return;
    # }

    # if (
    #     defined(
    #         my $new_token = _new_token(
    #             $setting, $search, $params,
    #             $from,    $until,  $vars->{token}
    #         )
    #     )
    #     )
    # {
    #     $vars->{resumption_token} = $self->_serialize($new_token);
    # }

    # $vars->{total} = $search->total;

    # if ($verb eq 'ListIdentifiers') {
    #     $vars->{records} = [
    #         map {
    #             my $rec = $_;
    #             my $id  = $rec->{$bag->id_key};

    #             if ($fix) {
    #                 $rec = $fix->fix($rec);
    #             }

    #             {
    #                 id        => $id,
    #                 datestamp => $format_datestamp->(
    #                     $rec->{$setting->{datestamp_field}}
    #                 ),
    #                 deleted => $sub_deleted->($rec),
    #                 setSpec => $sub_set_specs_for->($rec),
    #             };
    #         } @{$search->hits}
    #     ];
    #     return $render->(\$template_list_identifiers, $vars);
    # } else {
    #     $vars->{records} = [
    #         map {
    #             my $rec = $_;
    #             my $id  = $rec->{$bag->id_key};

    #             if ($fix) {
    #                 $rec = $fix->fix($rec);
    #             }

    #             my $deleted = $sub_deleted->($rec);

    #             my $rec_vars = {
    #                 id        => $id,
    #                 datestamp => $format_datestamp->(
    #                     $rec->{$setting->{datestamp_field}}
    #                 ),
    #                 deleted => $deleted,
    #                 setSpec => $sub_set_specs_for->($rec),
    #             };
    #             unless ($deleted) {
    #                 my $metadata = "";
    #                 my $exporter = Catmandu::Exporter::Template->new(
    #                     %$template_options,
    #                     template => $format->{template},
    #                     file     => \$metadata,
    #                 );
    #                 if ($format->{fix}) {
    #                     $rec = $format->{fix}->fix($rec);
    #                 }
    #                 $exporter->add($rec);
    #                 $exporter->commit;
    #                 $rec_vars->{metadata} = $metadata;
    #             }
    #             $rec_vars;
    #         } @{$search->hits}
    #     ];
    #     return $render->(\$template_list_records, $vars);
    # }

  } elsif ($verb eq 'ListMetadataFormats') {
    # if (my $id = $params->{identifier}) {
    #   $id =~ s/^$ns//;
    #   unless ($bag->get($id)) {
    #     push @$errors, [idDoesNotExist => "identifier $params->{identifier} is unknown or illegal"];
    #     $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
    #     return;
    #   }
    # }
    # return $render->(\$template_list_metadata_formats, $vars);
  } elsif ($verb eq 'ListSets') {
    # return $render->(\$template_list_sets, $vars);
  }

}

1;
