#! perl -w
use strict;
use Data::Dumper;

use FindBin;
use Test::More 'no_plan';

my $verbose = $ENV{WCS_VERBOSE} || 0;

use_ok 'WWW::CheckSite::Spider';

SKIP: {
    eval { require WWW::Mechanize };
    $@ and skip "No WWW::Mechanize available ($@)", 6;

    my $sp = WWW::CheckSite::Spider->new( v=> $verbose,
        uri      => "file://$FindBin::Bin/docroot/index.html",
        ua_class => 'WWW::Mechanize',
        myrules  => ['norobots.html'],
    );

    isa_ok $sp, 'WWW::CheckSite::Spider';

    ok my $index = $sp->get_page, "A page returned";
    is $index->{status}, 200, "Return status ok";

    my @pages = ( $index );
    while ( my $info = $sp->get_page ) {
        push @pages, $info;
    }

    is @pages, 5, "Got enough pages from spider";

    my( $ok, $nok );
    ($_->{status} == 200 ? $ok : $nok)++ for @pages;

    is  $ok, 3, "ok - pages";
    is $nok, 2, "not ok - pages"
}
