use strict;
use warnings;

use Test::More tests => 22;
use Test::NoWarnings;
use Test::Deep;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Feed::Scrape;

use utf8;

use MediaWords::Test::HashServer;
use Readonly;
use HTML::Entities;
use Encode;
use Data::Dumper;

# must contain a hostname ('localhost') because a foreign feed link test requires it
my Readonly $TEST_HTTP_SERVER_PORT = 9998;
my Readonly $TEST_HTTP_SERVER_URL  = 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

# for testing immediate redirects; hostname is intentionally different
my Readonly $TEST_HTTP_SERVER_PORT_2 = 9999;
my Readonly $TEST_HTTP_SERVER_URL_2  = 'http://127.0.0.1:' . $TEST_HTTP_SERVER_PORT_2;

my Readonly $HTTP_CONTENT_TYPE_RSS  = 'Content-Type: application/rss+xml; charset=UTF-8';
my Readonly $HTTP_CONTENT_TYPE_ATOM = 'Content-Type: application/atom+xml; charset=UTF-8';

BEGIN { use_ok 'MediaWords::Feed::Scrape' }

sub _sample_rss_feed($;$)
{
    my ( $base_url, $title ) = @_;

    $title ||= 'Sample RSS feed';

    $base_url = encode_entities( $base_url, '<>&' );
    $title    = encode_entities( $title,    '<>&' );

    return <<"XML";
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
    <channel>
        <title>$title</title>
        <link>$base_url</link>
        <description>This is a sample RSS feed.</description>
        <item>
            <title>First post</title>
            <link>$base_url/first</link>
            <description>Here goes the first post in a sample RSS feed.</description>
        </item>
        <item>
            <title>Second post</title>
            <link>$base_url/second</link>
            <description>Here goes the second post in a sample RSS feed.</description>
        </item>
    </channel>
</rss>
XML
}

sub _sample_atom_feed($;$)
{
    my ( $base_url, $title ) = @_;

    $title ||= 'Sample Atom feed';

    $base_url = encode_entities( $base_url, '<>&' );
    $title    = encode_entities( $title,    '<>&' );

    return <<"XML";
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en-US" xml:base="$base_url/wp-atom.php">
    <title type="text">$title</title>

    <updated>2014-03-27T20:31:28Z</updated>

    <link rel="alternate" type="text/html" href="$base_url" />
    <id>$base_url/feed/atom/</id>
    <link rel="self" type="application/atom+xml" href="$base_url/feed/atom/" />

    <entry>
        <author>
            <name>john_doe</name>
            <uri>$base_url/</uri>
        </author>
        <title type="html">First post</title>
        <link rel="alternate" type="text/html" href="$base_url/first" />
        <id>$base_url/first</id>
        <updated>2014-03-27T20:31:28Z</updated>
        <published>2014-03-27T20:31:28Z</published>
        <summary type="html">Here goes the first post in a sample Atom feed.</summary>
        <content type="html" xml:base="$base_url/first">Here goes the first post in a sample Atom feed.</content>
    </entry>

    <entry>
        <author>
            <name>john_doe</name>
            <uri>$base_url/</uri>
        </author>
        <title type="html">Second post</title>
        <link rel="alternate" type="text/html" href="$base_url/second" />
        <id>$base_url/second</id>
        <updated>2014-03-27T20:31:28Z</updated>
        <published>2014-03-27T20:31:28Z</published>
        <summary type="html">Here goes the second post in a sample Atom feed.</summary>
        <content type="html" xml:base="$base_url/second">Here goes the second post in a sample Atom feed.</content>
    </entry>

</feed>
XML
}

# Basic RSS feed URL scraping
sub test_basic()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <html>
            <head>
                <title>Basic test</title>
                <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
                <link rel="alternate" type="application/atom+xml" title="Atom 0.3" href="$TEST_HTTP_SERVER_URL/feed/atom/" />
            </head>
            <body>
                <p>Hello!</p>
            </body>
            </html>
HTML

        # Sample feed
        '/feed/atom/' => {
            header  => $HTTP_CONTENT_TYPE_ATOM,
            content => _sample_atom_feed( $TEST_HTTP_SERVER_URL )
          }

    };
    my $expected_result = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed/atom/',
            'name' => 'Sample Atom feed',
            'type' => 'syndicated',
        }
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $actual_result = MediaWords::Feed::Scrape::_get_main_feed_urls_from_html( $TEST_HTTP_SERVER_URL, $pages->{ '/' } );
    $hs->stop();

    cmp_bag( $actual_result, $expected_result, 'Basic test' );
}

