--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4669 and 4670.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4669, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4670, import this SQL file:
--
--     psql mediacloud < mediawords-4669-4670.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


CREATE OR REPLACE FUNCTION copy_chunk_of_nonpartitioned_sentences_to_partitions(story_chunk_size INT)
RETURNS VOID AS $$

DECLARE
    copied_sentence_count INT;

BEGIN

    RAISE NOTICE 'Copying sentences of up to % stories to the partitioned table...', story_chunk_size;

    -- Kill all autovacuums before proceeding with DDL changes
    PERFORM pid
    FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
    WHERE backend_type = 'autovacuum worker'
      AND query ~ 'story_sentences';

    WITH deleted_rows AS (

        -- Fetch and delete sentences of selected stories
        DELETE FROM story_sentences_nonpartitioned
        WHERE stories_id IN (

            -- Pick unique story IDs from the returned resultset
            SELECT DISTINCT stories_id
            FROM (

                -- "SELECT DISTINCT stories_ID ... ORDER BY stories_id" from
                -- the non-partitioned table to copy them to the partitioned
                -- one worked fine at first but then got superslow. My guess is
                -- that it's because of the index bloat: the oldest story IDs
                -- got removed from the table (their tuples were marked as
                -- "deleted"), so after a while the database was struggling to
                -- get through all the dead rows to get to the next chunk of
                -- the live ones.
                --
                -- "SELECT DISTINCT" without the "ORDER BY" has a similar
                -- effect, probably because it uses the very same index. At
                -- least for now, the most effective strategy seems to do a
                -- sequential scan with a LIMIT on the table, collect an
                -- approximate amount of sentences for the given story count to
                -- copy, and then DISTINCT them as a separate step.
                SELECT stories_id
                FROM story_sentences_nonpartitioned

                -- Assume that a single story has 10 sentences + add some leeway
                LIMIT story_chunk_size * 15
            ) AS stories_and_sentences

        )
        RETURNING story_sentences_nonpartitioned.*

    ),

    deduplicated_rows AS (

        -- Deduplicate sentences: nonpartitioned table has weird duplicates,
        -- and the new index insists on (stories_id, sentence_number)
        -- uniqueness (which is a logical assumption to make)
        SELECT DISTINCT ON (stories_id, sentence_number) *
        FROM deleted_rows

        -- Assume that the sentence with the biggest story_sentences_id is the
        -- newest one and so is the one that we want
        ORDER BY stories_id, sentence_number, story_sentences_nonpartitioned_id DESC

    )

    -- INSERT into view to hit the partitioning trigger
    INSERT INTO story_sentences (
        story_sentences_id,
        stories_id,
        sentence_number,
        sentence,
        media_id,
        publish_date,
        db_row_last_updated,
        language,
        is_dup
    )
    SELECT
        story_sentences_nonpartitioned_id,
        stories_id,
        sentence_number,
        sentence,
        media_id,
        publish_date,
        db_row_last_updated,
        language,
        is_dup
    FROM deduplicated_rows;

    GET DIAGNOSTICS copied_sentence_count = ROW_COUNT;

    RAISE NOTICE 'Copied % sentences to the partitioned table.', copied_sentence_count;

END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4670;

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

