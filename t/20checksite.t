#! perl
use strict;
use warnings;
use FindBin;
use File::Spec::Functions;

# $Id: 20checksite.t 274 2005-03-20 11:35:32Z abeltje $
use Test::More 'no_plan';

my $verbose = $ENV{WCS_VERBOSE} || 0;

use_ok 'WWW::CheckSite';

{
    my $wcs = WWW::CheckSite->new( v => $verbose,
        prefix => 'xxxtest',
        uri    => 'file://$FindBin::Bin/docroot/index.html',
    );
    isa_ok $wcs, 'WWW::CheckSite';
}

{
    ok my $wcs = WWW::CheckSite->load( v => $verbose,
        prefix => 'tsorg',
        dir    => $FindBin::Bin,
    ), 'loaded info from saved data';
    isa_ok $wcs, 'WWW::CheckSite';

    is $wcs->{uri}, 'http://www.test-smoke.org/', 'uri was set';

    ok $wcs->write_report, "write_report()";

    my $full = WWW::CheckSite::name_outfile( $wcs->_datadir, 'full' );
    ok -f $full, "full report exists";

    my $summ = WWW::CheckSite::name_outfile( $wcs->_datadir, 'summ' );
    ok -f $summ, "summary report exists";


    for my $rep ( $summ, $full ) {
        1 while unlink $rep;
    }
}