# Basic RSS feed URL scraping
sub test_utf8_title()
{
    my Readonly $utf8_title =
"𝘉𝘰𝘳𝘯 𝘥𝘰𝘸𝘯 𝘪𝘯 𝘢 𝘥𝘦𝘢𝘥 𝘮𝘢𝘯'𝘴 𝘵𝘰𝘸𝘯 / 𝘛𝘩𝘦 𝘧𝘪𝘳𝘴𝘵 𝘬𝘪𝘤𝘬 𝘐 𝘵𝘰𝘰𝘬 𝘸𝘢𝘴 𝘸𝘩𝘦𝘯 𝘐 𝘩𝘪𝘵 𝘵𝘩𝘦 𝘨𝘳𝘰𝘶𝘯𝘥 / äëïöü";

    my $pages = {

        # Index page
        '/' => <<"HTML",
            <html>
            <head>
                <title>Basic test</title>
                <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
                <link rel="alternate" type="application/atom+xml" title="$utf8_title" href="$TEST_HTTP_SERVER_URL/feed/atom/" />
            </head>
            <body>
                <p>Hello!</p>
            </body>
            </html>
HTML

        # Sample feed
        '/feed/atom/' => {
            header  => $HTTP_CONTENT_TYPE_ATOM,
            content => _sample_atom_feed( $TEST_HTTP_SERVER_URL, $utf8_title )
          }

    };
    my $expected_result = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed/atom/',
            'name' => $utf8_title,
            'type' => 'syndicated',
        }
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $actual_result = MediaWords::Feed::Scrape::_get_main_feed_urls_from_html( $TEST_HTTP_SERVER_URL, $pages->{ '/' } );
    $hs->stop();

    cmp_bag( $actual_result, $expected_result, 'Basic test - UTF-8 title' );
}

# Basic RSS feed (entities in URLs)
sub test_basic_entities_in_urls()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <html>
            <head>
                <title>Basic test</title>
                <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
                <link rel="alternate" type="application/atom+xml" title="Atom 0.3" href="$TEST_HTTP_SERVER_URL&#047feed/atom/" />
            </head>
            <body>
                <p>Hello!</p>
            </body>
            </html>
HTML

        # Sample feed
        '/feed/atom/' => {
            header  => $HTTP_CONTENT_TYPE_ATOM,
            content => _sample_atom_feed( $TEST_HTTP_SERVER_URL )
          }

    };
    my $expected_result = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed/atom/',
            'name' => 'Sample Atom feed',
            'type' => 'syndicated',
        }
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $actual_result = MediaWords::Feed::Scrape::_get_main_feed_urls_from_html( $TEST_HTTP_SERVER_URL, $pages->{ '/' } );
    $hs->stop();

    cmp_bag( $actual_result, $expected_result, 'Basic test - entities in URLs' );
}

# Basic RSS feed (short URLs)
sub test_basic_short_urls()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <html>
            <head>
                <title>Basic test</title>
                <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
                <link rel="alternate" type="application/atom+xml" title="Atom 0.3" href="$TEST_HTTP_SERVER_URL/feed/atom/" />
            </head>
            <body>
                <p>Hello!</p>
            </body>
            </html>
HTML

        # Sample feed
        '/feed/atom/' => {
            header  => $HTTP_CONTENT_TYPE_ATOM,
            content => _sample_atom_feed( $TEST_HTTP_SERVER_URL )
          }

    };
    my $expected_result = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed/atom/',
            'name' => 'Sample Atom feed',
            'type' => 'syndicated',
        }
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $actual_result = MediaWords::Feed::Scrape::_get_main_feed_urls_from_html( $TEST_HTTP_SERVER_URL, $pages->{ '/' } );
    $hs->stop();

    cmp_bag( $actual_result, $expected_result, 'Basic test - short URLs' );
}

# Basic RSS feed URL scraping (no RSS feed titles)
sub test_basic_no_titles()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <html>
            <head>
                <title>Basic test</title>
                <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
                <link rel="alternate" type="application/atom+xml" href="$TEST_HTTP_SERVER_URL/feed/atom/" />
            </head>
            <body>
                <p>Hello!</p>
            </body>
            </html>
HTML

        # Sample feed
        '/feed/atom/' => {
            header  => $HTTP_CONTENT_TYPE_ATOM,
            content => _sample_atom_feed( $TEST_HTTP_SERVER_URL )
          }

    };
    my $expected_result = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed/atom/',
            'name' => 'Sample Atom feed',
            'type' => 'syndicated',
        }
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $actual_result = MediaWords::Feed::Scrape::_get_main_feed_urls_from_html( $TEST_HTTP_SERVER_URL, $pages->{ '/' } );
    $hs->stop();

    cmp_bag( $actual_result, $expected_result, 'Basic test - no RSS titles' );
}

