#! /usr/bin/perl -w
use strict;
use 5.006;

# $Id: Makefile.PL 283 2005-04-02 09:49:39Z abeltje $
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => "WWW::CheckSite",
    VERSION_FROM => 'lib/WWW/CheckSite.pm',
    PREREQ_PM    => { 
        'Time::HiRes'     => 0,
        'WWW::Mechanize'  => 1.08, # Handles the LWP dependency
        'WWW::RobotRules' => 0,
        'HTML::Template'  => 0,
    },

    ABSTRACT_FROM => 'lib/WWW/CheckSite.pm',
    AUTHOR        => 'Abe Timmerman <abeltje@cpan.org>',

    EXE_FILES    => [qw( checksite )]
);
