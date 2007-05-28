package WWW::CheckSite;
use strict;
use warnings;

# $Id: CheckSite.pm 670 2007-05-28 18:48:29Z abeltje $
our $VERSION = '0.019_51';

=head1 NAME

WWW::CheckSite - OO interface to an iterator that checks a website

=head1 SYNOPSIS

    use WWW::CheckSite;

    my $wcs = WWW::CheckSite->new(
        uri    => 'http://www.test-smoke.org/',
        prefix => 'tsorg',
        save   => 1,
    );

    $wcs->validate;

    $wcs->write_report;

Or using saved data (skip the real validation):

    my $wcs = WWW::CheckSite->load(
        uri    => 'http://www.test-smoke.org/',
        prefix => 'tsorg',
    );

    $wcs->write_report;

=head1 DESCRIPTION

This module implents a spider, that checks the pages on a website. For
each page the links and images on that page are checked for
availability. After that, the page is validated by I<W3.ORG>.

When the spider is done, one can have a report in HTML written.

B<WARNING>: Although the spider respects F</robots.txt> on the target
site, the validator does not! Use this tool only on your own sites.

=head1 METHODS

=cut

BEGIN { eval qq{ use Time::HiRes qw( time ); } }
use FindBin;
use Storable qw( nstore retrieve );
use File::Spec::Functions qw( :DEFAULT rel2abs );
use File::Basename;
use File::Path;
use URI::file;

use WWW::CheckSite::Validator;

=head2 WWW::CheckSite->new( %args )

Initialize a new instance. Options supported:

=over 4

=item * B<uri> =>  the base uri to check [mandatory]

=item * B<prefix> => the name of the project [mandatory]

=item * B<dir> => target directory (curdir())

=item * B<save> => true/false (false)

=item * B<strictrules> => true/false (false)

=item * B<validate> => by_none/by_uri/by_upload (by_none)

=item * B<ua_class> => override the user agent class

=item * B<ua_args> => hashref with extra options passed to the user agent class

=item * B<v> => I<$verbosity>, where I<$verbosity> may be

=item * B<tt> => boolean to allow the use of Template Toolkit

=over

=item 0

Be quiet (default).

=item 1

Report basic information for every visited page (e.g. number of links
and images) and total time for checking the site.

=item 2

Additional reporting of page validation details.

=back

=back

=cut

sub new {
    my $class = shift;

    my %args = @_ ? ref $_[0] ? %{ +shift } : @_ : ();
    exists $args{tt} or $args{tt} = 1;

    exists $args{uri} && length $args{uri} or
        _die( "", "Usage: WWW::CheckSite->new( uri => q<your_uri> )" );

    exists $args{prefix} && length $args{prefix} or
        _die( "", "Usage: WWW::CheckSite->load( prefix => 'xxx' )" );

    # Backward compatibility wrt {uri}
    ref $args{uri} or $args{uri} = [ $args{uri} ];

    bless \%args, $class;
}

=head2 WWW::CheckSite->load( %args )

Initialize the object from datafile. Supported options:

=over 4

=item * B<dir> => target/source directory

=item * B<prefix> => the prefix used for this dataset [mandatory]

=item * B<tt> => boolean to allow the use of Template Toolkit

=back

=cut

sub load {
    my $class = shift;

    my %args = ref $_[0] ? %{ +shift } : @_;
    exists $args{tt} or $args{tt} = 1;

    exists $args{prefix} && length $args{prefix} or
        _die( "", "Usage: WWW::CheckSite->load( prefix => 'xxx' )" );

    my $tmp = bless \%args, $class;
    my $wcsfile = $tmp->_datafile;

    -f $wcsfile && -r _ or _die( "", "Cannot find '$wcsfile': $!" );

    my $self = retrieve $wcsfile;
    $self->{v} and print "Loaded '$wcsfile'\n";
    exists $args{ $_ } and $self->{ $_ } = $args{ $_ }
        for qw( dir prefix tt v html_by css_by html_validator css_validator );

    # Backward compatibility wrt {uri}
    ref $self->{uri} or $self->{uri} = [ $self->{uri} ];

    $self->_set_validator_fmt;

    return $self;
}

