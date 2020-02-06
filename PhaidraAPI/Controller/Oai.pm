package PhaidraAPI::Controller::Oai;

# based on https://github.com/LibreCat/Dancer-Plugin-Catmandu-OAI

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
  my ($self, $data) = @_;
  my $mp = Data::MessagePack->new->utf8;
  return $mp->unpack(decode_base64url($data));
}

sub _serialize {
  my ($self, $data) = @_;
  my $mp = Data::MessagePack->new->utf8;
  return encode_base64url($mp->pack($data));
}

sub _get_fields {
  my $self = shift;
  my $rec = shift;
  my $metadataPrefix = shift;

  switch ($metadataPrefix) {
    case 'oai_dc' {
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
    case 'oai_openaire' {
      return $rec->{openaire};
    }
  }
}

sub handler {
  my $self = shift;

  my $ns = "oai:".$self->config->{oai}->{oairepositoryidentifier}.":";
  my $uri_base = 'https://' . $self->config->{baseurl} . '/' . $self->config->{basepath} . '/oai';
  my $response_date = DateTime->now->iso8601 . 'Z';
  my $params = $self->req->params->to_hash;
  my $errors = [];
  my $set;
  my $sets;
  my $skip = 0;
  my $pagesize = $self->config->{oai}->{pagesize};
  my $verb = $params->{'verb'};
  $self->stash(
    uri_base              => $uri_base,
    request_uri           => $uri_base,
    response_date         => $response_date,
    errors                => $errors,
    params                => $params,
    repository_identitier => $self->config->{oai}->{oairepositoryidentifier},
    repository_name       => $self->config->{oai}->{repositoryname},
    ns                    => $ns,
    adminemail            => $self->config->{adminemail}
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

  my $token;
  if (exists $params->{resumptionToken}) {
    if ($verb eq 'ListSets') {
      push @$errors, [badResumptionToken => "resumptionToken isn't necessary"];
    } else {
      eval {
        $token = $self->_deserialize($params->{resumptionToken});
        $params->{set}            = $token->{_s} if defined $token->{_s};
        $params->{from}           = $token->{_f} if defined $token->{_f};
        $params->{until}          = $token->{_u} if defined $token->{_u};
        $skip                     = $token->{_n} if defined $token->{_n};
        $self->stash(token => $token);
      };
      if($@){
        push @$errors, [badResumptionToken => "resumptionToken is not in the correct format"];
      };
    }
  }

  if (exists $params->{set} || ($verb eq 'ListSets')) {
    my $mongosets = $self->mongo->get_collection('oai_sets')->find();
    while (my $s = $mongosets->next) {
      $sets->{$s->{setSpec}} = $s;
    }
    unless ($sets) {
      push @$errors, [noSetHierarchy => "sets are not supported"];
    }
    if (exists $params->{set}) {
      unless ($set = $sets->{$params->{set}}) {
        push @$errors, [badArgument => "set does not exist"];
      }
    }
  }

  if (exists $params->{metadataPrefix}) {
    if ($params->{metadataPrefix} eq 'oai_dc' || ($params->{metadataPrefix} eq 'oai_openaire')) {
      $self->stash(metadataPrefix => $params->{metadataPrefix});
    } else {
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
      $self->stash(r => $rec, fields => $self->_get_fields($rec, $params->{metadataPrefix}));
      $self->render(template => 'oai/get_record', format => 'xml', handler => 'ep');
      return;
    }
    push @$errors, [idDoesNotExist => "identifier ".$params->{identifier}." is unknown or illegal"];
    $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
    return;

  } elsif ($verb eq 'Identify') {
    my $earliestDatestamp = '1970-01-01T00:00:01Z';
    my $rec = $self->mongo->get_collection('oai_records')->find()->sort({ "updated" => 1 })->next;
    if ($rec) {
      $earliestDatestamp = $rec->{created};
    }
    $self->stash(earliest_datestamp => $earliestDatestamp);
    $self->render(template => 'oai/identify', format => 'xml', handler => 'ep');
    return;

  } elsif ($verb eq 'ListIdentifiers' || $verb eq 'ListRecords') {
    my $from  = $params->{from};
    my $until = $params->{until};

    for my $datestamp (($from, $until)) {
      $datestamp || next;
      if ($datestamp !~ /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}Z)?$/) {
        push @$errors, [badArgument => "datestamps must have the format YYYY-MM-DD or YYYY-MM-DDThh:mm:ssZ"];
        $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
        return;
      }
    }

    if ($from && $until && length($from) != length($until)) {
      push @$errors, [badArgument => "datestamps must have the same granularity"];
      $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
      return;
    }

    if ($from && $until && $from gt $until) {
      push @$errors, [badArgument => "from is more recent than until"];
      $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
      return;
    }

    if ($from && length($from) == 10) {
      $from = "${from}T00:00:00Z";
    }
    if ($until && length($until) == 10) {
      $until = "${until}T23:59:59Z";
    }

    my %filter;

    if ($from) {
      $filter{"updated"} = { '$gte' => DateTime::Format::ISO8601->parse_datetime($from) };
    }

    if ($until) {
      $filter{"updated"} = { '$lte' => DateTime::Format::ISO8601->parse_datetime($until) };
    }

    if ($params->{set}) {
      $filter{"setSpec"} = $params->{set};
    }

    my $total = $self->mongo->get_collection('oai_records')->count(\%filter);
    if ($total eq 0) {
      push @$errors, [noRecordsMatch => "no records found"];
      $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
      return;
    }
    $self->stash(total => $total);

    my $cursor = $self->mongo->get_collection('oai_records')->find(\%filter)->sort({ "updated" => 1 })->limit($pagesize)->skip($skip);
    my @records = ();
    while (my $rec = $cursor->next) {
      if ($verb eq 'ListIdentifiers') {
        push @records, {r => $rec};
      } else {
        push @records, {r => $rec, fields => $self->_get_fields($rec, $params->{metadataPrefix})};
      }
    }
    $self->stash(records => \@records);

    if (($total > $pagesize) && (($skip + $pagesize) < $total)) {
      my $t;
      $t->{_n} = $skip + $pagesize;
      $t->{_s} = $set->{setSpec} if defined $set;
      $t->{_f} = $from if defined $from;
      $t->{_u} = $until if defined $until;
      $self->stash(resumption_token => $self->_serialize($t));
    } else {
      $self->stash(resumption_token => undef);
    }

    $self->app->log->debug("oai list response: verb[$verb] skip[$skip] pagesize[$pagesize] total[$total] from[$from] until[$until] set[".$set->{setSpec}."] restoken[".$self->stash('resumption_token')."]");

    if ($verb eq 'ListIdentifiers') {
      $self->render(template => 'oai/list_identifiers', format => 'xml', handler => 'ep');
    } else {
      $self->render(template => 'oai/list_records', format => 'xml', handler => 'ep');
    }

  } elsif ($verb eq 'ListMetadataFormats') {

    if (my $id = $params->{identifier}) {
      $id =~ s/^$ns//;
      my $rec = $self->mongo->get_collection('oai_records')->find_one({"pid" => $id});
      unless (defined $rec) {
        push @$errors, [idDoesNotExist => "identifier ".$params->{identifier}." is unknown or illegal"];
        $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
        return;
      }
    }
    $self->render(template => 'oai/list_metadata_formats', format => 'xml', handler => 'ep');
    return;

  } elsif ($verb eq 'ListSets') {
    for my $setSpec (keys %{$sets}) {
      $sets->{$setSpec}->{fields} = $self->_get_fields($sets->{$setSpec}->{setDescription}, 'oai_dc')
    }
    $self->stash(sets => $sets);
    $self->render(template => 'oai/list_sets', format => 'xml', handler => 'ep');
    return;
  }
}

1;