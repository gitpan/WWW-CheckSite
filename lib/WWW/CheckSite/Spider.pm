package WWW::CheckSite::Spider;
use strict;
use warnings;

# $Id: Spider.pm 671 2007-05-28 18:52:35Z abeltje $
use vars qw( $VERSION @EXPORT_OK %EXPORT_TAGS );
$VERSION = '0.023';

=head1 NAME

WWW::CheckSite::Spider - A base class for spidering the web

=head1 SYNOPSIS

    use WWW::CheckSite::Spider;

    my $sp = WWW::CheckSite::Spider->new(
         uri      => 'http://www.test-smoke.org',
    );

    while ( my $page = $sp->get_page ) {
        # $page is a hashref with basic information
    }

or to spider a site behind HTTP basic authentication:

    package BA_Mech;
    use base 'WWW::Mechanize';

    sub get_basic_credentials { ( 'abeltje', '********' ) }

    package main;
    use WWW::CheckSite::Spider;

    my $sp = WWW::CheckSite::Spider->new(
         ua_class => 'BA_Mech',
         uri      => 'http://your.site.with.ba/',
    );

    while ( my $page = $sp->get_page ) {
        # $page is a hashref with basic information
    }


=head1 DESCRIPTION

This module implements a basic web-spider, based on
C<WWW::Mechanize>. It takes care of putting pages on the
"still-to-fetch" stack. Only uri's with the same origin will be
stacked, taking the robots-rules on the server into account.

=cut

use WWW::CheckSite::Util;
use WWW::RobotRules;
use URI;

=head1 CONSTATNTS & EXPORTS

The following constants ar exported on demand with the B<:const> tag.

=over 4

=item B<WCS_UNKNOWN>

=item B<WCS_FOLLOWED>

=item B<WCS_SPIDERED>

=item B<WCS_TOSPIDER>

=item B<WCS_TOFOLLOW>

=item B<WCS_NOCONTENT>

=item B<WCS_OUTSCOPE>

=back

=cut

sub WCS_UNKNOWN()   {   0 }
sub WCS_FOLLOWED()  {   1 }
sub WCS_SPIDERED()  {   2 }
sub WCS_TOSPIDER()  {   4 }
sub WCS_TOFOLLOW()  {   8 }
sub WCS_NOCONTENT() {  64 }
sub WCS_OUTSCOPE()  { 128 }

use base 'Exporter';
%EXPORT_TAGS = (
    const => [qw( WCS_UNKNOWN  WCS_FOLLOWED  WCS_SPIDERED WCS_TOSPIDER
                  WCS_TOFOLLOW WCS_NOCONTENT WCS_OUTSCOPE )],
);
@EXPORT_OK = map @{ $EXPORT_TAGS{ $_ } } => keys %EXPORT_TAGS;

=head1 METHODS

=head2 WWW::CheckSite::Spider->new( %opts )

Currently supported options (the rest will be set but not used!):

=over 4

=item * B<uri> => <start_uri> || <\@start_uri> [mandatory]

=item * B<ua_class> => by default L<WWW::Mechanize>