=head2 $wcs->validate

The C<validate()> method collects all the data.

=cut

sub validate {
    my $self = shift;

    my $wcs = WWW::CheckSite::Validator->new(
        uri            => $self->{uri},
        ua_class       => $self->{ua_class},
        ua_args        => $self->{ua_args},
        exclude        => $self->{exclude},
        html_validator => $self->{html_validator},
        html_by        => $self->{html_by},
        css_validator  => $self->{css_validator},
        css_by         => $self->{css_by},
        strictrules    => $self->{strictrules},
        lang           => $self->{lang},
        myrules        => $self->{myrules},
        v               => $self->{v} > 1,
    );

    my( $cnt, $intref ) = ( 0, 'a' );
    $self->{start_time} = time;
    while ( my $info = $wcs->get_page ) {
        $info->{intref} = $intref++
            if $info->{ret_uri} =~ /^\Q$self->{uri}[0]/;

        push @{ $self->{by_depth}{ $info->{depth} } }, $info->{ret_uri};
        $self->{report}{ $info->{ret_uri} } = $info;

        $self->{v} and printf "%5u %s (%u links; %u images; %s styles; %s)\n",
                              ++$cnt, @{ $info }{qw( ret_uri link_cnt 
                                                     image_cnt style_cnt)},
                              $info->{valid} ? $info->{valid} != -1
                                  ? 'valid' : 'skipped' : 'not valid';
    }
    $self->{spider_time} = time;

    $self->{v} and printf "That took %s\n", $self->_spider_time;

    $self->_set_validator_fmt;

    if ( $self->{save} ) {
        my $dir = $self->_datadir;
        unless ( -d $dir ) {
            mkpath( $dir, $self->{v} ) or
                $self->_die( "Cannot mkdir($dir): $!" );
        }
        nstore $self, $self->_datafile;
    }
}

=begin private

=head2 $wcs->_set_validator_fmt

Set the base format for the validator uri in the reports. It is based
on the W3 validator.

=end private

=cut

sub _set_validator_fmt {
    my( $self ) = @_;

    my $val_base = $self->{html_validator}
                || $WWW::CheckSite::Validator::VALIDATOR_XHTML;
    $self->{validator_fmt} = "$val_base/check?uri=%s";
}
 
=head2 $wcs->dump_links( $noskipped )

Return a list with all URLs encountered during site-traversal.

=cut

sub dump_links {
    my( $self, $noskipped ) = @_;

    my %seen;
    for my $url ( keys %{ $self->{report} } ) {
        $seen{ $url }++;
        for my $link ( @{ $self->{report}{ $url }{links} } ) {
            $seen{ $link->{uri} }++
                unless $noskipped && $link->{status} == 999;
        }
    }

    return sort keys %seen;
}

=begin private

=head2 $wcs->_spider_time

Return time in hhmm()

=end private

=cut

sub _spider_time {
    my $self = shift;
    return time_hhmm( @{ $self }{qw( start_time spider_time )} );
}

=begin private

=head2 $wcs->_report_time

Return time in hhmm()

=end private

=cut

sub _report_time {
    my $self = shift;
    return time_hhmm( @{ $self }{qw( rstart rfinish )} );
}

=begin private

=head2 $wcs->_datafile

Return the Storable file name.

=end private

=cut

sub _datafile {
    my $self = shift;
    return catfile $self->_datadir, "$self->{prefix}.wcs";
}
 
=begin private

=head2 $wcs->_datadir

Return the target directory name.

=end private

=cut

sub _datadir {
    my $self = shift;
    my $dir = $self->{dir} || curdir();
    return catdir $dir, $self->{prefix};
}
 
=head2 $wcs->write_report

Generate the reports.

=cut