# More complex example (more HTML tags, HTML entities; from dagbladet.se)
sub test_dagbladet_se()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="sv" lang="sv" >
<head>
    
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <meta http-equiv="content-language" content="sv" />
    
    <title>Nyheter - www.dagbladet.se</title>
    
    <meta name="title" content="Nyheter - www.dagbladet.se" />
    
    <meta name="description" content="Senaste nytt från Nyheter" />
    
    <meta name="alexaVerifyID" content="9bfowyqeE5_PDkhrMX7ty7y92XU" />

    <meta name="google-site-verification" content="_G8t9o6iVkO6QH-QQGaUsWR-FVdpTRyp2sJApfHssV8" />
    
    <link rel="shortcut icon" type="image/ico" href="/polopoly_fs/2.401.1365410226!/favicon.ico" />
    
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.51407" type="application/rss+xml" title="Dagbladet.se Sundsvall" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.51411" type="application/rss+xml" title="Dagbladet.se Timrå" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.51412" type="application/rss+xml" title="Dagbladet.se Ånge" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.51414" type="application/rss+xml" title="Inrikes" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.51415" type="application/rss+xml" title="Utrikes" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.122020" type="application/rss+xml" title="Dagbladet.se Sport" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.122021" type="application/rss+xml" title="Dagbladet.se Kultur &amp; Nöje" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.2393965" type="application/rss+xml" title="Dagbladet.se Ishockey" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.4123878" type="application/rss+xml" title="Nyheter" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.4123892" type="application/rss+xml" title="Sport" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.4124304" type="application/rss+xml" title="Ekonomi &amp; prylar" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.4144811" type="application/rss+xml" title="AdaptLogic" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.4390899" type="application/rss+xml" title="Dagbladet.se GIF-kollen" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.4390938" type="application/rss+xml" title="Dagbladet.se TIK-kollen" />
    <link rel="alternate" href="$TEST_HTTP_SERVER_URL/1.4761908" type="application/rss+xml" title="Dagbladet STIL" />

    <!-- Stylesheets -->        
    <link rel="stylesheet" href="/css/global.css" type="text/css" media="all" />
    <link rel="stylesheet" href="/polopoly_fs/2.401.1365410226!/dasu_fredrikh_130403.css" type="text/css" media="all" />
HTML

        # Feeds
        '/1.51407' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Dagbladet.se Sundsvall' )
        },
        '/1.51411' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Dagbladet.se Timrå' )
        },
        '/1.51412' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Dagbladet.se Ånge' )
        },
        '/1.51414' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Inrikes' )
        },
        '/1.51415' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Utrikes' )
        },
        '/1.122020' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Dagbladet.se Sport' )
        },
        '/1.122021' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Dagbladet.se Kultur & Nöje' )
        },
        '/1.2393965' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Dagbladet.se Ishockey' )
        },
        '/1.4123878' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Nyheter' )
        },
        '/1.4123892' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Sport' )
        },
        '/1.4124304' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Ekonomi & prylar' )
        },
        '/1.4144811' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'AdaptLogic' )
        },
        '/1.4390899' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Dagbladet.se GIF-kollen' )
        },
        '/1.4390938' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Dagbladet.se TIK-kollen' )
        },
        '/1.4761908' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'Dagbladet STIL' )
        },
    };
    my $expected_result = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.51407',
            'name' => 'Dagbladet.se Sundsvall',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.51411',
            'name' => 'Dagbladet.se Timrå',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.51412',
            'name' => 'Dagbladet.se Ånge',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.51414',
            'name' => 'Inrikes',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.51415',
            'name' => 'Utrikes',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.122020',
            'name' => 'Dagbladet.se Sport',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.122021',
            'name' => 'Dagbladet.se Kultur & Nöje',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.2393965',
            'name' => 'Dagbladet.se Ishockey',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4123878',
            'name' => 'Nyheter',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4123892',
            'name' => 'Sport',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4124304',
            'name' => 'Ekonomi & prylar',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4144811',
            'name' => 'AdaptLogic',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4390899',
            'name' => 'Dagbladet.se GIF-kollen',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4390938',
            'name' => 'Dagbladet.se TIK-kollen',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4761908',
            'name' => 'Dagbladet STIL',
            'type' => 'syndicated',
        },
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $actual_result = MediaWords::Feed::Scrape::_get_main_feed_urls_from_html( $TEST_HTTP_SERVER_URL, $pages->{ '/' } );
    $hs->stop();

    cmp_bag( $actual_result, $expected_result, 'Dagbladet.se test' );
}

