package PhaidraAPI::Controller::Objects;

use strict;
use warnings;
use v5.10;
use base 'Mojolicious::Controller';

sub getobject {
    my $self = shift;

    my $notes = PhaidraAPI::Model::Object->select( {
        user_id => $self->session('user_id')
    } )->hashes;

    $self->render_json($notes);
}

sub create {
    my $self = shift;

    my $note_id = PhaidraAPI::Model::Object->insert({
        %{$self->req->json},
        user_id => $self->session('user_id'),
        date    => time()
    });

    $self->render_json(
        scalar PhaidraAPI::Model::Object->select( { note_id => $note_id } )->hash,
        status=>201
    );
}

sub update {
    my $self = shift;
    my %where = (
        user_id => $self->session('user_id'),
        note_id => $self->param('id')
    );

    PhaidraAPI::Model::Object->update( $self->req->json , \%where);

    $self->render_json(PhaidraAPI::Model::Object->select(\%where)->hash);
}

sub delete {
    my $self = shift;

    PhaidraAPI::Model::Object->delete( {
        user_id => $self->session('user_id'),
        note_id => $self->param('id')
    } );

    $self->render_json(1);
}

1;
