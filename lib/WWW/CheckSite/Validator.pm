package WWW::CheckSite::Validator;
use strict;
use warnings;

# $Id: Validator.pm 633 2007-04-30 21:08:56Z abeltje $
use vars qw( $VERSION $VALIDATOR_URL $VALIDATOR_FRM $VALIDATOR_STYLE $XMLLINT );
$VERSION = '0.017';

=head1 NAME

WWW::CheckSite::Validator - A spider that assesses 'kwalitee' for a site

=head1 SYNOPSIS

    use WWW::CheckSite::Validator;
    my $wcv = WWW::CheckSite::Validator->new(
        uri => 'http://www.test-smoke.org'
    );

    while ( my $info = $wcv->get_page ) {
        # handle the info
    }

=head1 DESCRIPTION

This is a subclass of C<WWW::CheckSite::Spider>.

C<WWW::CheckSite::Validator> starts its work after the spider has
fetched the page. It will check these things:

=over 4

=item * B<links>

All links on the page (C<< <a href> >>, C<< <area href> >>, C<< <frame
src> >>) are checked for availability.

=item * B<images>

All images on the page (C<< <img src> >>, C<< <input type=image> >>)
are checked for availability.

=item * B<stylesheets>

All stylesheets on the page (C<< <link rel=stylesheet type=text/css>
>>) are checked for availability.

=item * B<W3 HTML validation>

The contents of the page are send to L<http://validator.w3.org> for
validation.

=back

=head1 METHODS

=cut

use WWW::CheckSite::Spider qw( :const );
use base 'WWW::CheckSite::Spider';
BEGIN {
    $VALIDATOR_URL   = 'http://validator.w3.org/check?uri=%s';
    $VALIDATOR_FRM   = 'http://validator.w3.org/';
    $XMLLINT         = 'xmllint';
    $VALIDATOR_STYLE = 'http://jigsaw.w3.org/css-validator/';
}

=head2 WWW::CheckSite::Validator->new( %args )

Extend C<< WWW::CheckSite::Spider->new >> to check for L<Image::Info>
so we can do a basic check on the images.

=cut

sub new {
    my $class = shift;
    my $self = $class->SUPER::new( @_ );

    $self->{validate} ||= 'by_none';
    $self->{novalidate} = $self->{validate} eq 'by_none';

    eval qq{use Image::Info qw( image_info )};
    $self->{can_val_image} = ! $@;
    return $self;
}

=head2 $wcs->process_page

This method overrides the C<WWW::CheckSite::Spider::process_page()>
method to check on the availability of B<links>, B<images> and
B<stylesheets>. When specified it will also send the page for
validation by B<W3.ORG>.

On top of the standard information it returns more:

=over 4

=item * B<links> a list of links on the page, with some extra info

=item * B<links_cnt> the number of links on the page

=item * B<links_ok> the number of links that returned STATUS==200

=item * B<images> a list of images on the page, with some extra info

=item * B<images_cnt> the number of images on the page

=item * B<images_ok> the number of images that returned STATUS==200

=item * B<styles> a list of stylesheets on the page, with some extra info

=item * B<styles_cnt> the number of stylesheets on the page

=item * B<styles_ok> the number of stylesheets that returned STATUS==200

=item * B<valid> the result of validation at W3.ORG

=back

=cut

sub process_page {
    my $self = shift;

    my $stats = $self->SUPER::process_page( @_ );

    $self->check_links(  $stats );
    $self->check_images( $stats );
    $self->check_styles( $stats );
    $self->validate(     $stats );

    return $stats;
}

=head2 $wcs->check_links( $stats )

The C<check_links()> method gets information about the links on this
page.  If there is no return status, it will C<HEAD> the uri and
update the cache status for this link to prevent multiple HEADing.

B<NOTE>: This method does B<not> respect the exclusion rules, and only
robot-rules with C<strictrules> enabled!

The structure for links:

=over 4

=item * B<link> as set in the C<< a/area >> tag

