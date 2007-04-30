#! /usr/bin/perl
use warnings FATAL => 'all';
use strict;

# $Id: pod_coverage.t 555 2006-10-08 09:23:57Z abeltje $

use Test::More;

my @test_files;
BEGIN {
    push @test_files, map join( '::',  'WWW', 'CheckSite', $_ )
        => qw( Spider Validator Util );

    push @test_files, map join( '::', 'WWW', $_ )
        => qw( CheckSite );
}
eval "use Test::Pod::Coverage";
plan $@
    ? (skip_all => "Test::Pod::Coverage required.")
    : (tests => scalar @test_files);

for my $pkg ( @test_files ) {
    pod_coverage_ok( $pkg );
}

