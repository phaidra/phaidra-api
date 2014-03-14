package PhaidraAPI::Model::Session::Transport::Header;

use strict;
use warnings;
use Data::Dumper;

use base 'MojoX::Session::Transport';

__PACKAGE__->attr('name');
__PACKAGE__->attr('log');

sub get {
    my ($self) = @_;
    return $self->tx->req->headers->header($self->name);	
}

# we don't set anything, the token is sent via cookie only on login and then kept on client side
sub set {
    my ($self, $sid, $expires) = @_;
}

1;
__END__
