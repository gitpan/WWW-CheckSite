#! perl -w
use strict;

# $Id: 01spider.t 440 2005-12-04 16:11:04Z abeltje $
use Test::More tests => 10;

use File::Spec::Functions qw( :DEFAULT rel2abs );
use File::Basename;
my $findbin;
BEGIN { $findbin = rel2abs dirname $0 }

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
        { v => $verbose, uri => "file://$findbin/docroot/index.html" }
    );
    isa_ok $sp, 'WWW::CheckSite::Spider';
}
