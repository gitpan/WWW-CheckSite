#! perl -w
use strict;
use FindBin;

# $Id: 01spider.t 259 2005-03-07 23:56:41Z abeltje $
use Test::More tests => 10;

my $verbose = $ENV{WCS_VERBOSE} || 0;
BEGIN { use_ok 'WWW::CheckSite::Spider', ':const' }

ok exists &WCS_UNKNOWN,   "WCS_UNKNOWN";
ok exists &WCS_FOLLOWED,  "WCS_FOLLOWED";
ok exists &WCS_SPIDERED,  "WCS_SPIDERED";
ok exists &WCS_TOSPIDER,  "WCS_TOSPIDER";
ok exists &WCS_NOCONTENT, "WCS_NOCONTENT";
ok exists &WCS_OUTSCOPE,  "WCS_OUTSCOPE";

{
    my $sp = eval { WWW::CheckSite::Spider->new };
    my $error = $@;
    ok $error, "Die on no args";
    like $error, qr/No uri to spider specified!/, "Got the right error";
}

{
    my $sp = WWW::CheckSite::Spider->new(
        { v => $verbose, uri => "file://$FindBin::Bin/docroot/index.html" }
    );
    isa_ok $sp, 'WWW::CheckSite::Spider';
}