# More complex example (relative URLs to RSS feeds; a lot of RSS feeds in a single line; from gp.se)
sub test_gp_se()
{
    my $pages = {

        # Index page
        # DO NOT PUT LINE BREAKS BETWEEN TAGS! No line breaks is the whole point of this test.
        '/' => '' . '<link rel="alternate" href="/1.16560" type="application/rss+xml" title="GP"/> ' .
          '<link rel="alternate" href="/1.215341" type="application/rss+xml" title="GP - Bohuslän"/> ' .
          '<link rel="alternate" href="/1.16562" type="application/rss+xml" title="GP - Bostad"/> ' .
          '<link rel="alternate" href="/1.315001" type="application/rss+xml" title="GP- Debatt"/> ' .
          '<link rel="alternate" href="/1.16555" type="application/rss+xml" title="GP - Ekonomi"/> ' .
          '<link rel="alternate" href="/1.4449" type="application/rss+xml" title="GP - Filmrecensioner"/> ' .
          '<link rel="alternate" href="/1.16942" type="application/rss+xml" title="GP - Göteborg"/> ' .
          '<link rel="alternate" href="/1.291999" type="application/rss+xml" title="GP - Halland"/> ' .
          '<link rel="alternate" href="/1.165654" type="application/rss+xml" title="GP - Hela nyhetsdygnet"/> ' .
          '<link rel="alternate" href="/1.16572" type="application/rss+xml" title="GP - Jobb &amp; Studier"/> ' .
          '<link rel="alternate" href="/1.4445" type="application/rss+xml" title="GP - Konsertrecensioner"/> ' .
          '<link rel="alternate" href="/1.4470" type="application/rss+xml" title="GP - Konst&amp;Designrecensioner"/> ' .
          '<link rel="alternate" href="/1.16558" type="application/rss+xml" title="GP - Konsument"/> ' .
          '<link rel="alternate" href="/1.16941" type="application/rss+xml" title="GP - Kultur &amp; Nöje"/> ' .
          '<link rel="alternate" href="/1.872491" type="application/rss+xml" title="GP - Ledare"/> ' .
          '<link rel="alternate" href="/1.4465" type="application/rss+xml" title="GP - Litteraturrecensioner"/> ' .
          '<link rel="alternate" href="/1.16571" type="application/rss+xml" title="GP - Mat &amp; Dryck"/> ' .
          '<link rel="alternate" href="/1.4471" type="application/rss+xml" title="GP - Matrecept"/> ' .
          '<link rel="alternate" href="/1.163662" type="application/rss+xml" title="GP - Miljöspaning"/> ' .
          '<link rel="alternate" href="/1.4434" type="application/rss+xml" title="GP - Mode"/> ' .
          '<link rel="alternate" href="/1.16570" type="application/rss+xml" title="GP - Motor"/> ' .
          '<link rel="alternate" href="/1.4482" type="application/rss+xml" title="GP - Motortester"/> ' .
          '<link rel="alternate" href="/1.896286" type="application/rss+xml" title="GP - Mölndal/Härryda"/> ' .
          '<link rel="alternate" href="/1.16569" type="application/rss+xml" title="GP - Resor"/> ' .
          '<link rel="alternate" href="/1.163656" type="application/rss+xml" title="GP - Rinkside"/> ' .
          '<link rel="alternate" href="/1.4466" type="application/rss+xml" title="GP - Scenkonstrecensioner"/> ' .
          '<link rel="alternate" href="/1.4438" type="application/rss+xml" title="GP - Skivrecensioner"/> ' .
          '<link rel="alternate" href="/1.4450" type="application/rss+xml" title="GP - Spelrecensioner"/> ' .
          '<link rel="alternate" href="/1.16542" type="application/rss+xml" title="GP - Sport"/> ' .
          '<link rel="alternate" href="/1.16943" type="application/rss+xml" title="GP - Sverige"/> ' .
          '<link rel="alternate" href="/1.9146" type="application/rss+xml" title="GP - Tester"/> ' .
          '<link rel="alternate" href="/1.4468" type="application/rss+xml" title="GP - Tv-recensioner"/> ' .
          '<link rel="alternate" href="/1.16944" type="application/rss+xml" title="GP - Världen"/> ' .
          '<link rel="alternate" href="/1.970150" type="application/rss+xml" title="GP Nyheter"/>',

        # Feeds
        '/1.16560' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP' )
        },
        '/1.215341' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Bohuslän' )
        },
        '/1.16562' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Bostad' )
        },
        '/1.315001' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP- Debatt' )
        },
        '/1.16555' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Ekonomi' )
        },
        '/1.4449' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Filmrecensioner' )
        },
        '/1.16942' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Göteborg' )
        },
        '/1.291999' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Halland' )
        },
        '/1.165654' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Hela nyhetsdygnet' )
        },
        '/1.16572' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Jobb & Studier' )
        },
        '/1.4445' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Konsertrecensioner' )
        },
        '/1.4470' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Konst&Designrecensioner' )
        },
        '/1.16558' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Konsument' )
        },
        '/1.16941' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Kultur & Nöje' )
        },
        '/1.872491' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Ledare' )
        },
        '/1.4465' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Litteraturrecensioner' )
        },
        '/1.16571' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Mat & Dryck' )
        },
        '/1.4471' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Matrecept' )
        },
        '/1.163662' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Miljöspaning' )
        },
        '/1.4434' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Mode' )
        },
        '/1.16570' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Motor' )
        },
        '/1.4482' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Motortester' )
        },
        '/1.896286' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Mölndal/Härryda' )
        },
        '/1.16569' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Resor' )
        },
        '/1.163656' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Rinkside' )
        },
        '/1.4466' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Scenkonstrecensioner' )
        },
        '/1.4438' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Skivrecensioner' )
        },
        '/1.4450' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Spelrecensioner' )
        },
        '/1.16542' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Sport' )
        },
        '/1.16943' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Sverige' )
        },
        '/1.9146' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Tester' )
        },
        '/1.4468' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Tv-recensioner' )
        },
        '/1.16944' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP - Världen' )
        },
        '/1.970150' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL, 'GP Nyheter' )
        },

    };
    my $expected_result = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16560',
            'name' => 'GP',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.215341',
            'name' => 'GP - Bohuslän',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16562',
            'name' => 'GP - Bostad',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.315001',
            'name' => 'GP- Debatt',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16555',
            'name' => 'GP - Ekonomi',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4449',
            'name' => 'GP - Filmrecensioner',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16942',
            'name' => 'GP - Göteborg',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.291999',
            'name' => 'GP - Halland',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.165654',
            'name' => 'GP - Hela nyhetsdygnet',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16572',
            'name' => 'GP - Jobb & Studier',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4445',
            'name' => 'GP - Konsertrecensioner',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4470',
            'name' => 'GP - Konst&Designrecensioner',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16558',
            'name' => 'GP - Konsument',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16941',
            'name' => 'GP - Kultur & Nöje',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.872491',
            'name' => 'GP - Ledare',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4465',
            'name' => 'GP - Litteraturrecensioner',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16571',
            'name' => 'GP - Mat & Dryck',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4471',
            'name' => 'GP - Matrecept',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.163662',
            'name' => 'GP - Miljöspaning',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4434',
            'name' => 'GP - Mode',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16570',
            'name' => 'GP - Motor',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4482',
            'name' => 'GP - Motortester',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.896286',
            'name' => 'GP - Mölndal/Härryda',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16569',
            'name' => 'GP - Resor',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.163656',
            'name' => 'GP - Rinkside',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4466',
            'name' => 'GP - Scenkonstrecensioner',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4438',
            'name' => 'GP - Skivrecensioner',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4450',
            'name' => 'GP - Spelrecensioner',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16542',
            'name' => 'GP - Sport',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16943',
            'name' => 'GP - Sverige',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.9146',
            'name' => 'GP - Tester',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.4468',
            'name' => 'GP - Tv-recensioner',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.16944',
            'name' => 'GP - Världen',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/1.970150',
            'name' => 'GP Nyheter',
            'type' => 'syndicated',
        },
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $actual_result = MediaWords::Feed::Scrape::_get_main_feed_urls_from_html( $TEST_HTTP_SERVER_URL, $pages->{ '/' } );
    $hs->stop();

    cmp_bag( $actual_result, $expected_result, 'GP.se test' );
}

