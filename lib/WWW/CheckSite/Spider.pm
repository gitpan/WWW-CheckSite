package WWW::CheckSite::Spider;
use strict;
use warnings;

# $Id: Spider.pm 284 2005-04-02 11:12:40Z abeltje $
use vars qw( $VERSION @EXPORT_OK %EXPORT_TAGS );
$VERSION = '0.006';

=head1 NAME

WWW::CheckSite::Spider - Implement a base class for spidering

=head1 SYNOPSIS

    use WWW::CheckSite::Spider;

    my $sp = WWW::CheckSite::Spider->new(
        ua_class => 'WWW::Mechanize', # or Win32:IE::Mechanize
        uri      => 'http://www.test-smoke.org',
    );

    while ( my $page = $sp->get_page ) {
        # $page is a hashref with bais information
    }

=head1 DESCRIPTION

This module implements a basic web-spider, based on
C<WWW::Mechanize>. It takes care of putting pages on the
"still-to-fetch" stack. Only uri's with the same origin will be
stacked, taking the robots-rules on the server into account.

=head1 METHODS

=cut

use WWW::CheckSite::Util;
use WWW::RobotRules;
use URI;

# Define some constants for the cache mechanism
=head1 CONSTATNTS & EXPORTS

The following constants ar exported on demand with the B<:const> tag.

=over 4

=item B<WCS_UNKNOWN>

=item B<WCS_FOLLOWED>

=item B<WCS_SPIDERED>

=item B<WCS_TOSPIDER>

=item B<WCS_NOCONTENT>

=item B<WCS_OUTSCOPE>

=back

=cut

sub WCS_UNKNOWN()   {   0 }
sub WCS_FOLLOWED()  {   1 }
sub WCS_SPIDERED()  {   2 }
sub WCS_TOSPIDER()  {   4 }
sub WCS_NOCONTENT() {  64 }
sub WCS_OUTSCOPE()  { 128 }

%EXPORT_TAGS = (
    const => [qw( WCS_UNKNOWN  WCS_FOLLOWED  WCS_SPIDERED
                  WCS_TOSPIDER WCS_NOCONTENT WCS_OUTSCOPE )],
);
@EXPORT_OK = map @{ $EXPORT_TAGS{ $_ } } => keys %EXPORT_TAGS;
use base 'Exporter';

=head2 WWW::CheckSite::Spider->new( %opts )

Currently supported options (the rest will be passed!):

=over 4

=item * B<uri> => <start_uri> [mandatory]

=item * B<au_class> => 'WWW::Mechanize' or 'Win32::IE::Mechanize'

