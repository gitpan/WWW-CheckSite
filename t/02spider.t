#! perl -w
use strict;

# $Id: 02spider.t 440 2005-12-04 16:11:04Z abeltje $
use Test::More;

use File::Spec::Functions qw( :DEFAULT rel2abs abs2rel );
use File::Basename;
my $findbin;
BEGIN {
    eval { use WWW::Mechanize };
    plan $@
        ? ( skip_all => "No WWW::Mechanize available ($@)" )
        : ( tests => 17 );
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

 
my $verbose = $ENV{WCS_VERBOSE} || 0;

use_ok 'WWW::CheckSite::Spider';

{
    my $sp = WWW::CheckSite::Spider->new( v=> $verbose,
        uri      => "http://localhost:$port/index.html",
        ua_class => 'WWW::Mechanize',
        myrules  => [ "norobots.html" ],
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

    is  $ok, 4, "ok - pages";

    is $nok, 1, "not ok - pages"
}

{
    my $sp = WWW::CheckSite::Spider->new( v=> $verbose,
        uri      => "http://localhost:$port/index.html",
        ua_class => 'WWW::Mechanize',
        exclude  => qr/norobots.html$/,
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

    is  $ok, 4, "ok - pages";
    is $nok, 1, "not ok - pages"
}
