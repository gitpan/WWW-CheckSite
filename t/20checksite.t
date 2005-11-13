#! perl
use strict;
use warnings;
use FindBin;
use File::Spec::Functions;

# $Id: 20checksite.t 432 2005-11-13 10:31:47Z abeltje $
use Test::More tests => 9;

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

    my @e_links = sort qw(
    http://archive.develooper.com/daily-build-reports@perl.org/
    http://jigsaw.w3.org/css-validator/validator?uri=http://www.Test-Smoke.org/
    http://search.cpan.org/dist/Test-Smoke
    http://validator.w3.org/check?uri=referer
    http://www.nntp.perl.org/group/perl.daily-build.reports
    http://www.test-smoke.org/

    http://www.test-smoke.org/FAQ.html 

    http://www.test-smoke.org/cgi/smoquel
    http://www.test-smoke.org/cgi/tsdb
    http://www.test-smoke.org/cgi/tsdb?pversion=5.9.2
    http://www.test-smoke.org/download/Test-Smoke-1.19.tar.gz
    http://www.test-smoke.org/download/V-0.10.tar.gz
    http://www.test-smoke.org/index.html
    http://www.test-smoke.org/otherperl.html
    http://www.test-smoke.org/source.html
    http://www.test-smoke.org/status.shtml
    http://www.test-smoke.org/tinysmokedb.shtml
    http://ztreet.xs4all.nl/album/smokefarm/
    ), (
    'http://www.test-smoke.org/FAQ.html#can_i_interrupt_a_smoke_run',
    'http://www.test-smoke.org/FAQ.html#can_i_still_generate_a_report_after_an_interrupted_smoke',
    'http://www.test-smoke.org/FAQ.html#how_can_i_run_continues_smokes',
    'http://www.test-smoke.org/FAQ.html#how_can_i_skip_a_step_in_smokeperl_pl',
    'http://www.test-smoke.org/FAQ.html#how_do_i_create_different_smokeconfigurations',
    'http://www.test-smoke.org/FAQ.html#how_do_i_include_copyonwrite_testing_in_my_smokes',
    'http://www.test-smoke.org/FAQ.html#how_do_i_investigate_failures',
    'http://www.test-smoke.org/FAQ.html#how_do_i_smoke_my_patch',
    'http://www.test-smoke.org/FAQ.html#item_smokeperl_2epl',
    'http://www.test-smoke.org/FAQ.html#what_are_all_the_scripts_in_the_smoke_suite_for',
    'http://www.test-smoke.org/FAQ.html#what_are_these_configuration_files_about',
    'http://www.test-smoke.org/FAQ.html#what_is_test__smoke',
    'http://www.test-smoke.org/FAQ.html#what_s_with_the_dailybuild_and_smokers_names',
    'http://www.test-smoke.org/FAQ.html#where_do_the_reports_go',
    'http://www.test-smoke.org/FAQ.html#where_is_test__smoke',
    'http://www.test-smoke.org/FAQ.html#why_is_test__smoke',
    );
    my @g_links = $wcs->dump_links;

    TODO : {
        local $TODO = "Get the return url from HEAD right";
        is_deeply \@g_links, \@e_links, "All links returned";
    }
}
