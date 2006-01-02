#! /usr/bin/perl -w
use strict;
use 5.006;

# $Id: Makefile.PL 453 2006-01-02 02:11:27Z abeltje $
use ExtUtils::MakeMaker;

# This may be crude...
eval qq{use Template () };
my $has_tt = !$@;
# eval qq{use HTML::Template () };
# my $has_ht = !$@;

# Prefer HTML::Template: less stuff to install
my %template = $has_tt ? ( 'Template' => 2 ) : ( 'HTML::Template' => 0 );

WriteMakefile(
    NAME         => "WWW::CheckSite",
    VERSION_FROM => 'lib/WWW/CheckSite.pm',
    PREREQ_PM    => {
        'Storable'        => 2.06, # Earliest version tested
        'Time::HiRes'     => 0,
        'LWP'             => 0,
        'WWW::Mechanize'  => 1.08,
        'WWW::RobotRules' => 0,
        %template
    },

    ABSTRACT_FROM => 'lib/WWW/CheckSite.pm',
    AUTHOR        => 'Abe Timmerman <abeltje@cpan.org>',

    EXE_FILES    => [qw( checksite )]
);
