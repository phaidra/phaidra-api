package PhaidraAPI::Controller::Oai;

# based on https://github.com/LibreCat/Dancer-Plugin-Catmandu-OAI

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';
use Switch;
use Data::MessagePack;
use MIME::Base64 qw(encode_base64url decode_base64url);
use DateTime;
use DateTime::Format::ISO8601;
use DateTime::Format::Strptime;
use BSON::Types qw(:all);
use Clone qw(clone);
use Mojo::JSON qw(encode_json decode_json);
use Mojo::ByteStream qw(b);
use PhaidraAPI::Model::Oai::Openaire;

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
  ListMetadataFormats => {valid => {identifier => 1, resumptionToken => 1}, required => []},
  ListRecords         => {
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

sub _get_metadata_dc {
  my ($self, $rec, $set) = @_;
  my @el          = qw(contributor, coverage, creator, date, description, format, identifier, language, publisher, relation, rights, source, subject, title, type);
  my %valuesCheck = map {$_ => {}} @el;
  my @metadata;
  if (exists($rec->{bib_publisher})) {
    for my $v (@{$rec->{bib_publisher}}) {
      $valuesCheck{'publisher'}{$v} = 1;
    }
    my %field;
    $field{name}   = 'publisher';
    $field{values} = $rec->{bib_publisher};
    push @metadata, \%field;
  }
  if (exists($rec->{bib_published})) {
    for my $v (@{$rec->{bib_published}}) {
      $valuesCheck{'date'}{$v} = 1;
    }
    my %field;
    $field{name}   = 'date';
    $field{values} = $rec->{bib_published};
    push @metadata, \%field;
  }
  if (exists($rec->{dcterms_datesubmitted})) {
    for my $v (@{$rec->{dcterms_datesubmitted}}) {
      $valuesCheck{'date'}{$v} = 1;
    }
    my %field;
    $field{name}   = 'date';
    $field{values} = $rec->{dcterms_datesubmitted};
    push @metadata, \%field;
  }
  if (exists($rec->{ispartof})) {
    my @ispartofs;
    for my $v (@{$rec->{ispartof}}) {
      push @ispartofs, 'isPartOf:https://' . $self->config->{phaidra}->{baseurl} . '/' . $v;
    }
    my %field;
    $field{name}   = 'relation';
    $field{values} = \@ispartofs;
    push @metadata, \%field;
  }
  unless (exists($rec->{dc_type_eng})) {
    $rec->{dc_type_eng} = ['other']
  }
  for my $k (keys %{$rec}) {
    if ($k =~ m/^dc_([a-z]+)_?([a-z]+)?$/) {
      my $skip = 0;
      for my $v (@{$rec->{$k}}) {
        if ($valuesCheck{$1}{$v}) {
          $skip = 1;
          last;
        }
      }
      $skip = 1 if ($1 eq 'license'); #dc_license is not a dc field, it's in rights
      next if $skip;
      for my $v (@{$rec->{$k}}) {
        $valuesCheck{$1}{$v} = 1;
      }
      my %field;
      $field{name} = $1;
      if ($set eq 'phaidra4primo') {
        if ($1 eq 'type') {
          $field{values} = [$self->_map_dc_type($rec, $k)];
        }
      }
      if ($1 eq 'description') {
        if (exists($rec->{ispartof})) {
          for my $coll (@{$rec->{ispartof}}) {
            if ($coll eq $self->app->config->{ir}->{ircollection}) {
              $field{values} = ["The abstract is available here: https://" . $self->app->config->{ir}->{baseurl} . "/" . $rec->{pid}];
            }
          }
        }
      }
      unless (exists($field{values})) {
	$field{values} = [];
	my $localdupcheck;
	for my $v (@{$rec->{$k}}) {
	  unless ($localdupcheck->{$v}) {
            push @{$field{values}}, $v;
          }
          $localdupcheck->{$v} = 1;
	}
      }
      $field{lang}   = $2 if $2;
      push @metadata, \%field;
    }
  }
  return \@metadata;
}

sub _map_dc_type {
  my $self           = shift;
  my $rec            = shift;
  my $key            = shift;

  my $type = $rec->{$key}[0];

  switch ($rec->{cmodel}) {
    case 'Asset' {
      switch ($rec->{owner}) {
        case 'dlbtrepo2' {
          $type = 'text_resource';
        }
        case 'phaidra1' {
          $type = 'research_dataset'
        }
        case 'sachslf6' {
          $type = 'movingimage'
        }
        case 'reposii5' {
          $type = 'text_resource'
        }
        case 'otolithf' {
          $type = 'research_dataset'
        }
        else {
          $type = 'other'
        }
      }
    }
    case 'Audio' {
      $type = 'audio';
    }
    case 'Book' {
      switch ($rec->{owner}) {
        case 'ondemae7' { # shouldn't occur
          $type = 'book'
        }
        case 'archiv3' {
          $type = 'book';
        }
        case 'hoenigsc' {
          $type = 'image'
        }
        else {
          $type = 'text_resource'
        }
      }
    }
    case 'Collection' {
      $type = 'collection';
    }
    case 'Container' {
      switch ($rec->{owner}) {
        case 'wandtafelu36' {
          $type = 'image'
        }
        else {
          $type = 'container'
        }
      }
    }
    case 'Paper' {
      $type = 'text_resource';
    }
    case 'PDFDocument' {
      switch ($rec->{dc_type_eng}[0]) {
        case 'article' {
          $type = 'article'
        }
        case 'article in collected edition' {
          $type = 'article';
        }
        case 'baccalaureate Dissertation' {
          $type = 'dissertation';
        }
        case 'book' {
          $type = 'book';
        }
        case 'book Part' {
          $type = 'book_chapter';
        }
        case 'conference Object' {
          $type = 'conference_object';
        }
        case 'diploma Dissertation' {
          $type = 'dissertation';
        }
        case 'dissertation' {
          $type = 'dissertation';
        }
        case 'lecture' {
          $type = 'lecture';
        }
        case 'lecture series (one person)' {
          $type = 'lecture';
        }
        case 'master\'s (Austria) Dissertation' {
          $type = 'dissertation';
        }
        case 'master\'s Dissertation' {
          $type = 'dissertation';
        }
        case 'preprint' {
          $type = 'text_resource';
        }
        case 'professorial Dissertation' {
          $type = 'dissertation';
        }
        case 'report' {
          $type = 'report';
        }
        case 'research Data' {
          $type = 'text_resource';
        }
        case 'review' {
          $type = 'review';
        }
        case 'text' {
          $type = 'text_resource';
        }
        case 'theses' {
          $type = 'dissertation';
        }
        case 'working Paper' {
          $type = 'text_resource';
        }
        case 'other' {
          $type = 'text_resource';
        }
        else {
          $type = 'text_resource'
        }
      }
    }
    case 'Picture' {
      switch ($rec->{resourcetype}) {
        case 'image' {
          $type = 'image'
        }
        case 'map' {
          $type = 'map';
        }
      }
    }
    case 'Resource' {
      $type = 'web_resource';
    }
    case 'Video' {
      $type = 'movingimage';
    }
  }

  $self->app->log->debug("XXXXXXXXXXXXXXXXXXXXXXx oai type2: ".$type);

  return $type;
}

sub _get_metadata {
  my $self           = shift;
  my $rec            = shift;
  my $metadataPrefix = shift;
  my $set            = shift;

  switch ($metadataPrefix) {
    case 'oai_dc' {
      return $self->_get_metadata_dc($rec, $set);
    }
    case 'oai_openaire' {
      my $oaire_model = PhaidraAPI::Model::Oai::Openaire->new;
      return $oaire_model->get_metadata_openaire($self, $rec);
    }
  }
}

sub handler {
  my $self = shift;

  my $ns            = "oai:" . $self->config->{oai}->{oairepositoryidentifier} . ":";
  my $uri_base      = 'https://' . $self->config->{baseurl} . '/' . $self->config->{basepath} . '/oai';
  my $response_date = DateTime->now->iso8601 . 'Z';
  my $params        = $self->req->params->to_hash;
  my $errors        = [];
  my $set;
  my $sets;
  my $skip     = 0;
  my $pagesize = $self->config->{oai}->{pagesize};
  my $verb     = $params->{'verb'};
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

    if ($valid->{resumptionToken} and exists $params->{resumptionToken}) {
      if (keys(%$params) > 2) {
        push @$errors, [badArgument => "resumptionToken cannot be combined with other parameters"];
      }
    }
    else {
      for my $key (keys %$params) {
        next if $key eq 'verb';
        unless ($valid->{$key}) {
          unless (($key eq 'set') && ($params->{$key} eq 'phaidra4primo')) {
            push @$errors, [badArgument => "parameter $key is illegal"];
          }
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
    }
    else {
      eval {
        $token                    = $self->_deserialize($params->{resumptionToken});
        $params->{set}            = $token->{_s} if defined $token->{_s};
        $params->{from}           = $token->{_f} if defined $token->{_f};
        $params->{until}          = $token->{_u} if defined $token->{_u};
        $params->{metadataPrefix} = $token->{_m} if defined $token->{_m};
        $skip                     = $token->{_n} if defined $token->{_n};
        $self->stash(token => $token);
      };
      if ($@) {
        push @$errors, [badResumptionToken => "resumptionToken is not in the correct format"];
      }
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
    }
    else {
      push @$errors, [cannotDisseminateFormat => "metadataPrefix $params->{metadataPrefix} is not supported"];
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
      $self->stash(r => $rec, metadata => $self->_get_metadata($rec, $params->{metadataPrefix}, $params->{set}));
      $self->render(template => 'oai/get_record', format => 'xml', handler => 'ep');
      return;
    }
    push @$errors, [idDoesNotExist => "identifier " . $params->{identifier} . " is unknown or illegal"];
    $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
    return;

  }
  elsif ($verb eq 'Identify') {
    my $earliestDatestamp = bson_time(0);                                                                        # 1970-01-01T00:00:01Z
    my $rec               = $self->mongo->get_collection('oai_records')->find()->sort({"updated" => 1})->next;
    if ($rec) {
      $earliestDatestamp = $rec->{created};
    }
    $self->stash(earliest_datestamp => $earliestDatestamp);
    $self->render(template => 'oai/identify', format => 'xml', handler => 'ep');
    return;

  }
  elsif ($verb eq 'ListIdentifiers' || $verb eq 'ListRecords') {
    my $from           = $params->{from};
    my $until          = $params->{until};
    my $metadataPrefix = $params->{metadataPrefix};

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
      $filter{"updated"} = {'$gte' => DateTime::Format::ISO8601->parse_datetime($from)};
    }

    if ($until) {
      $filter{"updated"} = {'$lte' => DateTime::Format::ISO8601->parse_datetime($until)};
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

    my $cursor  = $self->mongo->get_collection('oai_records')->find(\%filter)->sort({"updated" => -1})->limit($pagesize)->skip($skip);
    my @records = ();
    while (my $rec = $cursor->next) {
      if ($verb eq 'ListIdentifiers') {
        push @records, {r => $rec};
      }
      else {
        push @records, {r => $rec, metadata => $self->_get_metadata($rec, $metadataPrefix, $params->{set})};
      }
    }
    $self->stash(records => \@records);

    if (($total > $pagesize) && (($skip + $pagesize) < $total)) {
      my $t;
      $t->{_n} = $skip + $pagesize;
      $t->{_s} = $set->{setSpec} if defined $set;
      $t->{_f} = $from           if defined $from;
      $t->{_u} = $until          if defined $until;
      $t->{_m} = $metadataPrefix if defined $metadataPrefix;
      $self->stash(resumption_token => $self->_serialize($t));
    }
    else {
      $self->stash(resumption_token => undef);
    }

    $self->app->log->debug("oai list response: verb[$verb] skip[$skip] pagesize[$pagesize] total[$total] from[$from] until[$until] set[" . $set->{setSpec} . "] restoken[" . $self->stash('resumption_token') . "]");

    if ($verb eq 'ListIdentifiers') {
      $self->render(template => 'oai/list_identifiers', format => 'xml', handler => 'ep');
    }
    else {
      $self->render(template => 'oai/list_records', format => 'xml', handler => 'ep');
    }

  }
  elsif ($verb eq 'ListMetadataFormats') {

    if (my $id = $params->{identifier}) {
      $id =~ s/^$ns//;
      my $rec = $self->mongo->get_collection('oai_records')->find_one({"pid" => $id});
      unless (defined $rec) {
        push @$errors, [idDoesNotExist => "identifier " . $params->{identifier} . " is unknown or illegal"];
        $self->render(template => 'oai/error', format => 'xml', handler => 'ep');
        return;
      }
    }
    $self->render(template => 'oai/list_metadata_formats', format => 'xml', handler => 'ep');
    return;

  }
  elsif ($verb eq 'ListSets') {
    for my $setSpec (keys %{$sets}) {
      $sets->{$setSpec}->{metadata} = $self->_get_metadata($sets->{$setSpec}->{setDescription}, 'oai_dc');
    }
    $self->stash(sets => $sets);
    $self->render(template => 'oai/list_sets', format => 'xml', handler => 'ep');
    return;
  }
}

1;