=item * B<uri> as returned after the HEAD request

=item * B<tag> set to 'A' or 'AREA'

=item * B<text> set to the text in the link

=item * B<status> the return status from the HEAD request

=item * B<depth> the depth in the "browse-tree"

=item * B<action> explanation of the action taken on this uri

=back

=cut

sub check_links {
    my( $self, $stats ) = @_;
    my( $stack, $cache, $mech ) = @{ $self }{qw( _stack _cache _agent )};

    my @links = $mech->success ? $self->links_filtered : ();

    my @checked;
    for my $link ( @links ) {
        my $check = URI->new_abs( $link->url, $mech->uri );
        $self->more_rrules( $check );
        my $in_cache = $cache->has( $check );
        unless ( $in_cache && defined $in_cache->[1] ) {
            $self->more_rrules( $check );
            if ( ! $self->allowed( $check ) ) {
                $in_cache->[1] = '999';
                $self->{v} and print "  HEAD '$check': skipped.\n";
            } else {
                $self->{v} and print "  HEAD '$check': ";
                my $ua = $self->new_agent;
                eval { $ua->head( $check ) };
                $in_cache->[1] = $ua->status;
                $self->{v} and
                    printf "done(%sok).\n", $ua->success ? '' : 'not ';

                $ua->success && ! $self->ct_can_validate( $ua ) and
                    $in_cache->[0] = WCS_NOCONTENT;
            }
	}

        push @checked, {
            link   => $link->url,
            uri    => $check->as_string,
            tag    => $link->tag,
            text   => $link->text || ">No text in TAG<",
            status => $in_cache->[1],
            depth  => $in_cache->[2],
            action => $self->set_action( $check, $in_cache ),
        };
    }
    $stats->{link_cnt} = @links;
    $stats->{links} = \@checked;
    $stats->{links_ok} = grep $_->{status} == 200 => @checked;

    return $stats;
}

=head2 $wcs->check_images( $stats )

The C<check_images()> method gets information about the images on the
page. The list comes from the I<images()> method of the mechanize
object. It will only C<HEAD> the uri.

The structure for images:

=over 4

=item * B<link> as set in the C<< img/input >> tag

=item * B<uri> as returned after the HEAD request

=item * B<tag> set to 'ALT'

=item * B<text> set to the text of the ALT attribute

=item * B<status> the return status from the HEAD request

=item * B<ct> the 'Content-Type' returned by the HEAD request

=back

=cut

sub check_images {
    my( $self, $stats ) = @_;
    my( $stack, $cache, $mech ) = @{ $self }{qw( _stack _cache _agent )};

    my @images = $mech->success ? $mech->images : ();;

    my @checked;
    for my $img ( @images ) {
        my $check = URI->new_abs( $img->url, $mech->base );
        $self->more_rrules( $check );
        my $in_cache = $cache->has( $check );
        defined $in_cache or
            $in_cache = $cache->set( $check => [ WCS_FOLLOWED ] );
        unless ( $in_cache && defined $in_cache->[1] ) {
            $self->more_rrules( $check );
            if ( ! $self->allowed( $check ) ) {
                $in_cache->[1] = '999';
            } else {
                my $ua = $self->new_agent;
                my $method = $self->{can_val_image} ? 'get' : 'head';
                $self->{v} and print "  \U$method\E '$check': ";
                eval { $ua->$method( $check ) };
                my $success = $ua->success;

                $in_cache->[1] = $ua->status;
                $in_cache->[2] = $ua->ct;
                my $valid;
                if ( $method eq 'head' ) {
                    $valid = $success ? -1 : 0;
                } else { # it's GET
                    $valid = $success ? $self->validate_image( $ua ) : 0;
		}
                $in_cache->[3] = $valid;
                $self->{v} and
                    printf "done(%sok).\n", $ua->success ? '' : 'not ';
            }
	}

        push @checked, {
            link   => $img->url,
            uri    => $check->as_string,
            tag    => 'ALT',
            text   => ( defined( $img->alt )
                ? ($img->alt || "")
                : $self->{novalidate} ? "" : ">No text in TAG<" ),
            status => $in_cache->[1],
            ct     => $in_cache->[2],
            valid  => $in_cache->[3],
        };
    }
    $stats->{image_cnt} = @images;
    $stats->{images} = \@checked;
    $stats->{images_ok} = grep $_->{status} == 200 && $_->{valid} => @checked;

    return $stats;
}

