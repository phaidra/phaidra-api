package PhaidraAPI::Model::Stats;

use strict;
use warnings;
use v5.10;
use XML::LibXML;
use base qw/Mojo::Base/;

sub stats {
  my $self   = shift;
  my $c      = shift;
  my $pid    = shift;
  my $siteid = shift;
  my $output = shift;

  my $fr = undef;
  if (exists($c->app->config->{frontends})) {
    for my $f (@{$c->app->config->{frontends}}) {
      if (defined($f->{frontend_id}) && $f->{frontend_id} eq 'phaidra_catalyst') {
        $fr = $f;
      }
    }
  }

  unless (defined($fr)) {

    # return 200, this is just ok
    return {alerts => [{type => 'info', msg => 'Frontend is not configured'}], status => 200};
  }
  unless ($fr->{frontend_id} eq 'phaidra_catalyst') {

    # return 200, this is just ok
    return {alerts => [{type => 'info', msg => 'Frontend [' . $fr->{frontend_id} . '] is not supported'}], status => 200};
  }
  unless (defined($fr->{stats})) {

    # return 200, this is just ok
    return {alerts => [{type => 'info', msg => 'Statistics source is not configured'}], status => 200};
  }

  # only piwik now
  unless ($fr->{stats}->{type} eq 'piwik') {

    # return 200, this is just ok
    return {alerts => [{type => 'info', msg => 'Statistics source [' . $fr->{stats}->{type} . '] is not supported.'}], status => 200};
  }
  unless ($siteid) {
    unless (defined($fr->{stats}->{siteid})) {
      return {alerts => [{type => 'info', msg => 'Piwik siteid is not configured'}], status => 500};
    }
    $siteid = $fr->{stats}->{siteid};
  }

  my $pidnum = $pid;
  $pidnum =~ s/://g;

  if ($output eq 'chart') {

    my $downloads;
    my $sth
      = $c->app->db_stats_phaidra_catalyst->prepare(
      "SELECT DATE_FORMAT(server_time,'%Y-%m-%d'), location_country FROM piwik_log_link_visit_action INNER JOIN piwik_log_action on piwik_log_action.idaction = piwik_log_link_visit_action.idaction_url INNER JOIN piwik_log_visit on piwik_log_visit.idvisit = piwik_log_link_visit_action.idvisit WHERE piwik_log_link_visit_action.idsite = $siteid AND (piwik_log_action.name like '%download/$pid%')"
      ) or $c->app->log->error("Error querying piwik database for download stats chart:" . $c->app->db_stats_phaidra_catalyst->errstr);
    $sth->execute() or $c->app->log->error("Error querying piwik database for download stats chart:" . $c->app->db_stats_phaidra_catalyst->errstr);
    my $date;
    my $country;
    $sth->bind_columns(undef, \$date, \$country);
    while ($sth->fetch) {
      if ($downloads->{$country}) {
        $downloads->{$country}->{$date}++;
      }
      else {
        $downloads->{$country} = {$date => 1};
      }
    }

    my $detail_page;
    $sth
      = $c->app->db_stats_phaidra_catalyst->prepare(
      "SELECT DATE_FORMAT(server_time,'%Y-%m-%d'), location_country FROM piwik_log_link_visit_action INNER JOIN piwik_log_action on piwik_log_action.idaction = piwik_log_link_visit_action.idaction_url INNER JOIN piwik_log_visit on piwik_log_visit.idvisit = piwik_log_link_visit_action.idvisit WHERE piwik_log_link_visit_action.idsite = $siteid AND (piwik_log_action.name like '%detail/$pid%')"
      ) or $c->app->log->error("Error querying piwik database for detail stats chart:" . $c->app->db_stats_phaidra_catalyst->errstr);
    $sth->execute() or $c->app->log->error("Error querying piwik database for detail stats chart:" . $c->app->db_stats_phaidra_catalyst->errstr);
    $sth->bind_columns(undef, \$date, \$country);
    while ($sth->fetch) {
      if ($detail_page->{$country}) {
        $detail_page->{$country}->{$date}++;
      }
      else {
        $detail_page->{$country} = {$date => 1};
      }
    }

    if (defined($detail_page) || defined($downloads)) {
      return {downloads => $downloads, detail_page => $detail_page, alerts => [], status => 200};
    }
    else {
      my $msg = "No data has been fetched. DB msg:" . $c->app->db_stats_phaidra_catalyst->errstr;
      $c->app->log->warn($msg);
      return {alerts => [{type => 'info', msg => $msg}], status => 200};
    }
  }
  else {

    my $sth = $c->app->db_stats_phaidra_catalyst->prepare(
      "CREATE TEMPORARY TABLE pid_visits_idsite_downloads_$pidnum AS (SELECT piwik_log_link_visit_action.idsite FROM piwik_log_link_visit_action INNER JOIN piwik_log_action on piwik_log_action.idaction = piwik_log_link_visit_action.idaction_url WHERE piwik_log_action.name like '%download/$pid%');");
    $sth->execute();
    my $downloads = $c->app->db_stats_phaidra_catalyst->selectrow_array("SELECT count(*) FROM pid_visits_idsite_downloads_$pidnum WHERE idsite = $siteid;");
    $sth = $c->app->db_stats_phaidra_catalyst->prepare("DROP TEMPORARY TABLE IF EXISTS pid_visits_idsite_downloads_$pidnum;");
    $sth->execute();

    unless (defined($downloads)) {
      $c->app->log->error("Error querying piwik database for download stats:" . $c->app->db_stats_phaidra_catalyst->errstr);
    }

    # this counts *any* page with pid in URL. But that kind of makes sense anyways...
    $sth = $c->app->db_stats_phaidra_catalyst->prepare(
      "CREATE TEMPORARY TABLE pid_visits_idsite_detail_$pidnum AS (SELECT piwik_log_link_visit_action.idsite FROM piwik_log_link_visit_action INNER JOIN piwik_log_action on piwik_log_action.idaction = piwik_log_link_visit_action.idaction_url WHERE piwik_log_action.name like '%detail/$pid%');");
    $sth->execute();
    my $detail_page = $c->app->db_stats_phaidra_catalyst->selectrow_array("SELECT count(*) FROM pid_visits_idsite_detail_$pidnum WHERE idsite = $siteid;");
    $sth = $c->app->db_stats_phaidra_catalyst->prepare("DROP TEMPORARY TABLE IF EXISTS pid_visits_idsite_detail_$pidnum;");
    $sth->execute();

    unless (defined($detail_page)) {
      $c->app->log->error("Error querying piwik database for detail stats:" . $c->app->db_stats_phaidra_catalyst->errstr);
    }

    if (defined($detail_page)) {
      return {downloads => $downloads, detail_page => $detail_page, alerts => [], status => 200};
    }
    else {
      my $msg = "No data has been fetched. DB msg:" . $c->app->db_stats_phaidra_catalyst->errstr;
      $c->app->log->warn($msg);
      return {alerts => [{type => 'info', msg => $msg}], status => 200};
    }
  }
}

1;
__END__