sub write_report {
    my $self = shift;

    if ( $self->{tt} ) {
        # first check if we have Template Toolkit
        eval qq{use Template};
        return $self->write_tt_report unless $@;
    }

    # then check for HTML::Template
    eval qq{use HTML::Template};
    return $self->write_ht_report unless $@;

    $self->_die( "No supported template system found" );
}

=head2 $wcs->write_ht_report()

Load, fill the L<HTML::Template> template and write the reports.

=cut

sub write_ht_report {
    my $self = shift;

    my $dir = $self->_datadir;
    unless ( -d $dir ) {
        mkpath( $dir, $self->{v} ) or $self->_die( "Cannot mkdir($dir): $!" );
    }

    my $mainuri = ref $self->{uri} ? $self->{uri}[0] : $self->{uri};
    for my $type (qw( summ full )) {
        $self->{rstart} = time;
        my $report = create_report( "wcs${type}rpt.tmpl", $mainuri,
                                    @{ $self }{qw( by_depth report
                                                   validator_fmt v )} );
        $self->{rfinish} = time;

        $report->param( 
            spider_time  => $self->_spider_time,
            report_time  => $self->_report_time,
            now_time     => scalar localtime,
            did_validate => ($self->{validate} =~ /by_(?:upload|uri)/ ? 1 : 0),
            strict_rules => $self->{strictrules},
            language     => $self->{lang},
            summlink     => basename( name_outfile( $self->_datadir, 'summ' ) ),
            fulllink     => basename( name_outfile( $self->_datadir, 'full' ) ),
        );

        # write the report
        my $rptname = name_outfile( $self->_datadir, $type );
        open my $fh, "> $rptname" or
            $self->_die( "Cannot create($rptname): $!" );
        print $fh $report->output;
        close $fh or $self->_die( "Write error ($rptname): $!" );

        my $furi = URI::file->new_abs( $rptname );
        $self->{v} and print "Finished writing '$furi'\n";
    }
    return 1;
}

=head2 $wcs->write_tt_report()

Load, fill the L<Template> Toolkit template and write the reports.

=cut

sub write_tt_report {
    my $self = shift;

    my $dir = $self->_datadir;
    unless ( -d $dir ) {
        mkpath( $dir, $self->{v} ) or
            $self->_die( "Cannot mkdir($dir): $!" );
    }

    my $mainuri = ref $self->{uri} ? $self->{uri}[0] : $self->{uri};
    my $data = create_report_data( 'all', $mainuri,
                                   @{ $self }{qw( by_depth report
                                                  validator_fmt v )} );
    for my $type (qw( summ full )) {
        my $tt_name = "wcs${type}rpt.tt";
        $self->{rstart} = time;
        my $report = Template->new({
            INCLUDE_PATH => dirname( find_tmpl( $tt_name, $self->{v} ) ),
            POST_CHOMP => 1,
            EVAL_PERL  => 1,
        });
        $self->{rfinish} = time;

        my $rptname = name_outfile( $self->_datadir, $type );
        $report->process( $tt_name, {
            ( map +( $_ => $self->{ $_ } ) => qw( uri by_depth report v ) ),
            ( map +( $_ => $data->{ $_ } ) => keys %$data ),

            spider_time  => $self->_spider_time,
            report_time  => $self->_report_time,
            now_time     => scalar localtime,
            did_validate => ($self->{html_by} =~ /by_(?:upload|uri)/ ? 1 : 0),
            strict_rules => $self->{strictrules},
            language     => $self->{lang},
            summlink     => basename( name_outfile( $self->_datadir, 'summ' ) ),
            fulllink     => basename( name_outfile( $self->_datadir, 'full' ) ),
        },
            $rptname,
        ) || $self->_die( $report->error );

        my $furi = URI::file->new_abs( $rptname );
        $self->{v} and print "Finished writing '$furi'\n";
    }
    return 1;
}

=head2 $wcs->_die;

Do a Carp::croak().

=cut

sub _die {
    my $self = shift;
    require Carp;
    Carp::croak( @_ );
}

=head1 NO METHODS

