package HTTPD;
use strict;
use warnings;

# $Id: HTTPD.pm 440 2005-12-04 16:11:04Z abeltje $
use vars qw( $VERSION $DEBUG );
$VERSION = '0.003';
$DEBUG ||= 0;


use base 'HTTP::Server::Simple::CGI';

use File::Spec::Functions qw( :DEFAULT rel2abs );
use File::Basename;
my $findbin;
BEGIN { $findbin = rel2abs dirname $INC{ 'HTTPD.pm' }; }

sub new {
    my $class = shift;
    my $self = $class->SUPER::new( @_ );
    $self->{docroot} = defined $_[1]
        ? $_[1]
        : catdir( $findbin, updir, 'docroot' );

    $self->get_mime_types;
}

sub print_banner { };

sub get_mime_types {
    my $self = shift;
    my $mypath = dirname $INC{ 'HTTPD.pm' };
    my $mt_file = catfile $mypath, 'mime.types';

    my %mime;
    open my $mt, "< $mt_file" or die "[mime.types] $mt_file: $!";
    while ( my $line = <$mt> ) {
        $line =~ /^\s*$/ and next;
        $line =~ /^#/    and next;
        my( $type, @ext ) = split ' ', $line;
        @ext or next;
        for my $ext ( @ext ) { $mime{ $ext } = $type }
    }
    close $mt;
    $self->{mime} = \%mime;

    return $self;
}

sub handle_request {
    my( $self, $cgi ) = @_;

    ( my $rfile = $ENV{REQUEST_URI} ) =~ s|^/||;
    my $lfile = catfile $self->{docroot}, $rfile;
    return $self->do_404( $lfile, $@ ) unless -f $lfile;

    my( $ext ) = $rfile =~ /\.(\w+)$/;
    my $mime_type = $self->{mime}{ $ext } || 'text/html';

    my $content = do {
        open my $fh, "< $lfile" or return $self->do_403;
        local $/; <$fh>;
    };

    my $resp = join( "\015\012", split( /\n/, <<EO_HEAD ), "", ""  ) . $content;
$ENV{SERVER_PROTOCOL} 200 OK
Content-Type: $mime_type
Content-Length: @{[ length $content ]}
EO_HEAD

    print $resp;
}

sub do_404 {
    my $resp = join( "\015\012", split( /\n/, <<EO_HEAD ), "", ""  );
$ENV{SERVER_PROTOCOL} 404 NOT OK
EO_HEAD

    $DEBUG and print STDERR "$_[1] ($_[2])\n$resp";
    print $resp;
}
    
sub do_403 {
    my $resp = join( "\015\012", split( /\n/, <<EO_HEAD ), "", ""  );
$ENV{SERVER_PROTOCOL} 403 NOT OK
EO_HEAD

    $DEBUG and print STDERR $resp;
    print $resp;
}
    

1;
