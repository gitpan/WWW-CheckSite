#! perl -w
use strict;

# $Id: 10validator.t 440 2005-12-04 16:11:04Z abeltje $
use Test::More;

my( $port, $pid, $s ) = ( 54321 );
my %test;
BEGIN {
    $port = 54321;
    %test = (
        "http://localhost:$port/index.html" => {
            link_cnt => 5, links_ok => 5, image_cnt => 1, images_ok => 1,
             status => 200,
        },
        "http://localhost:$port/linkbroken.html" => {
            link_cnt => 2, links_ok => 1, image_cnt => 0, images_ok => 0,
            status => 200,
        },
        "http://localhost:$port/imagebroken.html" => {
            link_cnt => 1, links_ok => 1, image_cnt => 2, images_ok => 1,
            status => 200,
        },
        "http://localhost:$port/areabroken.html" => {
            link_cnt => 1, links_ok => 0, image_cnt => 1, images_ok => 1,
            status => 200,
        },
        "http://localhost:$port/doesnotexist.html" => {
            link_cnt => 0, links_ok => 0, image_cnt => 0, images_ok => 0,
            status => 404,
        },
        "http://localhost:$port/norobots.html" => {
            link_cnt => 4, links_ok => 4, image_cnt => 0, images_ok => 0,
            status => 200,
        },
    );
}

use File::Spec::Functions qw( :DEFAULT rel2abs abs2rel );
use File::Basename;
my $findbin;
BEGIN {
    eval { use WWW::Mechanize };
    plan $@
        ? ( skip_all => "No WWW::Mechanize available ($@)" )
        : ( tests => 8 + 5 * scalar keys %test );
    $findbin = rel2abs dirname $0;
}

use lib catdir $findbin, 'lib';
use_ok 'HTTPD';
{ # Set up local server

    ok $s = HTTPD->new( $port ), "Created HTTPD";
    isa_ok $s, 'HTTPD';

    $pid = $s->background;
    my $droot = abs2rel $s->{docroot};
    ok $pid, "Local webever running as $pid on port $port ($droot)";
}
END { $pid and kill 9, $pid }

my $verbose = $ENV{WCS_VERBOSE} || 0;
use_ok 'WWW::CheckSite::Validator';

{
    my $sp = WWW::CheckSite::Validator->new(
        v => $verbose,
        uri => "http://localhost:$port/index.html",
        validate => 'by_none',
    );
    isa_ok $sp, "WWW::CheckSite::Validator";

    ok my $index = $sp->get_page, "Got the index-page";

    my %pages = ( $index->{ret_uri} => $index );
    while ( my $info = $sp->get_page ) { $pages{ $info->{ret_uri} } = $info }
    is keys %pages, 6, "Got all the pages";

    for my $pg ( keys %test ) {

        is $pages{ $pg }->{link_cnt}, $test{ $pg }->{link_cnt},
           "links on page ($pg) $pages{ $pg }->{link_cnt}";
        is $pages{ $pg }->{links_ok}, $test{ $pg }->{links_ok},
           "links_ok on page ($pg) $pages{ $pg }->{links_ok}";

        is $pages{ $pg }->{image_cnt}, $test{ $pg }->{image_cnt},
           "images on page ($pg) $pages{ $pg }->{image_cnt}";
        is $pages{ $pg }->{images_ok}, $test{ $pg }->{images_ok},
           "images_ok on page ($pg) $pages{ $pg }->{images_ok}";

        is $pages{ $pg }->{status}, $test{ $pg }->{status},
           "status of page ($pg) $pages{ $pg }->{status}";
    }
}
