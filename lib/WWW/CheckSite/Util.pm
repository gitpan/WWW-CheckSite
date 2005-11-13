package WWW::CheckSite::Util;
use strict;

# $Id: Util.pm 428 2005-11-10 09:13:25Z abeltje $
use vars qw( $VERSION @EXPORT );
$VERSION = '0.002';

=head1 NAME

WWW::CheckSite::Util - provide utilities for WWW::CheckSite

=head1 SYNOPSIS

    use WWW::CheckSite::Util;

    my $cache = new_cashe;

    my $data;
    if ( $data = $cache->has( $key ) ) { # $data is a *copy*
        # change $data
        $cache->set( $key => $data );
    } else {
        # set $data
        $cache->set( $key => $data );
    }

    my $stack = new_stack( @sfields );


=cut

use base 'Exporter';
@EXPORT = qw( &new_cache &new_stack );

=head2 new_cache

Return a new C<WWW::CheckSite::Util::Cache> object.

=cut

sub new_cache {
    return WWW::CheckSite::Util::Cache->new;
}

=head2 new_stack

Return a new C<WWW::CheckSite::Util::Stack> object.

=cut

sub new_stack {
    return WWW::CheckSite::Util::Stack->new;
}

package WWW::CheckSite::Util::Cache;

=head1 WWW::CheckSite::Util::Cache

Implements a simple cache as a hash. Storage and reteival on the keyvalue.

=cut

sub new {
    my $class = shift;
    return bless { }, $class;
}

=head2 set( $key => $data )

Add (or update) the cache for this key. Returns C<$data>.

=cut

sub set {
    my( $self, $key, $data ) = @_;
    $self->{ $key } = $data;
}

=head2 unset( $key )

Remove the item for this key from the cache.

=cut

sub unset {
    my( $self, $key ) = @_;
    delete $self->{ $key };
}

=head2 has( $key )

Return the data if the exists otherwise return C<undef>.

=cut

sub has {
    my( $self, $key ) = @_;
    return exists $self->{ $key } ? $self->{ $key } : undef;
}


package WWW::CheckSite::Util::Stack;

=head1 WWW::CheckSite::Util::Stack

Implements a simple "Last in First out" stack. (They're called arrays
in Perl :-)

=cut

sub new {
    return bless [ ], shift;
}

=head2 push( $data )

Push C<$data> onto the stack.

=cut

sub push {
    my( $self, $data ) = @_;
    push @$self, $data;
}

=head2 pop

Return the last data pushed onto the stack.

=cut

sub pop {
    my $self = shift;
    return @$self ? pop @$self : undef;
}

=head2 peek

Return the last item on the stack without popping it.

=cut

sub peek {
    my $self = shift;
    return @$self ? $self->[-1] : undef;
}

=head2 size

Return the size of the stack.

=cut

sub size {
    my $self = shift;
    return scalar @$self;
}

=head1 COPYRIGHT

=cut