sub test_rss_simple_website()
{
    my $pages = {

        # Index page
        '/' => <<EOF,
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the RSS link listing:<br />
                <a href="/rss">RSS</a>
            </p>
EOF

        # RSS listing page
        '/rss' => <<EOF,
            <h1>Acme News</h1>
            <p>
            Our RSS feeds:
            </p>
            <ul>
                <li><a href="/feed1.xml">Wile E. Coyote</a></li>
                <li><a href="/feed2.xml">The Road Runner</a></li>
            </ul>
EOF

        # Sample feeds
        '/feed1.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL )
        },
        '/feed2.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL )
        },

    };
    my $expected_links = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed2.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed1.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        }
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $actual_links = MediaWords::Feed::Scrape::_get_valid_feeds_from_index_url( [ $TEST_HTTP_SERVER_URL ], 1 );
    $hs->stop();

    cmp_bag( $actual_links, $expected_links, 'test_rss_simple_website' );
}

sub test_rss_immediate_redirect_via_http_header()
{
    my $pages_1 = {

        '/' => {

            # Redirect to a new website
            redirect => $TEST_HTTP_SERVER_URL_2
        }
    };

    my $pages_2 = {

        # Index page
        '/' => <<"HTML",
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the RSS link listing:<br />
                <a href="/rss">RSS</a>
            </p>
HTML

        # RSS listing page
        '/rss' => <<"HTML",
            <h1>Acme News</h1>
            <p>
            Our RSS feeds:
            </p>
            <ul>
                <li><a href="/feed.xml">Wile E. Coyote</a></li>
            </ul>
HTML

        # Sample feeds
        '/feed.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL_2 )
        },

    };
    my $expected_links = [
        {
            'url'  => $TEST_HTTP_SERVER_URL_2 . '/feed.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        }
    ];

    my $medium = { url => $TEST_HTTP_SERVER_URL };

    my $hs1 = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT,   $pages_1 );
    my $hs2 = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT_2, $pages_2 );

    $hs1->start();
    $hs2->start();

    my $feed_links = MediaWords::Feed::Scrape::get_feed_links( $medium );

    $hs1->stop();
    $hs2->stop();

    cmp_bag( $feed_links, $expected_links, 'test_rss_immediate_redirect_via_http_header feed_links' );
}

