#! perl
use strict;
use warnings;

# $Id: 11validator.t 673 2007-05-28 19:01:18Z abeltje $
use Test::More;

use File::Spec::Functions qw( :DEFAULT rel2abs abs2rel );
use File::Basename;
my $findbin;
BEGIN {
    eval { use WWW::Mechanize };
    plan $@
        ? ( skip_all => "No WWW::Mechanize available ($@)" )
        : ( tests => 23 );
    $findbin = rel2abs dirname $0;
}

use lib catdir $findbin, 'lib';
use_ok 'HTTPD';

my $port;
{
    use_ok 'IO::Socket::INET';
    my $s = IO::Socket::INET->new( Listen => 5, Proto => 'tcp' );
    $port = $s->sockport;
    ok $port, "Using port $port for server";
}

my( $pid, $s );
{ # Set up local server

    ok $s = HTTPD->new( $port ), "Created HTTPD";
    isa_ok $s, 'HTTPD';

    $pid = $s->background;
    my $droot = abs2rel $s->{docroot};
    ok $pid, "Local webever running as $pid on port $port ($droot)";
}
END { $pid and kill 9, $pid }

my $imgreq;
BEGIN {
    eval qq{use Image::Info qw( image_info )};
    $imgreq = $@ ? 'HEAD' : 'GET';
#    diag "will be ${imgreq}ing images($@)";
}

my %test = (
    "http://localhost:%u/index.html" => {
        head => '', check => 1, fetch => 1, validate => 0,
    },
    "http://localhost:%u/linkbroken.html" => {
        head => 'HEAD', check => 1, fetch => 1, validate => 0,
    },
    "http://localhost:%u/imagebroken.html" => {
        head => 'HEAD', check => 1, fetch => 1, validate => 0,
    },
    "http://localhost:%u/areabroken.html" => {
        head => 'HEAD', check => 1, fetch => 1, validate => 0,
    },
    "http://localhost:%u/doesnotexist.html" => {
        head => 'HEAD', check => 1, fetch => 1, validate => 0,
    },
    "http://localhost:%u/dot.gif" => {
        head => $imgreq, check => 1, fetch => 0, validate => 0,
    },
);

my @tsturi = keys %test;
$test{ sprintf $_, $port } = delete $test{ $_ } for @tsturi;

use_ok 'WWW::CheckSite::Validator';

{
    local *SAVEOUT; open SAVEOUT, ">& STDOUT";
    my $out = tie *STDOUT, 'CatchOut';
    ok my $wcs = WWW::CheckSite::Validator->new(
        html_by  => 'by_none',
        css_by   => 'by_none',
        uri      => ["http://localhost:$port/index.html"],
        v        => 1,
    ), "called new()";
    isa_ok $wcs, 'WWW::CheckSite::Validator';

    like $$out, qr/^Setting rules/m, 'init robot rules';
    like $$out, qr/^  Check '$wcs->{uri}[0]'/m, "checked (rr) base uri";

    my @pages;
    while ( defined( my $page = $wcs->get_page ) ) {
        push @pages, $page;
    }

    for my $page ( keys %test ) {
        my $request = $test{ $page }{head};
        if ( $request ) {
            like $$out, qr/^  $request '$page': done/m,
                 "Found $request request ($page)";
        } else {
            unlike $$out, qr/^  HEAD '$page': done/m,
                   "Skipped HEAD request ($page)";
        }
        if ( $test{ $page }{fetch} ) {
            like $$out, qr/^Fetch: '$page': done/m,
                 "Found GET request ($page)";
        } else {
            unlike $$out, qr/^Fetch: '$page': done/m,
                   "Skipped GET request ($page)";
        }
    }
}

package CatchOut;

sub TIEHANDLE {
    my $class = shift;
    bless \(my $buf), $class;

}

sub PRINT {
    my $buf = shift;
    $$buf .= join "", @_;
}

sub PRINTF {
    my $buf = shift;
    my $fmt = shift;
    $$buf .= sprintf $fmt, @_;
}

1;