=head2 $wcs->check_styles( $stats )

The C<check_styles()> method checks the validity of stylesheets used in the
page. We check for C<< <link rel="stylesheet" type="text/css"> >> tags.

The structure for stylesheets:

=over 4

=item * B<link> as set in the link tag

=item * B<uri> as returned after the HEAD request

=item * B<tag> set to 'link'

=item * B<text> set to empty for compatibility with I<links> and I<images>

=item * B<status> the return status from the HEAD request

=item * B<ct> the 'Content-Type' returned by the HEAD request

=back

=cut

sub check_styles {
    my( $self, $stats ) = @_;
    my( $stack, $cache, $mech ) = @{ $self }{qw( _stack _cache _agent )};

    my $content = \( $mech->content );
    my $p = HTML::TokeParser->new( $content );
    my @styles;
    while ( my $token = $p->get_tag( 'link' ) ) {
        ( exists $token->[1]{rel}  && $token->[1]{rel}  eq 'stylesheet' ) &&
        ( exists $token->[1]{type} && $token->[1]{type} eq 'text/css' ) or next;
	push @styles, $token->[1]{href};
    }

    my @checked;
    for my $sheet ( @styles ) {
        my $check = URI->new_abs( $sheet, $mech->uri );
        $self->more_rrules( $check );
        my $in_cache = $self->{_cache}->has( $check );

        defined $in_cache or
            $in_cache = $cache->set( $check => [ WCS_FOLLOWED ] );
        unless ( $in_cache && defined $in_cache->[1] ) {
            $self->more_rrules( $check );
            if ( ! $self->allowed( $check ) ) {
                $in_cache->[1] = '999';
                $in_cache->[3] = -1;
            } else {
                my $ua = $self->new_agent;
                my $method = $self->{validate} =~ /by_(?:upload|uri)/
                    ? 'get' : 'head';
                $self->{v} and print "  \U$method\E '$check': ";
                eval { $ua->$method( $check ) };
                my $success = $ua->success;
                $self->{v} and
                    printf "done(%sok).\n", $success ? '' : 'not ';
                $in_cache->[1] = $ua->status;
                $in_cache->[2] = $ua->ct;
                $in_cache->[3] = $method eq 'get' && $success
                                     ? $self->validate_style( $ua ) : -1;
            }
	}

        push @checked, {
            link   => $sheet,
            uri    => $check->as_string,
            tag    => 'link',
            text   => '',
            status => $in_cache->[1],
            ct     => $in_cache->[2],
            valid  => $in_cache->[3],
        };
    }
    $stats->{style_cnt} = @styles;
    $stats->{styles} = \@checked;
    $stats->{styles_ok}  = grep +($_->{status} == 200)  => @checked;
    $stats->{vstyles_ok} = grep
        defined( $_->{valid} ) ? ($_->{valid} == 1) ? 1 : 0 : 1 => @checked;

    return $stats;
}

=head2 $wcs->validate

The C<validate()> method sends the url/contents off to W3.org to validate.

=cut

sub validate {
    my( $self, $stats ) = @_;

    unless ( $self->current_agent->success ) {
        $self->{v} and
            print "Validate @{[$self->current_agent->uri]}: skipped\n";
        $stats->{valid} = 0;
        return $stats;
    }

    my $how_to = $self->{validate} || 'by_none';
    my $validate = "validate_$how_to";
    $self->can( $validate ) or $validate = 'validate_by_none';

    $self->$validate( $stats );
}