=item * B<exclude> => <exclude_re> (qr/[#?].*$/)

=item * B<myrules> => <\@disallow>

=item * B<lang> => languages to pass to I<Accept-Language:> header

=begin undocumented

=item * B<_self_base> => <my_base_to_use>

=item * B<_norules> => perl_false 

=end undocumented

=back

=cut

sub new {
    my $class = shift;
    my %opts = @_ ? ref $_[0] ? %{ $_[0] } : @_ : ();

    $opts{uri} or do {
        require Carp;
        Carp::croak( "No uri to spider specified!" );
    };
    ref $opts{uri} or $opts{uri} = [ $opts{uri} ];

    $opts{_self_base} ||= $opts{uri}->[0];
    $opts{_self_base} =~ s|^(.+/)(.+\.s?html?)|$1|;
    $opts{_self_base} = URI->new( $opts{_self_base} )->canonical->as_string;

    $opts{uri_base} = [ map {
        ( my $base = $_ ) =~ s|^(.+/)(.+\.s?html?)|$1|;
        URI->new( $base )->canonical->as_string;
    } @{ $opts{uri} } ];
    $opts{uri} = [map URI->new( $_ )->canonical->as_string => @{ $opts{uri} }];

    defined $opts{exclude} or $opts{exclude} = '[#?].*$';
    defined $opts{myrules} or $opts{myrules} = [ ];
    $opts{_norules} = ! ( @{ $opts{myrules} } || $opts{strictrules} );

    $opts{_stack} = new_stack();
    $opts{_cache} = new_cache();

    $opts{ua_args} ||= { };

    my $self = bless \%opts, $class;
    $self->init_agent;
    $self->init_robotrules;
    for ( my $i = $#{ $self->{uri} }; $i >= 0; $i-- ) {
        my $uri  = $self->{uri}[ $i ];
        my $base = $self->{uri_base}[ $i ];
        if ( $self->uri_ok( $uri ) ) {
            $self->{_stack}->push( [ $uri, $base ] );
            $self->{_cache}->set( $uri => [ WCS_TOSPIDER, undef, 1 ] );
        }
    }

    return $self;
}

=head2 $spider->get_page

Fetch the page and do some book keeping. It returns the result of
C<< $pider->process_page() >>.

=cut

sub get_page {
    my $self = shift;

    my( $stack, $cache ) = @{ $self }{qw( _stack _cache )};
    return unless $stack->size; # End of iteration

    my $in_cache;
    my $item = $stack->pop;
    my $uri;
    if ( ref $item ) {
        $uri = $item->[0];
        $self->{_self_base} = $item->[1];
    } else {
        $uri = $item;
    }

    $uri and $in_cache = $cache->has( $uri );
    while ( defined $uri && $in_cache && !($in_cache->[0] & WCS_TOSPIDER) ) {
        $uri = $stack->pop;
        $uri and $in_cache = $cache->has( $uri );
    }
    return unless defined $uri; # End of iteration

    $self->_process( $uri );
}

=begin private

=head2 $self->_process( $uri )

Private method to help not requesting pages more than once.

=end private

=cut

sub _process {
    my $self = shift;
    my $uri  = shift;

    my $mech = $self->current_agent;
    $self->{v} and print "Fetch: '$uri': ";
    $mech->get( $uri );
    $self->{v} and printf "done(%sok).\n", $mech->success ? '' : 'not ';
    $self->{_self_base} ||= $mech->base;

    $self->_update_stack( $uri );

    $self->process_page( $uri );
}

=begin private

=head2 $self->_update_stack( $base )

This is what the spider is all about. It will examine
C<< $self->current_agent->links() >> to filter the links to follow.

=end private

=cut

sub _update_stack {
    my( $self, $base ) = @_;

    my( $stack, $cache, $mech ) = @{ $self }{qw( _stack _cache _agent )};

    my $this_page = $cache->has( $base );
    @{ $this_page }[0, 1] = ( WCS_SPIDERED, $mech->status );

    return unless $mech->success;

    my @candidates = $self->links_filtered;

    my $new_base = $mech->uri;

    $new_base->canonical ne URI->new( $base )->canonical
        and $cache->set( $new_base => $this_page );

    foreach my $link ( @candidates ) {
        my $new   = URI->new_abs( $link->url, $new_base )->as_string;
        my $check = $self->strip_uri( $new );
        my $data;
        if ( $data = $cache->has( $check ) ) {
            my $frag;
            if ( $new ne $check && ! ($frag = $cache->has( $new )) ) {
                $frag = [ WCS_TOFOLLOW, undef, $this_page->[2] + 1 ];
                $cache->set( $new => $frag );
            }
        } else {
            if ( $self->uri_ok( $new ) ) {
                $stack->push( $check );
                $data = [ WCS_TOSPIDER, undef, $this_page->[2] + 1 ];
	    } else {
                $data = [ WCS_OUTSCOPE, 999, $this_page->[2] + 1 ];
                $cache->set( $new => $data );
                $self->uri_ok( $check ) and 
                    $data = [ WCS_TOFOLLOW, undef, $this_page->[2] + 1 ];
            }
            $cache->set( $check => $data );
        }
    }
}

=head2 $spider->process_page( $uri )

Override this method to make the spider do something useful. By
default it returns:

=over 4

=item * B<org_uri> Used for the request

=item * B<ret_uri> The uri returned by the server

=item * B<depth> The depth in the browse tree

=item * B<status> The return status from server

=item * B<success> shortcut for status == 200

=item * B<is_html> shortcut for ct eq 'text/html'

=item * B<title> What's in the <TITLE></TITLE> section

=item * B<ct> The content-type

=back

=cut

sub process_page {
    my( $self, $uri ) = @_;

    my $mech = $self->current_agent;

    my $use_uri = $mech->success ? $mech->uri : $uri;
    my $in_cache = $self->{_cache}->has( $use_uri );

    my $stats = {
        org_uri => $uri,
        ret_uri => ($use_uri || $uri),
        depth   => $in_cache->[2],
        status  => $mech->status,
        success => $mech->success,
        is_html => $mech->is_html,
        title   => $mech->success ? $mech->is_html
            ? $mech->title || "No title: $use_uri" : $use_uri
            : "Failed: $use_uri",
        ct      => $mech->success ? $mech->ct : "Unknown",
    };

    return $stats;
}

=head2 $spider->links_filtered

Filter out the uri's that will fail:

    qr!^(?:mailto:|mms://|javascript:)!i

=cut

sub links_filtered {
    my $self = shift;
    return grep {
        my $url = $self->filter_link( $_->url );
        ! defined $url
            ? undef
            : ( ($url eq $_->url and $_->url( $url )), $_ )
    } $self->current_agent->links;
}

=head2 $spider->filter_link( $uri )

Return the URI to be spidered or C<undef> for skipping.

=cut

sub filter_link {
    my( $self, $uri ) = @_;
    my $check = URI->new( $uri );
    defined $check->scheme or return $uri;
    return $check->scheme =~ /^(:?https|http|ftp|file)$/
        ? $uri
        : undef;
}

=head2 $spider->strip_uri( $uri )

Strip the fragment bit of the I<$uri>.

=cut

sub strip_uri {
    my $self = shift;

    my $nu = URI->new( @_ );
    defined $nu->fragment and $nu->fragment( undef );
    return $nu->as_string
}

=head1 USERAGENT METHODS

=head2 $spider->agent

Retruns a standard name for this UserAgent.

=cut

sub agent { return (ref(shift) || __PACKAGE__) . "/$VERSION" }

=head2 $spider->init_agent

Initialise the agent that is used to fetch pages. The default class is
C<WWW::Mechanize> but any class that has the same methods will do.

The C<ua_class> needs to support the following methods (see
L<WWW::Mechanize> for more information about these):

=over 4

=item I<new>

=item I<get>

=item I<base>

=item I<uri>

=item I<status>

=item I<success>

=item I<ct>

=item I<is_html>

=item I<title>

=item I<links>

=item I<HEAD> (for L<WWW::CheckSite::Validator>)

=item I<content> (for L<WWW::CheckSite::Validator>)

=item I<images> (for L<WWW::CheckSite::Validator>)

=back

=cut

sub init_agent {
    my $self = shift;
    $self->{_agent} = $self->new_agent;
}

=head2 $spider->current_agent

Return the current user agent.

=cut

sub current_agent { $_[0]->{_agent} }

=head2 $spider->new_agent

Create a new agent and return it.

=cut

sub new_agent {
    my $self = shift;
    $self->{ua_class} ||= 'WWW::Mechanize';

    # If the package we're using has been declared inline, we don't
    # don't want to try and use it...
    # 20050421: by Pete Sergeant
    unless ( exists $::{ $self->{ua_class} . '::' } ) { 
        eval qq{ use $self->{ua_class} };
    }
    $@ and do {
        require Carp;
        Carp::croak( "Cannot initialise a UserAgent:\n$@" );
    };

    my $ua = $self->{ua_class}->new(
        agent => $self->agent,
        %{ $self->{ua_args} }
    );
    $self->{lang} and
        $ua->default_header( 'Accept-Language' => $self->{lang} );

    return $ua;
}

=head1 ROBOTRULES METHODS

The Spider uses the robot rules mechanism. This means that it will
always get the F</robots.txt> file from the root of the webserver to
see if we are allowed (actually "not disallowed") to access pages as a
robot.

You can add rules for disallowing pages by specifying a list of lines
in the F<robots.txt> syntax to C<< @{ $self->{myrules} } >>.

=head2 $spider->more_rrules( $url )

Check to see if the F<robots.txt> file for this C<$url> has already
been loaded. If not, fetch the file and add the rules to the C<<
$self->{_r_rules} >> object.

=cut

sub more_rrules {
    my( $self, $url ) = @_;

    my $rr_url = URI->new_abs( '/robots.txt', $url );

    my $in_cache = $self->{_cache}->has( $rr_url );
    unless ( $in_cache ) {
        my $ua = $self->new_agent;
        $self->{v} and print "Robot rules: $rr_url: ";
        $ua->get( $rr_url );
        $ua->success and $self->{_r_rules}->parse( $rr_url, $ua->content );
        $self->{v} and printf "done(%sok).\n", $ua->success ? '' : 'not ';
        $self->{v} && $ua->success
            and printf "Setting rules:\n%s\n", $ua->content;
        $self->{_cache}->set( $rr_url => [ WCS_SPIDERED, $ua->status, 0 ] );
    }
}

=head2 $spider->uri_ok( $uri )

This will determine whether this uri should be spidered. Rules are simple:

=over 8

=item *
Has the same base uri as the one we started with

=item *
Is not excluded by the C<< $self->{exclude} >> regex.

=item *
Is not excluded by F<robots.txt> mechanism

=back

=cut

sub uri_ok {
    my( $self, $uri ) = @_;

    my $check_uri = URI->new( $uri );
    $self->{_uri_ok} = '';
    $self->{v} and print "  Check '$uri'";
    $self->{_uri_ok} = 'scope'    unless $uri =~ m/^$self->{_self_base}/;
    $self->{_uri_ok} = 'pattern'  if     $uri =~ m/$self->{exclude}/;

    $self->{_uri_ok} = 'robots'   unless $self->{_norules} ||
                                         $self->allowed( $uri );

    $self->{v} and
        printf " done (%s).\n", $self->{_uri_ok} ? $self->{_uri_ok} : 'ok';
    return !$self->{_uri_ok};
}

=head2 $spider->allowed( $uri )

Checks the uri against the robotrules.

=cut

sub allowed {
    my( $self, $uri ) = @_;
    return $self->current_rrules->allowed( $uri );
}

=head2 $spider->init_robotrules( )

This will setup a <WWW::RobotRules> object. C<< @{$self->{myrules } >>
is used to add rules and should be in the RobotRules format. These
rules are B<added> to the ones found in F<robots.txt>.

=cut

sub init_robotrules {
    my $self = shift;

    my $agent = $self->agent;
    my $rules = WWW::RobotRules->new( $agent );

    # The $base_url should be set!
    my $robots_uri = eval {
        (URI->new_abs( '/robots.txt', $self->{_self_base} ))->as_string
    };
    $@ and do {
        require Carp;
        Carp::croak( "Error in base-url: $@" );
    };

    my $robots_txt = "";
    if ( $self->{strictrules} ) {
        $self->{v} and print "Robot rules: '$robots_uri': ";
        my $rua = $self->new_agent;
        $rua->get( $robots_uri );
        $self->{v} and printf "done(%sok).\n", $rua->success ? '' : 'not ';
        $self->{_cache}->set( $robots_uri, [ WCS_SPIDERED, $rua->status, 0 ] );
        $robots_txt = $rua->success ? $rua->content : "";
    } else {
        $self->{_cache}->set( $robots_uri, [ WCS_SPIDERED, 999, 0 ] );
    }

    $robots_txt ||= @{ $self->{myrules} }
        ? "User-Agent: *\n"
        : "User-Agent: *\nDisallow:\n";

    foreach my $myrule ( @{ $self->{myrules} } ) {
        $robots_txt .= "Disallow: $myrule\n";
        $self->{v} and print "myrule: Disallow: $myrule\n";
    }

    $robots_txt .= "Disallow:\n" if ( $robots_txt =~ tr/\n// ) == 1;
    $self->{v} and print "Setting rules:\n$robots_txt\n";

    $rules->parse( $robots_uri, $robots_txt )
        if $self->{uri}[0] =~ m|^https?://|; # problem with file:// uris

    $self->{_r_rules} =  $rules;
}

=head2 $spider->current_rrules

Returns the current RobotRules object.

=cut

sub current_rrules { $_[0]->{_r_rules} }

1;

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