=head2 create_report()

Load and fill the L<HTML::Template>.

=cut

sub create_report {
    my( $tmplnm, $v ) = @_[ 0, -1 ];

    my $data = create_report_data( @_ );

    my $tmpl = HTML::Template->new(
        filename => find_tmpl( $tmplnm, $v ),
        loop_context_vars => 1,
        die_on_bad_params => 0,
    );
    $tmpl->param( %$data );
    return $tmpl;
}

=head2 create_report_data()

Return a hash with all the data needed to fill both the
L<HTML::Template> and the L<Template> Toolkit templates.

=cut

sub create_report_data {
    my( $tmplnm, $url, $by_depth, $report, $validate_fmt, $v ) = @_;

    my %data = ( url => $url, title => $report->{ $url }{title},
                 valid_cnt => 0, valid_ok => 0, pages => [ ],
                 not_ok_cnt => 0, kw_total => 0 );

    $v > 1 and print "Using validator: '$validate_fmt'\n";
    foreach my $level ( sort { $a <=> $b } keys %$by_depth ) {
        $v > 1 and printf "[$tmplnm]Level %u, %u page(s)\n", $level,
                          scalar @{ $by_depth->{ $level } };

        foreach my $uri ( @{ $by_depth->{ $level } } ) {
            my $pinfo = $report->{ $uri };
            $pinfo->{uri} = $uri;
            $pinfo->{validator_uri} = sprintf $validate_fmt, $uri;
            $pinfo->{status_tx} = status_text( $pinfo->{status} );
            $pinfo->{status_ok} = $pinfo->{status} == 200;

            $pinfo->{all_ok} = $pinfo->{status_ok};
            for my $ikey (qw( links images styles )) {
                $pinfo->{ "all_${ikey}_ok" } = 1;
                $pinfo->{   "${ikey}_sk"   } = 0;
                $pinfo->{ "kw_${ikey}_cnt" } = 0;
            }

            foreach ( @{ $pinfo->{links} },
                      @{ $pinfo->{images} },
                      @{ $pinfo->{styles} } ) {
                $_->{status_tx} = status_text( $_->{status} );

                $_->{status_ok} = $_->{status} == 200;
                $_->{status_sk} = $_->{status} == 999;
                exists $_->{valid} and
                    $_->{status_ok} &&= $_->{valid};

                $pinfo->{all_ok} &&= ( $_->{status_ok} || $_->{status_sk} );

                $_->{text} =~ s/>No text in TAG</&gt;No text in $_->{tag}&lt;/
                    and $_->{no_text} = 1;

                $_->{"type_$_->{tag}"} = 1;
                $pinfo->{all_ok} &&= ! $_->{no_text};
                $_->{link_ok} = ! $_->{no_text} && $_->{status_ok};
                if ( $_->{tag} eq 'link' ) { # this is a style
                    $_->{status_sk} and $pinfo->{styles_sk}++;
                    $pinfo->{all_styles_ok} &&= $_->{link_ok};
                    $_->{valid_tx} = $_->{valid}
                        ? $_->{valid} == 1 ? 'ok' : 'skipped' : 'not ok';
                    $_->{valid_ok} = $_->{valid}
                        ? $_->{valid} == 1 ? 1 : 1 : 0;
                    $_->{link_ok} || $_->{status_sk}
                        and $pinfo->{kw_styles_cnt}++;
                } elsif ( exists $_->{ct} ) { # this is an image
                    $_->{status_sk} and $pinfo->{images_sk}++;
                    $pinfo->{all_images_ok} &&= $_->{link_ok};
                    $_->{link_ok} || $_->{status_sk}
                        and $pinfo->{kw_images_cnt}++;
                } else {
                    $_->{status_sk} and $pinfo->{links_sk}++;
                    $pinfo->{all_links_ok} &&= $_->{link_ok};
                    $_->{link_ok} || $_->{status_sk}
                        and $pinfo->{kw_links_cnt}++;
                }
            }

            $pinfo->{valid_tx} = $pinfo->{valid}
                ? $pinfo->{valid} == 1 ? 'ok' : 'skipped' : 'not ok';
            defined $pinfo->{valid} and $pinfo->{all_ok} &&= $pinfo->{valid};

            $pinfo->{link_cnt} and $pinfo->{link_status_ok} =
                $pinfo->{link_cnt} == $pinfo->{links_ok} + $pinfo->{links_sk}; 
            $pinfo->{link_status} = $pinfo->{link_cnt} 
                ? $pinfo->{link_cnt} == $pinfo->{links_ok} + $pinfo->{links_sk}
                    ? 'ok' : 'not ok' : 'N/A';
            $pinfo->{link_cnt} and 
                $pinfo->{all_ok} &&= $pinfo->{link_status_ok};
            $pinfo->{kw_links_cnt} ||= 0;
            $pinfo->{kw_links} = $pinfo->{link_cnt}
                ? sprintf "%.2f", $pinfo->{kw_links_cnt}/$pinfo->{link_cnt} : 1;
            $pinfo->{status_ok} or $pinfo->{kw_links} = 0;

            $pinfo->{kw_images_cnt} ||= 0;
            $pinfo->{kw_images_cnt} and $pinfo->{image_status_ok} =
                $pinfo->{kw_images_cnt} == $pinfo->{images_ok} +
                                       $pinfo->{images_sk}; 
            $pinfo->{image_status} = $pinfo->{image_cnt} 
                ? $pinfo->{image_cnt} == $pinfo->{images_ok} +
                                         $pinfo->{images_sk}
                    ? 'ok' : 'not ok' : 'N/A';
            $pinfo->{image_cnt} and 
                $pinfo->{all_ok} &&= $pinfo->{image_status_ok};
            $pinfo->{kw_images} = $pinfo->{image_cnt}
                ? sprintf "%.2f", $pinfo->{kw_images_cnt}/$pinfo->{image_cnt}
                : 1;

            $pinfo->{style_cnt} and $pinfo->{style_status_ok} =
                $pinfo->{style_cnt} == $pinfo->{styles_ok} +
                                       $pinfo->{styles_sk}; 
            $pinfo->{style_status} = $pinfo->{style_cnt} 
                ? $pinfo->{style_cnt} == $pinfo->{styles_ok} +
                                         $pinfo->{styles_sk}
                    ? 'ok' : 'not ok' : 'N/A';
            $pinfo->{style_cnt} and 
                $pinfo->{all_ok} &&= $pinfo->{style_status_ok};
            $pinfo->{kw_styles_cnt} ||= 0;
            $pinfo->{kw_styles} = $pinfo->{style_cnt}
                ? sprintf "%.2f", $pinfo->{kw_styles_cnt}/$pinfo->{style_cnt}
                : 1;

            $pinfo->{kw_return} = sprintf "%.2f", $pinfo->{status_ok} ? 1 : 0;
            $pinfo->{kw_title}  = sprintf "%.2f", $pinfo->{title}
                ? $pinfo->{status_ok} ? 1 : 0 : 0;
            $pinfo->{kw_valid}  = sprintf "%.2f", 
                                         $pinfo->{valid_tx} ne 'not ok' ? 1 : 0;
            my @metrics = qw( return title valid links images styles );
            $pinfo->{kw_total} = 0;
            for my $metric (@metrics) {
                $pinfo->{kw_total} += $pinfo->{ "kw_$metric" };
            }
            $pinfo->{kwalitee} = sprintf "%.2f", $pinfo->{kw_total}/@metrics;
            $data{kw_site} += $pinfo->{kwalitee};

            $pinfo->{all_ok} or $data{not_ok_cnt}++;
            $pinfo->{valid} and $data{valid_ok}++;
            $pinfo->{valid_tx} =~ /ok/ and $data{valid_cnt}++;
            push @{ $data{pages} }, $pinfo;
        }
    }

    $data{page_cnt}    = scalar @{ $data{pages} };
    $data{kwalitee}    = sprintf "%.2f", $data{kw_site}/$data{page_cnt};
    $data{copyright}   = '&copy; MMV Abe Timmerman &lt;abeltje@cpan.org&gt;';
    $data{wcs_version} = $VERSION;

    return \%data;
}

