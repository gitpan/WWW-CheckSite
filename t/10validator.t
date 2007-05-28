#! perl -w
use strict;

# $Id: 10validator.t 673 2007-05-28 19:01:18Z abeltje $
use Test::More;

my %test;
BEGIN {
    %test = (
        "http://localhost:%u/index.html" => {
            link_cnt => 6, links_ok => 6, image_cnt => 1, images_ok => 1,
             style_cnt => 1, status => 200,
        },
        "http://localhost:%u/linkbroken.html" => {
            link_cnt => 2, links_ok => 1, image_cnt => 0, images_ok => 0,
            style_cnt => 0, status => 200,
        },
        "http://localhost:%u/imagebroken.html" => {
            link_cnt => 1, links_ok => 1, image_cnt => 2, images_ok => 1,
            style_cnt => 0, status => 200,
        },
        "http://localhost:%u/areabroken.html" => {
            link_cnt => 1, links_ok => 0, image_cnt => 1, images_ok => 1,
            style_cnt => 0, status => 200,
        },
        "http://localhost:%u/doesnotexist.html" => {
            link_cnt => 0, links_ok => 0, image_cnt => 0, images_ok => 0,
            style_cnt => 0, status => 404,
        },
        "http://localhost:%u/norobots.html" => {
            link_cnt => 4, links_ok => 4, image_cnt => 0, images_ok => 0,
            style_cnt => 0, status => 200,
        },
        "http://localhost:%u/inlinestyle.html" => {
            link_cnt => 1, links_ok => 1, image_cnt => 0, images_ok => 0,
            style_cnt => 2, status => 200,
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
        : ( tests => 10 + 6 * scalar keys %test );
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

my @tsturi = keys %test;
$test{ sprintf $_, $port } = delete $test{ $_ } for @tsturi;

my $verbose = $ENV{WCS_VERBOSE} || 0;
use_ok 'WWW::CheckSite::Validator';

{
    my $sp = WWW::CheckSite::Validator->new(
        v           => $verbose,
        uri         => ["http://localhost:$port/index.html"],
        strictrules => 0,
        html_by     => 'by_none',
        css_by      => 'by_none',
    );
    isa_ok $sp, "WWW::CheckSite::Validator";

    ok my $index = $sp->get_page, "Got the index-page";

    my %pages = ( $index->{ret_uri} => $index );
    while ( my $info = $sp->get_page ) { $pages{ $info->{ret_uri} } = $info }
    is keys %pages, 7, "Got all the pages";

    for my $pg ( keys %test ) {

        is $pages{ $pg }->{link_cnt}, $test{ $pg }->{link_cnt},
           "links on page ($pg) $pages{ $pg }->{link_cnt}";
        is $pages{ $pg }->{links_ok}, $test{ $pg }->{links_ok},
           "links_ok on page ($pg) $pages{ $pg }->{links_ok}";

        is $pages{ $pg }->{image_cnt}, $test{ $pg }->{image_cnt},
           "images on page ($pg) $pages{ $pg }->{image_cnt}";
        is $pages{ $pg }->{images_ok}, $test{ $pg }->{images_ok},
           "images_ok on page ($pg) $pages{ $pg }->{images_ok}";

        is $pages{ $pg }->{style_cnt}, $test{ $pg }->{style_cnt},
           "styles on page ($pg) $pages{ $pg }->{style_cnt}";

        is $pages{ $pg }->{status}, $test{ $pg }->{status},
           "status of page ($pg) $pages{ $pg }->{status}";
    }
}