sub test_rss_immediate_redirect_via_html_meta_refresh()
{
    my $pages_1 = {

        # META-redirect to a new website
        '/' => <<"HTML"
            <html>
                <head>
                    <meta http-equiv="Refresh" content="0; url=$TEST_HTTP_SERVER_URL_2">
                </head>
                <body>
                    <h1>Website was moved to $TEST_HTTP_SERVER_URL_2</h1>
                    <p>See you there!</p>
                </body>
            </html>
HTML

    };

    my $pages_2 = {

        # Index page
        '/' => <<"HTML",
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the RSS link listing:<br />
                <a href="/rss">RSS</a>
            </p>
HTML

        # RSS listing page
        '/rss' => <<"HTML",
            <h1>Acme News</h1>
            <p>
            Our RSS feeds:
            </p>
            <ul>
                <li><a href="/feed.xml">Wile E. Coyote</a></li>
            </ul>
HTML

        # Sample feeds
        '/feed.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL_2 )
        },

    };
    my $expected_links = [
        {
            'url'  => $TEST_HTTP_SERVER_URL_2 . '/feed.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        }
    ];

    my $medium = { url => $TEST_HTTP_SERVER_URL };

    my $hs1 = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT,   $pages_1 );
    my $hs2 = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT_2, $pages_2 );

    $hs1->start();
    $hs2->start();

    my $feed_links = MediaWords::Feed::Scrape::get_feed_links( $medium );

    $hs1->stop();
    $hs2->stop();

    cmp_bag( $feed_links, $expected_links, 'test_rss_immediate_redirect_via_html_meta_refresh feed_links' );
}

# <base href="" />, like in http://www.thejakartaglobe.com
sub test_rss_base_href()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <html>
                <head>
                    <base href="$TEST_HTTP_SERVER_URL/path_one/" target="_blank" />
                </head>
                <body>
                    <h1>Acme News</h1>
                    <p>
                        Blah blah yada yada.
                    </p>
                    <hr />
                    <p>
                        We didn't bother to add proper &lt;link&gt; links to our pages, but
                        here's a link to the RSS link listing:<br />
                        <a href="rss">RSS</a>
                    </p>
                </body>
            </html>
HTML

        # RSS listing page
        '/path_one/rss' => <<"HTML",
            <html>
                <head>
                    <base href="$TEST_HTTP_SERVER_URL/path_two/" target="_blank" />
                </head>
                <body>
                    <h1>Acme News</h1>
                    <p>
                    Our RSS feeds:
                    </p>
                    <ul>
                        <li><a href="feed1.xml">Wile E. Coyote</a></li>
                        <li><a href="feed2.xml">The Road Runner</a></li>
                    </ul>
                </body>
            </html>
HTML

        # Sample feeds
        '/path_two/feed1.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL )
        },
        '/path_two/feed2.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL )
        },

    };
    my $expected_links = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/path_two/feed1.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/path_two/feed2.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        }
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $feed_links = MediaWords::Feed::Scrape::_get_valid_feeds_from_index_url( [ $TEST_HTTP_SERVER_URL ], 1 );
    $hs->stop();

    cmp_bag( $feed_links, $expected_links, 'test_rss_base_href' );
}

sub test_rss_unlinked_urls()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the RSS link listing:<br />
                <a href="/rss">RSS</a>
            </p>
HTML

        # RSS listing page
        '/rss' => <<"HTML",
            <h1>Acme News</h1>
            <p>
            Our RSS feeds:
            </p>
            <ul>
                <!-- No links -->
                $TEST_HTTP_SERVER_URL/feed1.xml -- Wile E. Coyote<br />
                $TEST_HTTP_SERVER_URL/feed2.xml -- The Road Runner<br />
            </ul>