=head2 $wcs->validate_by_none

The fallback do-not-validate method.

=cut

sub validate_by_none {
    my( $self, $stats ) = @_;
    $stats->{valid} = -1;
}

=head2 $wcs->validate_by_uri

Sends only the uri to W3.ORG and get the validation result.

=cut

sub validate_by_uri {
    my( $self, $stats ) = @_;

    my $val_uri = sprintf $VALIDATOR_URL, $self->current_agent->uri;
    $self->{v} and print "HTML-Validate $val_uri: ";

    my $ua = $self->new_agent;
    $self->{lang} and $ua->default_header( 'Accept-Language' => 'en' );
    $ua->get( $val_uri );

    $stats->{valid} = $ua->success
        ? $ua->content =~ /This Page Is Valid/ : '-1';
    $self->{v} and printf "done(%sok)\n", $stats->{valid} == 1 ? "" : "not ";

    $self->{lang} and $ua->default_header( 'Accept-Language' => $self->{lang} );
}

=head2 $wcs->validate_by_upload( $stats )

Create a temporary file (with L<File::Temp>) from C<< $agent->content >>,
call the validator with that temporary file and save the result (as a
boolean) in C<< $stats->{validate} >>.

=cut

sub validate_by_upload {
    my( $self, $stats ) = @_;

    eval "use File::Temp";
    $@ and $stats->{valid} = 1, return;

    my( $mech ) = @{ $self }{qw( _agent )};
    File::Temp->import( 'tempfile' );
    my( $fh, $filename ) = tempfile( 'wcvtempXXXX', SUFFIX => '.html', 
                                                    UNLINK => 1 );
    print $fh $mech->content;
    close $fh;

    $self->{v} and printf "HTML-Validate_upl(%s): %s ", $filename, $mech->uri;
    $stats->{validate} = $filename;

    my $ua = $self->new_agent;
    $self->{lang} and $ua->default_header( 'Accept-Language' => 'en' );
    $ua->get( $VALIDATOR_FRM );
    $ua->submit_form( 
        form_number => 2,
        fields      => { uploaded_file => $filename },
    );

    $stats->{valid} = $ua->success 
        ? $ua->content =~ /This Page Is Valid/ : -1;
    $self->{v} and printf " done(%sok)\n", $stats->{valid} == 1 ? "" : "not ";

    $self->{lang} and $ua->default_header( 'Accept-Language' => $self->{lang} );
}

=head2 $wcs->validate_by_xmllint( $stats )

Use the L<xmllint(1)> program to validate the (X)HTML.

=cut

sub validate_by_xmllint {
    my( $self, $stats ) = @_;
    my $opts = qq[--postvalid --recover --stream];

    eval "use File::Temp";
    $@ and $stats->{valid} = 1, return;

    my( $ua ) = @{ $self }{qw( _agent )};
    File::Temp->import( 'tempfile' );
    my( $fh, $filename ) = tempfile( 'wcvtempXXXX', SUFFIX => '.html', 
                                                    UNLINK => 1 );
    print $fh $ua->content;
    close $fh;

    $self->{v} and print "[$XMLLINT $opts $filename 2>\&1]\n";
    $self->{v} and printf "xmllint(%s): %s ", $filename, $ua->uri;
    $stats->{validate} = $filename;

    my $out = qx[$XMLLINT $opts $filename 2>\&1];
    $self->{v} and print $out;
    $stats->{valid} = defined $out
        ? $out eq '' : -1;
    $self->{v} and printf " done(%sok)\n", $stats->{valid} == 1 ? "" : "not ";
}

=head2 $wcs->validate_style( $ua )

Dispatch the validation to the right method.

=cut

sub validate_style {
    my( $self, $ua ) = @_;

    $self->{novalidate} and return -1;

    my $how_to = $self->{validate} || 'by_none';
    my $validate = "style_$how_to";
    $self->can( $validate ) or $validate = 'style_by_none';

    $self->$validate( $ua );
}

