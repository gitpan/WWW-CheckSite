#! /usr/bin/perl
use warnings FATAL => 'all';
use strict;

# $Id: pod_ok.t 555 2006-10-08 09:23:57Z abeltje $

use File::Spec::Functions;
use Test::More;

my @test_files;
BEGIN {
    @test_files = qw( checksite );

    push @test_files, map catfile( 'lib', 'WWW', 'CheckSite', $_ )
        => qw( Spider.pm Validator.pm Util.pm Manual.pod );

    push @test_files, map catfile( 'lib', 'WWW', $_ )
        => qw( CheckSite.pm );
}
eval "use Test::Pod 1.00";
plan $@
    ? (skip_all => "Test::Pod 1.00 required")
    : (tests => scalar @test_files );

pod_file_ok( $_ ) for @test_files;
