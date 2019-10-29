package PhaidraAPI::Controller::Stats;

use strict;
use warnings;
use v5.10;
use PhaidraAPI::Controller::Stats;
use base 'Mojolicious::Controller';

sub stats {
    my $self = shift; 
       
    my $pid = $self->stash('pid');
    my $siteid = $self->param('siteid');

    unless(defined($pid)){
        $self->render(json => { alerts => [{ type => 'info', msg => 'Undefined pid' }]}, status => 400);
        return;
    }

    my $key = $self->stash('stats_param_key');

    my $fr = undef;
    if(exists($self->app->config->{frontends})){
        for my $f (@{$self->app->config->{frontends}}){
            if(defined($f->{frontend_id}) && $f->{frontend_id} eq 'phaidra_catalyst'){
                $fr = $f;
            }
        }
    }

    unless(defined($fr)){
        # return 200, this is just ok
        $self->render(json => { alerts => [{ type => 'info', msg => 'Frontend is not configured' }]}, status => 200);
        return;
    }
    unless($fr->{frontend_id} eq 'phaidra_catalyst'){
        # return 200, this is just ok
        $self->render(json => { alerts => [{ type => 'info', msg => 'Frontend ['.$fr->{frontend_id}.'] is not supported' }]}, status => 200);
        return;
    }
    unless(defined($fr->{stats})){
        # return 200, this is just ok
        $self->render(json => { alerts => [{ type => 'info', msg => 'Statistics source is not configured' }]}, status => 200);
        return;
    }        
    # only piwik now
    unless($fr->{stats}->{type} eq 'piwik'){
        # return 200, this is just ok            
        $self->render(json => { alerts => [{ type => 'info', msg => 'Statistics source ['.$fr->{stats}->{type}.'] is not supported.' }]}, status => 200);
        return;
    }
    unless($siteid){
        unless(defined($fr->{stats}->{siteid})){
            $self->render(json => { alerts => [{ type => 'info', msg => 'Piwik siteid is not configured' }]}, status => 500);
            return;
        }
        $siteid = $fr->{stats}->{siteid};
    }

    my $cachekey = 'stats_'.$siteid.'_'.$pid;
    my $cacheval = $self->app->chi->get($cachekey);

    unless($cacheval){

        $self->app->log->debug("[cache miss] $cachekey");

        my $pidnum = $pid;
        $pidnum =~ s/://g;

        # can't do downloads, piwik's custom vars do not work reliably
        my $downloads = 0; #$self->app->db_stats_phaidra_catalyst->selectrow_array("select count(*) from piwik_log_link_visit_action as a where a.idsite=$siteid and a.custom_var_v2 = \"$pid\" and a.custom_var_k2 = \"Download\"") or $self->app->log->error("Error querying piwik database for downloads:".$self->app->db_stats_phaidra_catalyst->errstr);

        # this counts *any* page with pid in URL. But that kind of makes sense anyways...
        my $sth = $self->app->db_stats_phaidra_catalyst->prepare("CREATE TEMPORARY TABLE pid_visits_idsite_$pidnum AS (SELECT piwik_log_link_visit_action.idsite FROM piwik_log_link_visit_action INNER JOIN piwik_log_action on piwik_log_action.idaction = piwik_log_link_visit_action.idaction_url WHERE piwik_log_action.name like '%view/$pid%' OR piwik_log_action.name like '%detail_object/$pid%' OR piwik_log_action.name like '%detail/$pid%');");
        $sth->execute();
#        $sth->fetchall_arrayref();
        my $detail_page = $self->app->db_stats_phaidra_catalyst->selectrow_array("SELECT count(*) FROM pid_visits_idsite_$pidnum WHERE idsite = $siteid;");
        
        if(defined($detail_page)){
            $cacheval = { downloads => $downloads, detail_page => $detail_page };        
            $self->app->chi->set($cachekey, $cacheval, '1 day');
        }else{
            $self->app->log->error("Error querying piwik database for detail views:".$self->app->db_stats_phaidra_catalyst->errstr);
        }
    }else{
        $self->app->log->debug("[cache hit] $cachekey");
    }

    if(defined($key)){
        $self->render(text => $cacheval->{$key}, status => 200);
    }else{
        $self->render(json => { stats => $cacheval }, status => 200);
    }
}