=item * B<exclude> => <exclude_re> (qr/[#?].*$/)

=item * B<myrules> => <\@disallow>

=item * B<lang> => languages to pass to I<Accept-Language:> header

=begin undocumented

=item * B<_self_base> => <my_base_to_use>

=item * B<_norules> => true false

=end undocumented

=back

=cut

sub new {
    my $class = shift;
    my %opts = @_ ? ref $_[0] ? %{ $_[0] } : @_ : ();

    $opts{uri} or do {
        require Carp;
        Carp::croak( "No uri to spider specified!\n" );
    };

    $opts{_self_base} ||= $opts{uri};
    $opts{_self_base} =~ s|^(.+/)(.+\.s?html?)|$1|;

    defined $opts{exclude} or $opts{exclude} = '[#?].*$';
    defined $opts{myrules} or $opts{myrules} = [ ];
    $opts{strictrules} and $opts{_norules} = 0;

    $opts{_stack} = new_stack();
    $opts{_cache} = new_cache();

    $opts{ua_args} ||= { };

    my $self = bless \%opts, $class;
    $self->init_agent;
    $self->init_robotrules;
    if ( $self->uri_ok( $self->{uri} ) ) {
        $self->{_stack}->push( $self->{uri} );
        $self->{_cache}->set( $self->{uri} => [ WCS_TOSPIDER, undef, 1 ] );
    }

    return $self;
}

=head2 get_page

Fetch the page and do some book keeping. It returns a hashref with
some basic information:

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

sub get_page {
    my $self = shift;

    my( $stack, $cache ) = @{ $self }{qw( _stack _cache )};
    return unless $stack->size; # End of iteration

    my $in_cache;
    my $uri = $stack->pop;
    $uri and $in_cache = $cache->has( $uri );
    while ( defined $uri && $in_cache && !($in_cache->[0] & WCS_TOSPIDER) ) {
        $uri = $stack->pop;
        $uri and $in_cache = $cache->has( $uri );
    }
    return unless defined $uri; # End of iteration

    $self->_process( $uri );
}

=head2 _process

Private method to help not requesting pages more than once.

=cut

sub _process {
    my $self = shift;
    my $uri  = shift;

    my $mech = $self->{_agent};
    $self->{v} and print "Fetch: '$uri': ";
    $mech->get( $uri );
    $self->{v} and printf "done(%sok).\n", $mech->success ? '' : 'not ';
    $self->{_self_base} ||= $mech->base;

    $self->update_stack( $uri );

    $self->process_page( $uri );
}

=head2 update_stack

This is what the spider is all about. It will examine
C<< $self->{_agent}->links() >> to filter the links to follow.

=cut

sub update_stack {
    my( $self, $base ) = @_;

    my( $stack, $cache, $mech ) = @{ $self }{qw( _stack _cache _agent )};

    my $this_page = $cache->has( $base );
    @{ $this_page }[0, 1] = ( WCS_SPIDERED, $mech->status );

    return unless $mech->success;

    my @candidates = $self->links_filtered;

    my $new_base = $mech->base;
    foreach my $link ( @candidates ) {
        my $check = URI->new_abs( $link->url, $new_base )->as_string;
        my $data;
        if ( $data = $cache->has( $check ) ) {
        } else {
            if ( $self->uri_ok( $check ) ) {
                $stack->push( $check );
                $data = [ WCS_TOSPIDER, undef, $this_page->[2] + 1 ];
	    } else {
                $data = [ WCS_OUTSCOPE, undef, $this_page->[2] + 1 ];
            }
            $cache->set( $check => $data );
        }
    }
}

=head2 process_page( $uri )

Override this method to make the spider do something useful.

=cut

sub process_page {
    my( $self, $uri ) = @_;

    my $mech = $self->{_agent};

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

=head2 links_filtered

Filter out the uri's that will fail:

    qr!^(?:mailto:|mms://|javascript:)!i

=cut

sub links_filtered {
    my $self = shift;
    return grep {
        $_->url !~ m!^(?:mailto:|mms://|javascript:)!i
    } $self->{_agent}->links;
}

=head1 UserAgent

=head2 agent

Retruns a standard name for this UserAgent.

=cut

sub agent { return (ref( shift) || __PACKAGE__) . "/$VERSION" }

=head2 init_agent

Initialise the agent that is used to fetch pages. The default class is
C<WWW::Mechanize> but any class that has the same methods will do.

=cut

sub init_agent {
    my $self = shift;
    $self->{_agent} = $self->new_agent;
}

=head2 new_agent

Create a new agent and return it.

=cut

sub new_agent {
    my $self = shift;
    $self->{ua_class} ||= 'WWW::Mechanize';

    eval qq{ require $self->{ua_class}; };
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

=head1 Robot Rules

The Spider uses the robot rules mechanism. This means that it will
always get the F<robots.txt> file from the root of the webserver to
see if we are allowed (actually "not disallowed") to access pages as a
robot.

You can add rules for disallowing pages by specifying a list of lines
in the F<robots.txt> syntax to C<< @{ $self->{myrules} } >>.

=head2 uri_ok( $uri )

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

    $self->{_uri_ok} = '';
    $self->{v} and print "  Check '$uri'";
    $self->{_uri_ok} = 'scope'   unless $uri =~ /^$self->{_self_base}/i;
    $self->{_uri_ok} = 'pattern' if     $uri =~ m/$self->{exclude}/;

    $self->{_uri_ok} = 'robots'  unless $self->{_norules} ||
                                         $self->allowed( $uri );

    $self->{v} and
        printf " done (%s).\n", $self->{_uri_ok} ? $self->{_uri_ok} : 'ok';
    return !$self->{_uri_ok};
}

=head2 allowed( $uri )

Checks the uri against the robotrules.

=cut

sub allowed {
    my( $self, $uri ) = @_;
    $self->{_r_rules}->allowed( $uri );
}

=head2 init_robotrules( )

This will setup a <WWW::RobotRules> object. C<< @{$self->{myrules } >>
is used to add rules and should be in the RobotRules format. These
rules are B<added> to the ones found in F<robots.txt>.

=cut

sub init_robotrules {
    my $self = shift;

    my $agent = $self->agent;
    my $rules = WWW::RobotRules->new( $agent );
    my $robot_agent = "User-agent: $agent\n";

    # The $base_url should be set!
    my $robots_uri = eval {
        (URI->new_abs( '/robots.txt', $self->{_self_base} ))->as_string
    };
    $@ and do {
        require Carp;
        Carp::croak( "Error in base-url: $@\n" );
    };
    $self->{v} and print "Robot rules: '$robots_uri': ";

    my $rua = $self->new_agent;
    $rua->get( $robots_uri );
    $self->{v} and printf "done(%sok).\n", $rua->success ? '' : 'not ';
    my $robots_txt = $rua->success ? $rua->content : $robot_agent;
    $robots_txt ||= $robot_agent;

    $robots_txt .= "Disallow: $_\n" foreach @{ $self->{myrules} };

    $robots_txt .= "Disallow:\n" if ( $robots_txt =~ tr/\n// ) == 1;

    $rules->parse( $robots_uri, $robots_txt )
        if $self->{uri} =~ m|^https?://|; # problem with file:// uris

    $self->{_r_rules} =  $rules;
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