HTML

        # Sample feeds
        '/feed1.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL )
        },
        '/feed2.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL )
        },

    };
    my $expected_links = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed2.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed1.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        }
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $feed_links = MediaWords::Feed::Scrape::_get_valid_feeds_from_index_url( [ $TEST_HTTP_SERVER_URL ], 1 );
    $hs->stop();

    cmp_bag( $feed_links, $expected_links, 'test_rss_unlinked_urls' );
}

sub test_rss_image_link()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                <!-- Intentionally no mention of R-S-S -->
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the Rich Site Summary link listing:<br />
                <a href="/listing"><img src="/rss.png" alt="" /></a>
            </p>
HTML

        # RSS listing page
        '/listing' => <<"HTML",
            <h1>Acme News</h1>
            <p>
            Our Rich Site Summary feeds:
            </p>
            <ul>
                <li><a href="/feed1.xml">Wile E. Coyote</a></li>
                <li><a href="/feed2.xml">The Road Runner</a></li>
            </ul>
HTML

        # Sample feeds
        '/feed1.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL )
        },
        '/feed2.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL )
        },

    };
    my $expected_links = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed2.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        },
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed1.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        }
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $feed_links = MediaWords::Feed::Scrape::_get_valid_feeds_from_index_url( [ $TEST_HTTP_SERVER_URL ], 1 );
    $hs->stop();

    cmp_bag( $feed_links, $expected_links, 'test_rss_image_link' );
}

sub test_rss_external_feeds()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the RSS link listing:<br />
                <a href="/rss">RSS</a>
            </p>
HTML

        # RSS listing page
        '/rss' => <<"HTML",
            <h1>Acme News</h1>
            <p>
            Our RSS feeds:
            </p>
            <ul>
                <li><a href="http://feeds2.feedburner.com/localhost">Wile E. Coyote</a></li> <!-- This one should be declared as main feed -->
                <li><a href="http://quotidianohome.feedsportal.com/c/33327/f/565662/index.rss">The Road Runner</a></li> <!-- This one should *not* be declared a main feed -->
            </ul>
HTML
    };

    my $expected_links = [
        {
            'url'  => 'http://feeds2.feedburner.com/localhost',
            'name' => '127.0.0.1 » 127.0.0.1',
            'type' => 'syndicated',
        },
    ];

    my $medium = { url => $TEST_HTTP_SERVER_URL };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $feed_links = MediaWords::Feed::Scrape::get_feed_links( $medium );
    $hs->stop();

    cmp_bag( $feed_links, $expected_links, 'test_rss_external_feeds feed_links' );
}

sub test_get_feed_links()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the RSS link listing:<br />
                <a href="/rss">RSS</a>
            </p>
HTML

        # URL that looks like a feed but doesn't contain one
        '/feed' => <<"HTML",
            The feed searcher will look here, but there is no feed to be found at this URL.
HTML

        # RSS listing page
        '/rss' => <<"HTML",
            <h1>Acme News</h1>
            <p>
            Our RSS feeds:
            </p>
            <ul>
                <!-- "?format=html" was present in http://www.eldis.org/go/subscribe, elsewhere too -->
                <li><a href="http://feeds.feedburner.com/feedburnerstatus?format=html">Wile E. Coyote</a></li>

                <li><a href="http://feeds.feedburner.com/thesartorialist">The Road Runner</a></li>
            </ul>
HTML
    };

    my $expected_links = [
        {
            'url'  => 'http://feeds.feedburner.com/feedburnerstatus',
            'name' => 'FeedBurner Status',
            'type' => 'syndicated',
        },
        {
            'url'  => 'http://feeds.feedburner.com/thesartorialist',
            'name' => 'The Sartorialist',
            'type' => 'syndicated',
        }
    ];

    my $medium = { url => $TEST_HTTP_SERVER_URL };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $feed_links = MediaWords::Feed::Scrape::get_feed_links( $medium );
    $hs->stop();

    cmp_bag( $feed_links, $expected_links, 'test_get_feed_links feed_links' );
}

sub test_feeds_with_common_prefix()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the RSS link listing:<br />
                <a href="/rss">RSS</a>
            </p>
HTML

        # RSS listing page
        '/rss' => <<"HTML",
            <h1>Acme News</h1>
            <p>
            Our RSS feeds:
            </p>
            <ul>
                <li><a href="$TEST_HTTP_SERVER_URL/feed1.xml">Feed one</a></li>
                <li><a href="$TEST_HTTP_SERVER_URL/feed2.xml">Feed two</a></li>
                <li><a href="$TEST_HTTP_SERVER_URL/feed3.xml">Feed three</a></li>
            </ul>
