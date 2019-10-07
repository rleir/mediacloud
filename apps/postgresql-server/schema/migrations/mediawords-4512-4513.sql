--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4512 and 4513.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4512, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4513, import this SQL file:
--
--     psql mediacloud < mediawords-4512-4513.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Copy of "feeds" table from yesterday; used for generating reports for rescraping efforts
CREATE TABLE feeds_from_yesterday (
    feeds_id            INT                 NOT NULL,
    media_id            INT                 NOT NULL,
    name                VARCHAR(512)        NOT NULL,
    url                 VARCHAR(1024)       NOT NULL,
    feed_type           feed_feed_type      NOT NULL,
    feed_status         feed_feed_status    NOT NULL
);

CREATE INDEX feeds_from_yesterday_feeds_id ON feeds_from_yesterday(feeds_id);
CREATE INDEX feeds_from_yesterday_media_id ON feeds_from_yesterday(media_id);
CREATE INDEX feeds_from_yesterday_name ON feeds_from_yesterday(name);
CREATE UNIQUE INDEX feeds_from_yesterday_url ON feeds_from_yesterday(url, media_id);

--
-- Update "feeds_from_yesterday" with a new set of feeds
--
CREATE OR REPLACE FUNCTION update_feeds_from_yesterday() RETURNS VOID AS $$
BEGIN

    TRUNCATE TABLE feeds_from_yesterday;
    INSERT INTO feeds_from_yesterday (feeds_id, media_id, name, url, feed_type, feed_status)
        SELECT feeds_id, media_id, name, url, feed_type, feed_status
        FROM feeds;

END;
$$
LANGUAGE 'plpgsql';

--
-- Print out a diff between "feeds" and "feeds_from_yesterday"
--
CREATE OR REPLACE FUNCTION rescraping_changes() RETURNS VOID AS
$$
DECLARE
    r_media RECORD;
    r_feed RECORD;
BEGIN

    -- Check if media exists
    IF NOT EXISTS (
        SELECT 1
        FROM feeds_from_yesterday
    ) THEN
        RAISE EXCEPTION '"feeds_from_yesterday" table is empty.';
    END IF;

    RAISE NOTICE 'Changes between "feeds" and "feeds_from_yesterday":';
    RAISE NOTICE '';

    FOR r_media IN
        SELECT *
        FROM media
        WHERE media_id IN (
            SELECT DISTINCT media_id
            FROM (
                SELECT feeds_id, media_id, feed_type, feed_status, name, url FROM feeds_from_yesterday
                EXCEPT
                SELECT feeds_id, media_id, feed_type, feed_status, name, url FROM feeds
            ) AS modified_feeds
        )
        ORDER BY media_id
    LOOP
        RAISE NOTICE 'MODIFIED media: media_id=%, name="%", url="%"',
            r_media.media_id,
            r_media.name,
            r_media.url;

        FOR r_feed IN
            SELECT *
            FROM feeds
            WHERE media_id = r_media.media_id
              AND feeds_id NOT IN (
                SELECT feeds_id
                FROM feeds_from_yesterday
            )
        LOOP
            RAISE NOTICE '    ADDED feed: feeds_id=%, feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.feeds_id,
                r_feed.feed_type,
                r_feed.feed_status,
                r_feed.name,
                r_feed.url;
        END LOOP;

        -- Feeds shouldn't get deleted but we're checking anyways
        FOR r_feed IN
            SELECT *
            FROM feeds_from_yesterday
            WHERE media_id = r_media.media_id
              AND feeds_id NOT IN (
                SELECT feeds_id
                FROM feeds
            )
        LOOP
            RAISE NOTICE '    DELETED feed: feeds_id=%, feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.feeds_id,
                r_feed.feed_type,
                r_feed.feed_status,
                r_feed.name,
                r_feed.url;
        END LOOP;

        FOR r_feed IN
            SELECT feeds_before.feeds_id,

                   feeds_before.name AS before_name,
                   feeds_before.url AS before_url,
                   feeds_before.feed_type AS before_feed_type,
                   feeds_before.feed_status AS before_feed_status,

                   feeds_after.name AS after_name,
                   feeds_after.url AS after_url,
                   feeds_after.feed_type AS after_feed_type,
                   feeds_after.feed_status AS after_feed_status

            FROM feeds_from_yesterday AS feeds_before
                INNER JOIN feeds AS feeds_after ON (
                    feeds_before.feeds_id = feeds_after.feeds_id
                    AND (
                        feeds_before.name != feeds_after.name
                     OR feeds_before.url != feeds_after.url
                     OR feeds_before.feed_type != feeds_after.feed_type
                     OR feeds_before.feed_status != feeds_after.feed_status
                    )
                )

            WHERE feeds_before.media_id = r_media.media_id

            ORDER BY feeds_before.feeds_id
        LOOP
            RAISE NOTICE '    MODIFIED feed: feeds_id=%', r_feed.feeds_id;
            RAISE NOTICE '        BEFORE: feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.before_feed_type,
                r_feed.before_feed_status,
                r_feed.before_name,
                r_feed.before_url;
            RAISE NOTICE '        AFTER:  feed_type=%, feed_status=%, name="%", url="%"',
                r_feed.after_feed_type,
                r_feed.after_feed_status,
                r_feed.after_name,
                r_feed.after_url;
        END LOOP;

        RAISE NOTICE '';

    END LOOP;

END;
$$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4513;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

