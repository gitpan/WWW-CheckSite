#! perl
use strict;
use warnings;
use FindBin;

# $Id: 11validator.t 274 2005-03-20 11:35:32Z abeltje $
use Test::More 'no_plan';

my %test = (
    "file://$FindBin::Bin/docroot/index.html" => {
        head => 0, check => 1, fetch => 1, validate => 0,
    },
    "file://$FindBin::Bin/docroot/linkbroken.html" => {
        head => 1, check => 1, fetch => 1, validate => 0,
    },
    "file://$FindBin::Bin/docroot/imagebroken.html" => {
        head => 1, check => 1, fetch => 1, validate => 0,
    },
    "file://$FindBin::Bin/docroot/areabroken.html" => {
        head => 1, check => 1, fetch => 1, validate => 0,
    },
    "file://$FindBin::Bin/docroot/doesnotexist.html" => {
        head => 1, check => 1, fetch => 1, validate => 0,
    },
    "file://$FindBin::Bin/docroot/dot.gif" => {
        head => 1, check => 1, fetch => 0, validate => 0,
    },
);

use_ok 'WWW::CheckSite::Validator';

{
    local *SAVEOUT; open SAVEOUT, ">& STDOUT";
    my $out = tie *STDOUT, 'CatchOut';
    ok my $wcs = WWW::CheckSite::Validator->new(
        validate => 'by_none',
        uri      => "file://$FindBin::Bin/docroot/index.html",
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
