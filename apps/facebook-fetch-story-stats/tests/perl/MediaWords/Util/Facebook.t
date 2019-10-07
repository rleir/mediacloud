use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::Util::Facebook;
use MediaWords::Util::Config::Facebook;
use MediaWords::Test::DB::Create;

use Data::Dumper;

# URLs that might fail
sub test_bogus_urls($)
{
    my ( $db ) = @_;

    my @bogus_urls = (

        # URLs with #fragment
        'http://www.nbcnews.com/#/health/health-news/inside-ebola-clinic-doctors-fight-out-control-virus-%20n150391',
        'http://www.nbcnews.com/#/health/',
        'http://www.nbcnews.com/#/health',
        'http://www.nbcnews.com/#/',
        'http://foo.com/#/bar/',

        # URLs with ~tilde
        'http://cyber.law.harvard.edu/~lvaliukas/test.html/',
        'http://cyber.law.harvard.edu/~lvaliukas/test.html/#/foo',
        'http://feeds.please-note-that-this-url-is-not-gawker.com/~r/gizmodo/full/~3/qIhlxlB7gmw/foo-bar-baz-1234567890/',
        'http://feeds.boingboing.net/~r/boingboing/iBag/~3/W1mgVFzEwm4/last-chance-to-save-net-neutra.html/',

        # URLs with #fragment that's about to be removed
        'http://www.macworld.com/article/2154541/podcast-we-got-the-beats.html#tk.rss_all',

        # Gawker's feed URLs
'http://feeds.gawker.com/~r/gizmodo/full/~3/qIhlxlB7gmw/how-to-yell-at-the-fcc-about-how-much-you-hate-its-net-1576943170',
'http://feeds.gawker.com/~r/gawker/full/~3/FjKCT99u_M8/wall-street-is-doing-devious-shit-while-america-sleeps-1679519880',

        # URL that doesn't return "share" or "og_object" keys
'http://feeds.chicagotribune.com/~r/chicagotribune/views/~3/weNQRdjizS8/sns-rt-us-usa-court-netneutrality-20140114,0,5487975.story',

        # Bogus URL with "http:/www" (fixable by fix_common_url_mistakes())
        'http:/www.theinquirer.net/inquirer/news/2322928/net-neutrality-rules-lie-in-tatters-as-fcc-overruled',
    );

    foreach my $bogus_url ( @bogus_urls )
    {
        eval { MediaWords::Util::Facebook::get_url_share_comment_counts( $db, $bogus_url ); };
        ok( !$@, "Stats were fetched for bogus URL '$bogus_url'" );
    }
}

sub test_share_comment_counts($)
{
    my ( $db ) = @_;

    my ( $nyt_ferguson_share_count, $nyt_ferguson_comment_count ) =
      MediaWords::Util::Facebook::get_url_share_comment_counts( $db,
        'http://www.nytimes.com/interactive/2014/08/13/us/ferguson-missouri-town-under-siege-after-police-shooting.html' );
    ok( $nyt_ferguson_share_count > 0, "nyt ferguson count '$nyt_ferguson_share_count' should be positive" );

    my ( $zero_share_count, $zero_comment_count ) =
      MediaWords::Util::Facebook::get_url_share_comment_counts( $db, 'http://totally.bogus.url.123456' );
    ok( $zero_share_count == 0,   "zero share count '$zero_share_count' should be 0" );
    ok( $zero_comment_count == 0, "zero comment count '$zero_comment_count' should be 0" );
}

sub test_store_result($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack( $db, { A => { B => [ 1, 2, 3 ] } } );

    my $story = $media->{ A }->{ feeds }->{ B }->{ stories }->{ 1 };

    $story->{ url } = 'http://google.com';

    my ( $share_count, $comment_count ) = MediaWords::Util::Facebook::get_and_store_share_comment_counts( $db, $story );

    my $ss = $db->query( 'select * from story_statistics where stories_id = ?', $story->{ stories_id } )->hash;

    ok( $ss, 'story_statistics row exists after initial insert' );

    is( $ss->{ facebook_share_count },   $share_count,   "stored url share count" );
    is( $ss->{ facebook_comment_count }, $comment_count, "stored url comment count" );
    ok( !defined( $ss->{ facebook_api_error } ), "null url share count error" );

    $story->{ url } = 'boguschema://foobar';

    MediaWords::Util::Facebook::get_and_store_share_comment_counts( $db, $story );

    my $sse = $db->query( 'select * from story_statistics where stories_id = ?', $story->{ stories_id } )->hash;

    is( $sse->{ facebook_share_count },   0, "stored url share count should 0 after error" );
    is( $sse->{ facebook_comment_count }, 0, "stored url comment count should 0 after error" );
    ok( defined( $sse->{ facebook_api_error } ), "facebook should have reported an error" );
}

sub main()
{
    unless ( MediaWords::Util::Config::Facebook::is_enabled() ) {
        plan skip_all => "Facebook's API is not enabled.";
        return;
    }

    plan tests => 24;

    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    my $db = MediaWords::DB::connect_to_db();

    test_bogus_urls( $db );
    test_share_comment_counts( $db );
    test_store_result( $db );
}

main();