=begin private

=head2 name_outfile( $dir, $type )

Return the full name of the report file.

=end private

=cut

sub name_outfile {
    my( $dir, $type ) = @_;
    return catfile $dir, "${type}.html";
}

=begin private

=head2 find_tmpl( $name, $v )

Return the full name of the template file.

=end private

=cut

sub find_tmpl {
    my( $name, $v ) = @_;

    my $from_cur = $name;
    -f $from_cur and do {
        $v > 1 and print "Found: '$from_cur\n";
        return $from_cur;
    };
    $from_cur .= ".tmpl";
    -f $from_cur and do {
        $v > 1 and print "Found: '$from_cur\n";
        return $from_cur;
    };
    my $from_bin = rel2abs( $name, $FindBin::Bin );
    -f $from_bin and do {
        $v > 1 and print "Found: '$from_bin\n";
        return $from_bin;
    };
    $from_bin .= ".tmpl";
    -f $from_bin and do {
        $v > 1 and print "Found: '$from_bin\n";
        return $from_bin;
    };

    # Findout where the module is installed:
    ( my $lib = $INC{ 'WWW/CheckSite.pm' } ) =~ s|CheckSite.pm||;
    my $from_lib = rel2abs( $name, $lib );
    -f $from_lib and do {
        $v > 1 and print "Found: '$from_lib\n";
        return $from_lib;
    };
    $from_lib .= ".tmpl";
    -f $from_lib and do {
        $v > 1 and print "Found: '$from_lib\n";
        return $from_lib;
    };

    return $name;
}

