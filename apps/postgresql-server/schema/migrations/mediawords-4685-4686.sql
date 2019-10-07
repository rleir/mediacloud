--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4685 and 4686.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4685, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4686, import this SQL file:
--
--     psql mediacloud < mediawords-4685-4686.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Will recreate later
DROP VIEW feedly_unscraped_feeds;


DROP TABLE stories_superglue_metadata;


CREATE TEMPORARY TABLE temp_superglue_feeds AS
    SELECT feeds_id
    FROM feeds
    WHERE type = 'superglue';

CREATE TEMPORARY TABLE temp_superglue_stories AS
    SELECT stories_id
    FROM feeds_stories_map
    WHERE feeds_id IN (SELECT feeds_id FROM temp_superglue_feeds);

-- Faster deletes and foreign key matching
CREATE INDEX retweeter_stories_stories_id ON retweeter_stories (stories_id);

DELETE FROM cliff_annotations
WHERE object_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM nytlabels_annotations
WHERE object_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM topic_links
WHERE ref_stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM topic_merged_stories_map
WHERE source_stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM topic_merged_stories_map
WHERE target_stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM topic_seed_urls
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM topic_stories
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM snap.live_stories
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM processed_stories
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM retweeter_stories
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM scraped_stories
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM solr_import_stories
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM solr_imported_stories
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM stories_ap_syndicated
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM stories_tags_map
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM story_sentences
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM story_statistics
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM story_statistics_twitter
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM stories
WHERE stories_id IN (SELECT stories_id FROM temp_superglue_stories);

DELETE FROM downloads
WHERE feeds_id IN (SELECT feeds_id FROM temp_superglue_feeds);

DELETE FROM feeds
WHERE feeds_id IN (SELECT feeds_id FROM temp_superglue_feeds);

-- No longer need it
DROP INDEX retweeter_stories_stories_id;

DROP TABLE temp_superglue_stories;
DROP TABLE temp_superglue_feeds;


-- Only way to get rid of valid enum type value is to recreate the enum
CREATE TYPE feed_type_new AS ENUM ('syndicated', 'web_page', 'univision');

ALTER TABLE feeds ALTER COLUMN type DROP DEFAULT;
ALTER TABLE feeds ALTER COLUMN type TYPE feed_type_new USING (type::text::feed_type_new);
ALTER TABLE feeds ALTER COLUMN type SET DEFAULT 'syndicated';

ALTER TABLE feeds_after_rescraping ALTER COLUMN type DROP DEFAULT;
ALTER TABLE feeds_after_rescraping ALTER COLUMN type TYPE feed_type_new USING (type::text::feed_type_new);
ALTER TABLE feeds_after_rescraping ALTER COLUMN type SET DEFAULT 'syndicated';

ALTER TABLE feeds_from_yesterday ALTER COLUMN type DROP DEFAULT;
ALTER TABLE feeds_from_yesterday ALTER COLUMN type TYPE feed_type_new USING (type::text::feed_type_new);
ALTER TABLE feeds_from_yesterday ALTER COLUMN type SET DEFAULT 'syndicated';

DROP TYPE feed_type;
ALTER TYPE feed_type_new RENAME TO feed_type;


CREATE VIEW feedly_unscraped_feeds AS
    SELECT f.*
    FROM feeds AS f
        LEFT JOIN scraped_feeds AS sf
            ON f.feeds_id = sf.feeds_id
           AND sf.import_module = 'MediaWords::ImportStories::Feedly'
        WHERE f.type = 'syndicated'
          AND f.active = 't'
          AND sf.feeds_id IS NULL;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4686;
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

