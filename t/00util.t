#! perl -w
use strict;

use Test::More tests => 18;

BEGIN{ use_ok 'WWW::CheckSite::Util'; }

ok defined( &WWW::CheckSite::Util::new_cache ), "new_cache() exists";
{
    my $cache = WWW::CheckSite::Util::new_cache();
    isa_ok $cache, 'WWW::CheckSite::Util::Cache';
}
ok defined( &WWW::CheckSite::Util::new_stack ), "new_stack() exitst";
{
    my $stack = WWW::CheckSite::Util::new_stack();
    isa_ok $stack, 'WWW::CheckSite::Util::Stack';
}

{
    ok defined( &new_cache ), "new_cache() imported";
    my $cache = new_cache;
    isa_ok $cache, 'WWW::CheckSite::Util::Cache';

    ok $cache->set( key => 'val' ), "set( value => val )";
    is $cache->has( 'key' ), 'val', "has( key )";
    is $cache->unset( 'key' ), 'val' , "unset( key )";
    is $cache->has( 'key' ), undef, "hasn't got 'key'"
}

{
    ok defined( &new_stack ), "new_stack() imported";
    my $stack = new_stack;
    isa_ok $stack, 'WWW::CheckSite::Util::Stack';

    ok $stack->push( 'val' ), "Push";
    is $stack->peek, 'val',   "Peek";
    is $stack->pop,  'val',   "Pop";
    is $stack->pop, undef,    "no more pop";
    is $stack->peek, undef,   "no more peek";
}