=begin private

=head2 status_text( $hhtp_status )

Return the verbose status of a http status code. A selection of RFC
2616 sect. 10

=end private

=cut

sub status_text {
    local $_ = shift || 'unknown';
    SWITCH: {
        /^200$/ and return "ok";
        /^203$/ and return "non-authoritative information";
        /^204$/ and return "no content";
        /^304$/ and return "not modified";
        /^305$/ and return "use proxy";
        /^400$/ and return "bad request";
        /^401$/ and return "unauthorized";
        /^403$/ and return "forbidden";
        /^404$/ and return "not found";
        /^500$/ and return "internal server error";
        /^501$/ and return "not implemented";
        /^502$/ and return "bad gateway";
        /^503$/ and return "service unavailable";
        /^504$/ and return "gateway timeout";
        /^505$/ and return "http version not supported";
        /^999$/ and return "no robots allowed";
        return $_;
    }
}

=begin private

=head2 time_hhmm( $start_or_count[, $end] )

Return a difference specified in seconds in the format:

     H hour(s) MM minute(s) SS seconds

leaving the zero parts off the front.

=end private

=cut

sub time_hhmm {
    my( $start, $finish ) = @_;

    my $diff = defined $finish ?  abs( $finish - $start ) : $start;

    my $days = int( $diff / (24*60*60) );
    $diff -= 24*60*60 * $days;
    my $hours = int( $diff / (60*60) );
    $diff -= 60*60 * $hours;
    my $mins = int( $diff / 60 );
    $diff -=  60 * $mins;

    my @parts;
    push @parts, sprintf "$days day%s",    $days  > 1 ? 's' : '' if $days;
    push @parts, sprintf "$hours hour%s",  $hours > 1 ? 's' : '' if $hours;
    push @parts, sprintf "$mins minute%s", $mins  > 1 ? 's' : '' if $mins;
    push @parts, sprintf "%.3f seconds", $diff;

    return join " ", @parts;
}

=head1 AUTHOR

Abe Timmerman, C<< <abeltje@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-www-checksite@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.  I will be notified, and then you'll automatically
be notified of progress on your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright MMV Abe Timmerman, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut
