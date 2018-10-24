package MediaWords::Crawler::Provider;

# Provision downloads for the download fetcher in memory downloads queue
#
# The provider is responsible for provisioning downloads for the engine's in
# memory downloads queue.  The basic job of the provider is just to query the
# downloads table for any downloads with `state = 'pending'`.  As detailed in
# the handler section below, most 'pending' downloads are added by the handler
# when the url for a new story is discovered in a just download feed.
#
# But the provider is also responsible for periodically adding feed downloads
# to the queue.  The provider uses a back off algorithm that starts by
# downloading a feed five minutes after a new story was last found and then
# doubles the delay each time the feed is download and no new story is found,
# until the feed is downloaded only once a week.
#
# The provider is also responsible for throttling downloads by site, so only a
# limited number of downloads for each site are provided to the the engine each
# time the engine asks for a chunk of new downloads.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;
use List::MoreUtils;
use Readonly;

use MediaWords::DB;
use MediaWords::Crawler::Provider::Queue;
use MediaWords::Crawler::Provider::Configuration;
use MediaWords::Job::FetchDownload;
use MediaWords::Util::Config;

# how often to download each feed (seconds)
Readonly my $STALE_FEED_INTERVAL => 60 * 60 * 24 * 7;

# how often to check for feeds to download (seconds)
Readonly my $STALE_FEED_CHECK_INTERVAL => 60 * 30;

# timeout for download in fetching state (seconds)
Readonly my $STALE_DOWNLOAD_INTERVAL => 60 * 5;

# how many downloads to store in memory queue
Readonly my $MAX_QUEUED_DOWNLOADS => 1_000_000;

# Create a new provider.
sub new($;$)
{
    my ( $class, $configuration ) = @_;

    my $self = {};
    bless( $self, $class );

    $configuration ||= MediaWords::Crawler::Provider::Configuration->new();

    $self->{ _queue } = MediaWords::Crawler::Provider::Queue->new();

    # Last time a pending downloads check was run
    $self->{ _last_pending_check } = 0;

    # Last time a stale feed check was run
    $self->{ _last_stale_feed_check } = 0;

    # Last time a stale download check was run
    $self->{ _last_stale_download_check } = 0;

    return $self;
}

# delete downloads in fetching mode more than five minutes old.
# this shouldn't technically happen, but we want to make sure that
# no hosts get hung b/c a download sits around in the fetching state forever
sub _timeout_stale_downloads
{
    my ( $self ) = @_;

    if ( $self->{ _last_stale_download_check } > ( time() - $STALE_DOWNLOAD_INTERVAL ) )
    {
        return;
    }
    $self->{ _last_stale_download_check } = time();

    my $dbs       = $self->engine->dbs;
    my $downloads = $dbs->query(<<SQL
        SELECT *
        FROM downloads_media
        WHERE state = 'fetching'
          AND download_time < (NOW() - interval '5 minutes')
SQL
    )->hashes;

    for my $download ( ${ downloads } )
    {
        my $downloads_id = $download->{ downloads_id };

        $download->{ state }         = 'error';
        $download->{ error_message } = 'Download timed out by Fetcher::_timeout_stale_downloads';
        $download->{ download_time } = 'now()'; # FIXME will this work in Python?

        $dbs->update_by_id( "downloads", $downloads_id, $download );

        DEBUG "Timed out stale download $downloads_id with URL " . $download->{ url };
    }
}

# get all stale feeds and add each to the download queue this subroutine expects to be executed in a transaction
sub _add_stale_feeds
{
    my ( $self ) = @_;

    if ( ( time() - $self->{ _last_stale_feed_check } ) < $STALE_FEED_CHECK_INTERVAL )
    {
        return;
    }

    my $stale_feed_interval = $STALE_FEED_INTERVAL;

    DEBUG "_add_stale_feeds";

    $self->{ _last_stale_feed_check } = time();

    my $dbs = $self->engine->dbs;

    my $constraint = <<"SQL";
SQL

    # If the table doesn't exist, PostgreSQL sends a NOTICE which breaks the "no warnings" unit test
    $dbs->query( 'SET client_min_messages=WARNING' );
    $dbs->query( 'DROP TABLE IF EXISTS feeds_to_queue' );
    $dbs->query( 'SET client_min_messages=NOTICE' );

    $dbs->query( <<"SQL" );
        CREATE TEMPORARY TABLE feeds_to_queue AS
        SELECT feeds_id,
               url
        FROM feeds
        WHERE active = 't'
          AND url ~ 'https?://'
          AND (
            -- Never attempted
            last_attempted_download_time IS NULL

            -- Feed was downloaded more than $stale_feed_interval seconds ago
            OR (last_attempted_download_time < (NOW() - interval '$stale_feed_interval seconds'))

            -- (Probably) if a new story comes in every "n" seconds, refetch feed every "n" + 5 minutes
            OR (
                (NOW() > last_attempted_download_time + ( last_attempted_download_time - last_new_story_time ) + interval '5 minutes')

                -- "web_page" feeds are to be downloaded only once a week,
                -- independently from when the last new story comes in from the
                -- feed (because every "web_page" feed download provides a
                -- single story)
                AND type != 'web_page'
            )
          )
SQL

    $dbs->query( <<"SQL" );
        UPDATE feeds
        SET last_attempted_download_time = NOW()
        WHERE feeds_id IN (SELECT feeds_id FROM feeds_to_queue)
SQL

    my $downloads = $dbs->query( <<"SQL" )->hashes;
        INSERT INTO downloads (feeds_id, url, host, type, sequence, state, priority, download_time, extracted)
        SELECT feeds_id,
               url,
               LOWER(SUBSTRING(url from '.*://([^/]*)' )),
               'feed',
               1,
               'pending',
               0,
               NOW(),
               false
        FROM feeds_to_queue
        RETURNING *
SQL

    for my $download ( @{ $downloads } )
    {
        my $medium = $dbs->query( "SELECT media_id FROM feeds WHERE feeds_id = ?", $download->{ feeds_id } )->hash;
        $download->{ _media_id } = $medium->{ media_id };
        $self->{ _queue }->queue_download( $download );
    }

    $dbs->query( "DROP TABLE feeds_to_queue" );

    DEBUG "end _add_stale_feeds";
}

