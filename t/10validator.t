#! perl -w
use strict;
use FindBin;
use Data::Dumper;

# $Id: 10validator.t 264 2005-03-16 14:33:26Z abeltje $
use Test::More 'no_plan';

my $verbose = $ENV{WCS_VERBOSE};
my %test = (
    "file://$FindBin::Bin/docroot/index.html" => {
        link_cnt => 3, image_cnt => 1, status => 200,
    },
    "file://$FindBin::Bin/docroot/linkbroken.html" => {
        link_cnt => 2, image_cnt => 0, status => 200,
    },
    "file://$FindBin::Bin/docroot/imagebroken.html" => {
        link_cnt => 1, image_cnt => 2, status => 200,
    },
    "file://$FindBin::Bin/docroot/areabroken.html" => {
        link_cnt => 0, image_cnt => 0, status => 404,
    },
    "file://$FindBin::Bin/docroot/doesnotexist.html" => {
        link_cnt => 0, image_cnt => 0, status => 404,
    },
);

use_ok 'WWW::CheckSite::Validator';

{
    my $sp = WWW::CheckSite::Validator->new(
        v => $verbose,
        uri => "file://$FindBin::Bin/docroot/index.html",
        validate => 'by_none',
    );
    isa_ok $sp, "WWW::CheckSite::Validator";

    ok my $index = $sp->get_page, "Got the index-page";

    my %pages = ( $index->{ret_uri} => $index );
    while ( my $info = $sp->get_page ) { $pages{ $info->{ret_uri} } = $info }
    is keys %pages, 5, "Got all the pages";

    for my $pg ( keys %test ) {
        is $pages{ $pg }->{link_cnt}, $test{ $pg }->{link_cnt},
           "links on page ($pg)";
        is $pages{ $pg }->{image_cnt}, $test{ $pg }->{image_cnt},
           "images on page ($pg)";
        is $pages{ $pg }->{status}, $test{ $pg }->{status},
           "status of page ($pg)";
    }
}