sub chart {
    my $self = shift; 
       
    my $pid = $self->stash('pid');
    my $siteid = $self->param('siteid');

    unless(defined($pid)){
        $self->render(json => { alerts => [{ type => 'info', msg => 'Undefined pid' }]}, status => 400);
        return;
    }

    my $key = $self->stash('stats_param_key');

    my $fr = undef;
    if(exists($self->app->config->{frontends})){
        for my $f (@{$self->app->config->{frontends}}){
            if(defined($f->{frontend_id}) && $f->{frontend_id} eq 'phaidra_catalyst'){
                $fr = $f;                    
            }
        }
    }

    unless(defined($fr)){
        # return 200, this is just ok
        $self->render(json => { alerts => [{ type => 'info', msg => 'Frontend is not configured' }]}, status => 200);
        return;
    }
    unless($fr->{frontend_id} eq 'phaidra_catalyst'){
        # return 200, this is just ok
        $self->render(json => { alerts => [{ type => 'info', msg => 'Frontend ['.$fr->{frontend_id}.'] is not supported' }]}, status => 200);
        return;
    }
    unless(defined($fr->{stats})){
        # return 200, this is just ok
        $self->render(json => { alerts => [{ type => 'info', msg => 'Statistics source is not configured' }]}, status => 200);
        return;
    }        
    # only piwik now
    unless($fr->{stats}->{type} eq 'piwik'){
        # return 200, this is just ok            
        $self->render(json => { alerts => [{ type => 'info', msg => 'Statistics source ['.$fr->{stats}->{type}.'] is not supported.' }]}, status => 200);
        return;
    }
    unless($siteid){
        unless(defined($fr->{stats}->{siteid})){
            $self->render(json => { alerts => [{ type => 'info', msg => 'Piwik siteid is not configured' }]}, status => 500);
            return;
        }
        $siteid = $fr->{stats}->{siteid};
    }

    my $cachekey = 'statschart_'.$siteid.'_'.$pid;
    my $cacheval = $self->app->chi->get($cachekey);

    unless($cacheval){

        $self->app->log->debug("[cache miss] $cachekey");

        my $pidnum = $pid;
        $pidnum =~ s/://g;

        my $downloads;
        my $docs = $self->paf_mongo->db->collection('downloads')->find({pid => $pid})->all;
        for my $d (@{$docs}){
            $downloads->{$d->{day}} = $d->{count};
        }

        # this counts pages with view/pid or detail_page/pid in URL
        my $detail_page;
        my $sth = $self->app->db_stats_phaidra_catalyst->prepare("SELECT DATE_FORMAT(server_time,'%Y-%m-%d') FROM piwik_log_link_visit_action INNER JOIN piwik_log_action on piwik_log_action.idaction = piwik_log_link_visit_action.idaction_url WHERE idsite = $siteid AND (piwik_log_action.name like '%view/$pid%' OR piwik_log_action.name like '%detail_object/$pid%' OR piwik_log_action.name like '%detail/$pid%')");
        $sth->execute();
        my $date;
        $sth->bind_columns(undef, \$date);
        while($sth->fetch) {
            $detail_page->{$date}++;
        }
    
        if(defined($detail_page) || defined($downloads)){
            $cacheval = { downloads => $downloads, detail_page => $detail_page };        
            $self->app->chi->set($cachekey, $cacheval, '1 day');
        }
    }else{
        $self->app->log->debug("[cache hit] $cachekey");
    }

    if(defined($key)){
        $self->render(text => $cacheval->{$key}, status => 200);
    }else{
        $self->render(json => { stats => $cacheval }, status => 200);
    }
    
}

1;
