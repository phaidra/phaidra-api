package PhaidraAPI::Controller::Stats;

use strict;
use warnings;
use v5.10;
use PhaidraAPI::Controller::Stats;
use base 'Mojolicious::Controller';

sub stats {
    my $self = shift; 
       
    my $pid = $self->stash('pid');

    unless(defined($pid)){
        $self->render(json => { alerts => [{ type => 'info', msg => 'Undefined pid' }]}, status => 400);
        return;
    }

    my $key = $self->stash('stats_param_key');

    my $cachekey = 'stats_'.$pid;
    my $cacheval = $self->app->chi->get($cachekey);

    unless($cacheval){

        $self->app->log->debug("[cache miss] $cachekey");

        my $fr = undef;
        my $siteid = undef;
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
        unless(defined($fr->{stats}->{siteid})){
            $self->render(json => { alerts => [{ type => 'info', msg => 'Piwik siteid is not configured' }]}, status => 500);
            return;
        }
        $siteid = $fr->{stats}->{siteid};

        # get         
        my $downloads = $self->app->db_stats_phaidra_catalyst->selectrow_array("select count(*) from piwik_log_link_visit_action as a where a.idsite=$siteid and a.custom_var_v2 = \"$pid\" and a.custom_var_k2 = \"Download\"") or $self->app->log->error("Error querying piwik database for downloads:".$self->app->db_stats_phaidra_catalyst->errstr);
        my $detail_page = $self->app->db_stats_phaidra_catalyst->selectrow_array("select count(*) from piwik_log_link_visit_action as a where a.idsite=$siteid and a.custom_var_v4 = \"$pid\" and a.custom_var_k4 = \"Detail page\"") or $self->app->log->error("Error querying piwik database for detail views:".$self->app->db_stats_phaidra_catalyst->errstr);
        $cacheval = { downloads => $downloads, detail_page => $detail_page };        

        $self->app->chi->set($cachekey, $cacheval, '1 day');
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