=head2 $wcs->style_by_none

The fallback do-not-validate-stylesheet method.

=cut

sub style_by_none {
    return -1;
}

=head2 $wcs->style_by_uri( $ua )

Sends only the uri to JIGSAW.W3.ORG and get the validation result.

=cut

sub style_by_uri {
    my( $self, $ua ) = @_;

    my $uri = $ua->uri;
    $self->{v} and print "CSS-Validate $VALIDATOR_STYLE?$uri: ";
    $self->{lang} and $ua->default_header( 'Accept-Language' => 'en' );
    $ua->get( $VALIDATOR_STYLE );
    $ua->submit_form(
        form_number => 1,
        fields      => { uri => $uri },
    );

    my $valid = $ua->success
        ? $ua->content =~ /This document validates as / : -1;

    $self->{v} and printf "done(%sok)\n", $valid == 1 ? "" : "not ";

    $self->{lang} and $ua->default_header( 'Accept-Language' => $self->{lang} );

    return $valid;
}

=head2 $wcs->style_by_upload( $ua )

Create a temporary file (with L<File::Temp>) from C<< $ua->content >>,
call the validator with that temporary file and return the result.

=cut

sub style_by_upload {
    my( $self, $ua ) = @_;

    eval "use File::Temp";
    return if $@;

    File::Temp->import( 'tempfile' );
    my( $fh, $filename ) = tempfile( 'wcvtempXXXX', SUFFIX => '.css', 
                                                    UNLINK => 1 );
    print $fh $ua->content;
    close $fh;

    $self->{v} and printf "CSS-Validate_upl(%s): %s ", $filename, $ua->uri;

    $self->{lang} and $ua->default_header( 'Accept-Language' => 'en' );
    $ua->get( $VALIDATOR_STYLE );
    $ua->submit_form( 
        form_number => 2,
        fields      => { file => $filename },
    );

    my $valid = $ua->success 
        ? $ua->content !~ m|<h2>Errors</h2>|i : -1;
    $self->{v} and printf " done(%sok)\n", $valid == 1 ? "" : "not ";

    $self->{lang} and $ua->default_header( 'Accept-Language' => $self->{lang} );

    return $valid;
}

=head2 $wcs->validate_image( $ua )

This is more like a basic consistency check, that uses C<<
Image::Info::image_info() >>.

=cut

sub validate_image {
    my( $self, $ua ) = @_;
    my $image = $ua->content;
    my $iinfo = Image::Info::image_info( \$image );
    return ! $iinfo->{error};
}

=head2 $wcs->ct_can_validate( $ua )

Check if the content-type is "validatable".

=cut

sub ct_can_validate {
    my( $self, $ua ) = @_;

    return $ua->ct =~ m[^\Qtext/html\E]                     ||
           $ua->ct =~ m[^\Qtext/xhtml\E]                    ||
           $ua->ct =~ m[^\Qapplication/xhtml+xml\E]         ||
           $ua->ct =~ m[^\Qapplication/vnd.wap.xhtml+xml\E];
}

=head2 $wcs->set_action

Why?

=cut

sub set_action {
    my( $self, $check, $in_cache ) = @_;
    
    my $reason = ($in_cache->[0] & WCS_OUTSCOPE)  ? $self->{_uri_ok} eq 'scope'
        ? 'Out of scope' : 'Excluded by pattern' : '';
    $reason  ||= ($in_cache->[0] & WCS_SPIDERED)  ? 'done' : '';
    $reason  ||= ($in_cache->[0] & WCS_NOCONTENT) ? 'no text/html' : '';

    return $reason ? "[c] Skip: ($reason)" : "[c] Spider: $check";
}

=head1 SEE ALSO

L<WWW::CheckSite::Spider>, L<WWW::CheckSite>

=head1 AUTHOR

Abe Timmerman, C<< <abeltje@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-WWW-CheckSite@rt.cpan.org>, or through the web interface at
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
