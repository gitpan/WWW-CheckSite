#! perl
use strict;
use warnings;

# $Id: 11validator.t 440 2005-12-04 16:11:04Z abeltje $
use Test::More;

use File::Spec::Functions qw( :DEFAULT rel2abs abs2rel );
use File::Basename;
my $findbin;
BEGIN {
    eval { use WWW::Mechanize };
    plan $@
        ? ( skip_all => "No WWW::Mechanize available ($@)" )
        : ( tests => 21 );
    $findbin = rel2abs dirname $0;
}

use lib catdir $findbin, 'lib';
use_ok 'HTTPD';
my( $port, $pid, $s ) = ( 54321 );
{ # Set up local server

    ok $s = HTTPD->new( $port ), "Created HTTPD";
    isa_ok $s, 'HTTPD';

    $pid = $s->background;
    my $droot = abs2rel $s->{docroot};
    ok $pid, "Local webever running as $pid on port $port ($droot)";
}
END { $pid and kill 9, $pid }

my %test = (
    "http://localhost:$port/index.html" => {
        head => 0, check => 1, fetch => 1, validate => 0,
    },
    "http://localhost:$port/linkbroken.html" => {
        head => 1, check => 1, fetch => 1, validate => 0,
    },
    "http://localhost:$port/imagebroken.html" => {
        head => 1, check => 1, fetch => 1, validate => 0,
    },
    "http://localhost:$port/areabroken.html" => {
        head => 1, check => 1, fetch => 1, validate => 0,
    },
    "http://localhost:$port/doesnotexist.html" => {
        head => 1, check => 1, fetch => 1, validate => 0,
    },
    "http://localhost:$port/dot.gif" => {
        head => 1, check => 1, fetch => 0, validate => 0,
    },
);

use_ok 'WWW::CheckSite::Validator';

{
    local *SAVEOUT; open SAVEOUT, ">& STDOUT";
    my $out = tie *STDOUT, 'CatchOut';
    ok my $wcs = WWW::CheckSite::Validator->new(
        validate => 'by_none',
        uri      => "http://localhost:$port/index.html",
        v        => 1,
    ), "called new()";
    isa_ok $wcs, 'WWW::CheckSite::Validator';

    like $$out, qr/^Robot rules/m, 'init robot rules';
    like $$out, qr/^  Check '$wcs->{uri}'/m, "checked (rr) base uri";

    my @pages;
    while ( defined( my $page = $wcs->get_page ) ) {
        push @pages, $page;
    }

    for my $page ( keys %test ) {
        if ( $test{ $page }{head} ) {
            like $$out, qr/^  HEAD '$page': done/m, "Found HEAD request";
        } else {
            unlike $$out, qr/^  HEAD '$page': done/m, "Skipped HEAD request";
        }
        if ( $test{ $page }{fetch} ) {
            like $$out, qr/^Fetch: '$page': done/m, "Found GET request";
        } else {
            unlike $$out, qr/^Fetch: '$page': done/m, "Skipped GET request";
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