# add all pending downloads to the $_downloads list
sub _add_pending_downloads
{
    my ( $self ) = @_;

    my $interval = $configuration->pending_check_interval();

    if ( $self->{ _last_pending_check } > ( time() - $interval ) ) {
        return;
    }

    $self->{ _last_pending_check } = time();

    if ( $self->{ _queue }->get_downloads_size() > $MAX_QUEUED_DOWNLOADS )
    {
        DEBUG "Skipping add pending downloads due to queue size";
        return;
    }

    my $db = $self->engine->dbs;

    $db->query( <<SQL
        CREATE TEMPORARY TABLE _ranked_downloads AS
            SELECT
                d.*,
                COALESCE( d.host , 'non-media' ) AS site,
                RANK() OVER (PARTITION BY d.host ORDER BY priority ASC, d.downloads_id DESC) AS site_rank
            FROM downloads AS d
            WHERE d.state = 'pending'
              and (d.download_time < NOW() OR d.download_time IS NULL)
SQL
    );

    my $downloads = $db->query( <<SQL,
        SELECT
            rd.*, 
            f.media_id AS _media_id
        FROM _ranked_downloads AS rd
            -- FIXME why join "feeds" here?
            JOIN feeds AS f USING (feeds_id)
        ORDER BY
            priority ASC,
            site_rank ASC,
            downloads_id DESC
        LIMIT ?
SQL
        $MAX_QUEUED_DOWNLOADS
    )->hashes;

    $db->query( "DROP TABLE _ranked_downloads" );

    map { $self->{ _queue }->queue_download( $_ ) } @{ $downloads };
}

# Hand out a list of pending downloads, throttling the downloads by site
# (download host, generally), so that a download is only handed our for each
# site each $configuration->throttle seconds.
#
# Every $STALE_FEED_INTERVAL, add downloads for all feeds that are due to be
# downloaded again according to # the back off algorithm.
#
# Every $configuration->pending_check_interval seconds, query the database for
# pending downloads (`state = 'pending'`).

sub _provide_downloads($$)
{
    my ( $db, $configuration ) = @_;

    $self->_timeout_stale_downloads();

    $self->_add_stale_feeds();

    $self->_add_pending_downloads();

    my $downloads = [];
    my $skipped_download_count = 0;

    for my $media ( @{ $self->{ _queue }->get_download_media_ids() } )
    {
        my $media_id = $media->{ media_id };

        # We just slept for 1 so only bother calling time() if throttle is greater than 1
        my $throttle = $configuration->throttle();
        if ( $throttle >= 1 and $media->{ time } > ( time() - $throttle ) )
        {
            TRACE "Skipping media ID $media_id because of throttling";

            ++$skipped_download_count;

            next;
        }

        if ( my $download = $self->{ _queue }->pop_download( $media_id ) )
        {
            push( @{ $downloads }, $download );
        }
    }

    if ( $skipped_download_count > 0 ) {
        DEBUG "Skipped / throttled downloads: $skipped_download_count";
    }

    DEBUG "Provide downloads: " . scalar( @{ $downloads } ) . " downloads";

    if ( scalar @{ $downloads } == 0 )
    {
        DEBUG "Sleeping for " . $configuration->sleep_interval() . " seconds due to empty queue.";
        sleep( $configuration->sleep_interval() );
    }

    return $downloads;
}

sub _reset_fetching_downloads($)
{
    $db->query( "UPDATE downloads set state = 'pending' where state = 'fetching'" );
}

# Provide a single chunk of downloads
#
# 1. if the in memory queue of pending downloads is empty, calls _provide_downloads() to refill it;
# 2. adds the pending downloads to the fetcher's queue.
sub provide_single_chunk($;$$)
{
    my ( $db, $configuration, $skip_resetting_fetching_downloads ) = @_;

    $configuration ||= MediaWords::Crawler::Provider::Configuration->new();

    unless ( $skip_resetting_fetching_downloads ) {
        _reset_fetching_downloads( $db );
    }

    $db->run_block_with_large_work_mem(
        sub {

            DEBUG "Refilling queued downloads...";
            my $queued_downloads = _provide_downloads($db, $configuration );

            foreach my $queued_download (@{ $queued_downloads }) {
                my $downloads_id = $queued_download->{ downloads_id };
                TRACE "Adding download $downloads_id to the fetch queue...";

                MediaWords::Job::FetchDownload->add_to_queue({
                    downloads_id => $downloads_id
                });
            }
        }
    );
}

# (static) Loop provide_single_chunk() forever
sub provide(;$)
{
    my ( $configuration ) = @_;

    _reset_fetching_downloads( $db );
    Readonly my $skip_resetting_fetching_downloads => 1;

    while ( 1 ) {

        DEBUG "Reconnecting to the database...";
        my $db = MediaWords::DB::connect_to_db();

        provide_single_chunk( $db, $configuration, $skip_resetting_fetching_downloads );
    }
}

1;