HTML

        # Sample feeds
        '/feed1.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => <<"XML"
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
        <title>Example.com - Sports</title> <!-- One of the sub-feeds -->
</channel></rss>
XML
        },
        '/feed2.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => <<"XML"
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
        <title>Example.com</title> <!-- This is the "main" feed which is expected to
                                        contain posts from the sub-feeds above -->
</channel></rss>
XML
        },
        '/feed3.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => <<XML
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
        <title>Example.com - Entertainment</title> <!-- One of the sub-feeds -->
</channel></rss>
XML
        },

    };
    my $expected_links = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed2.xml',
            'name' => 'Example.com',
            'type' => 'syndicated',
        },
    ];

    my $medium = { url => $TEST_HTTP_SERVER_URL };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $feed_links = MediaWords::Feed::Scrape::get_feed_links( $medium );
    $hs->stop();

    cmp_bag( $feed_links, $expected_links, 'test_feeds_with_common_prefix feed_links' );
}

sub test_feed_aggregator_urls()
{
    my $pages = {

        # Index page
        '/' => <<"HTML",
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                We didn't bother to add proper &lt;link&gt; links to our pages, but
                here's a link to the RSS link listing:<br />
                <a href="/rss">RSS</a>
            </p>
HTML

        # RSS listing page
        '/rss' => <<"HTML",
            <h1>Acme News</h1>
            <p>
            Our RSS feeds:
            </p>
            <ul>
                <li><a href="http://www.google.com/ig/add?feedurl=$TEST_HTTP_SERVER_URL/feed.xml">Add to Google</a></li>
                <li><a href="http://add.my.yahoo.com/rss?url=$TEST_HTTP_SERVER_URL/feed.xml">Add to Yahoo!</a></li>
                <li><a href="http://www.netvibes.com/subscribe.php?url=$TEST_HTTP_SERVER_URL/feed.xml">Add to NetVibes</a></li>
            </ul>
HTML

        # Sample feeds
        '/feed.xml' => {
            header  => $HTTP_CONTENT_TYPE_RSS,
            content => _sample_rss_feed( $TEST_HTTP_SERVER_URL )
        },

    };
    my $expected_links = [
        {
            'url'  => $TEST_HTTP_SERVER_URL . '/feed.xml',
            'name' => 'Sample RSS feed',
            'type' => 'syndicated',
        },
    ];

    my $medium = { url => $TEST_HTTP_SERVER_URL };

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $feed_links = MediaWords::Feed::Scrape::get_feed_links( $medium );
    $hs->stop();

    cmp_bag( $feed_links, $expected_links, 'test_feed_aggregator_urls feed_links' );
}

sub test_web_page_feed()
{
    my $medium_name = 'Acme News -- The best news ever!';
    my $medium      = { url => $TEST_HTTP_SERVER_URL, name => $medium_name };
    my $pages       = {

        # Index page
        '/' => <<"HTML",
            <h1>Acme News</h1>
            <p>
                Blah blah yada yada.
            </p>
            <hr />
            <p>
                This website doesn't have any RSS feeds, so it should be added
                as an "web_page" feed.
            </p>
HTML
    };
    my $expected_links = [
        {
            'url'  => $TEST_HTTP_SERVER_URL,
            'name' => $medium_name,
            'type' => 'web_page',
        },
    ];

    my $hs = MediaWords::Test::HashServer->new( $TEST_HTTP_SERVER_PORT, $pages );

    $hs->start();
    my $feed_links = MediaWords::Feed::Scrape::get_feed_links( $medium );
    $hs->stop();

    cmp_bag( $feed_links, $expected_links, 'test_web_page_feed feed_links' );
}

# make sure that a bad medium doesn't cause an error
sub test_bad_medium_url
{
    my $feeds = MediaWords::Feed::Scrape::get_feed_links( { url => 'http://bad@url!' } );
    cmp_bag( $feeds, [] );
}

sub main
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_basic();
    test_utf8_title();
    test_basic_entities_in_urls();
    test_basic_short_urls();
    test_basic_no_titles();
    test_dagbladet_se();
    test_gp_se();
    test_rss_simple_website();
    test_rss_immediate_redirect_via_http_header();
    test_rss_immediate_redirect_via_html_meta_refresh();
    test_rss_base_href();
    test_rss_unlinked_urls();
    test_rss_image_link();
    test_rss_external_feeds();
    test_get_feed_links();
    test_feeds_with_common_prefix();
    test_feed_aggregator_urls();
    test_web_page_feed();
    test_bad_medium_url();

    Test::NoWarnings::had_no_warnings();
}

main();

