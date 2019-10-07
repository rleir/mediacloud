--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4521 and 4522.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4521, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4522, import this SQL file:
--
--     psql mediacloud < mediawords-4521-4522.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


ALTER TABLE bitly_processing_results
    ADD COLUMN collect_date TIMESTAMP NULL DEFAULT NOW();

-- Set to NULL for all the current data because we don't know the exact collection date
UPDATE bitly_processing_results
    SET collect_date = NULL;


--
-- Bit.ly total story click counts
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE bitly_clicks_total (
    bitly_clicks_id   BIGSERIAL NOT NULL,
    stories_id        INT       NOT NULL,

    click_count       INT       NOT NULL
);

-- Automatic Bit.ly total click count partitioning to stories_id chunks of 1m rows
CREATE OR REPLACE FUNCTION bitly_clicks_total_partition_by_stories_id_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_total_000001")
    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    chunk_size CONSTANT INT := 1000000;           -- 1m stories in a chunk
    to_char_format CONSTANT TEXT := '000000';     -- Up to 1m of chunks, suffixed as "_000001", ..., "_999999"

    stories_id_chunk_number INT;  -- millions part of stories_id (e.g. 30 for stories_id = 30,000,000)
    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    SELECT NEW.stories_id / chunk_size INTO stories_id_chunk_number;
    SELECT 'bitly_clicks_total_' || trim(leading ' ' from to_char(stories_id_chunk_number, to_char_format))
        INTO target_table_name;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables 
        WHERE table_schema = current_schema()
          AND table_name = target_table_name
    ) THEN

        SELECT (NEW.stories_id / chunk_size) * chunk_size INTO stories_id_start;
        SELECT ((NEW.stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

        EXECUTE '
            CREATE TABLE ' || target_table_name || ' (

                -- Primary key
                CONSTRAINT ' || target_table_name || '_pkey
                    PRIMARY KEY (bitly_clicks_id),

                -- Partition by stories_id
                CONSTRAINT ' || target_table_name || '_stories_id CHECK (
                    stories_id >= ''' || stories_id_start || '''
                AND stories_id <  ''' || stories_id_end   || '''),

                -- Foreign key to stories.stories_id
                CONSTRAINT ' || target_table_name || '_stories_id_fkey
                    FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL,

                -- Unique duplets
                CONSTRAINT ' || target_table_name || '_stories_id_unique
                    UNIQUE (stories_id)

            ) INHERITS (bitly_clicks_total);
        ';

        -- Update owner
        SELECT u.usename AS owner
        FROM information_schema.tables AS t
            JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
            JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
        WHERE t.table_name = 'bitly_clicks_total'
          AND t.table_schema = 'public'
        INTO target_table_owner;

        EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

    END IF;

    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*;
    ' USING NEW;

    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER bitly_clicks_total_partition_by_stories_id_insert_trigger
    BEFORE INSERT ON bitly_clicks_total
    FOR EACH ROW EXECUTE PROCEDURE bitly_clicks_total_partition_by_stories_id_insert_trigger();


-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE OR REPLACE FUNCTION upsert_bitly_clicks_total (
    param_stories_id INT,
    param_click_count INT
) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE bitly_clicks_total
            SET click_count = param_click_count
            WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_clicks_total (stories_id, click_count)
            VALUES (param_stories_id, param_click_count);
            RETURN;
        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;


--
-- Bit.ly daily story click counts
--

-- "Master" table (no indexes, no foreign keys as they'll be ineffective)
CREATE TABLE bitly_clicks_daily (
    bitly_clicks_id   BIGSERIAL NOT NULL,
    stories_id        INT       NOT NULL,

    day               DATE      NOT NULL,
    click_count       INT       NOT NULL
);

-- Automatic Bit.ly daily click count partitioning to stories_id chunks of 1m rows
CREATE OR REPLACE FUNCTION bitly_clicks_daily_partition_by_stories_id_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_daily_000001")
    target_table_owner TEXT;      -- partition table owner (e.g. "mediaclouduser")

    chunk_size CONSTANT INT := 1000000;           -- 1m stories in a chunk
    to_char_format CONSTANT TEXT := '000000';     -- Up to 1m of chunks, suffixed as "_000001", ..., "_999999"

    stories_id_chunk_number INT;  -- millions part of stories_id (e.g. 30 for stories_id = 30,000,000)
    stories_id_start INT;         -- stories_id chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_end INT;           -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
BEGIN

    SELECT NEW.stories_id / chunk_size INTO stories_id_chunk_number;
    SELECT 'bitly_clicks_daily_' || trim(leading ' ' from to_char(stories_id_chunk_number, to_char_format))
        INTO target_table_name;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables 
        WHERE table_schema = current_schema()
          AND table_name = target_table_name
    ) THEN

        SELECT (NEW.stories_id / chunk_size) * chunk_size INTO stories_id_start;
        SELECT ((NEW.stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

        EXECUTE '
            CREATE TABLE ' || target_table_name || ' (

                -- Primary key
                CONSTRAINT ' || target_table_name || '_pkey
                    PRIMARY KEY (bitly_clicks_id),

                -- Partition by stories_id
                CONSTRAINT ' || target_table_name || '_stories_id CHECK (
                    stories_id >= ''' || stories_id_start || '''
                AND stories_id <  ''' || stories_id_end   || '''),

                -- Foreign key to stories.stories_id
                CONSTRAINT ' || target_table_name || '_stories_id_fkey
                    FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL,

                -- Unique duplets
                CONSTRAINT ' || target_table_name || '_stories_id_day_unique
                    UNIQUE (stories_id, day)

            ) INHERITS (bitly_clicks_daily);
        ';

        -- Update owner
        SELECT u.usename AS owner
        FROM information_schema.tables AS t
            JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
            JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
        WHERE t.table_name = 'bitly_clicks_daily'
          AND t.table_schema = 'public'
        INTO target_table_owner;

        EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

    END IF;

    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*;
    ' USING NEW;

    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER bitly_clicks_daily_partition_by_stories_id_insert_trigger
    BEFORE INSERT ON bitly_clicks_daily
    FOR EACH ROW EXECUTE PROCEDURE bitly_clicks_daily_partition_by_stories_id_insert_trigger();


-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE OR REPLACE FUNCTION upsert_bitly_clicks_daily (
    param_stories_id INT,
    param_day DATE,
    param_click_count INT
) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE bitly_clicks_daily
            SET click_count = param_click_count
            WHERE stories_id = param_stories_id
              AND day = param_day;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_clicks_daily (stories_id, day, click_count)
            VALUES (param_stories_id, param_day, param_click_count);
            RETURN;
        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;


--
-- Bit.ly processing schedule
--
CREATE TABLE bitly_processing_schedule (
    bitly_processing_schedule_id    BIGSERIAL NOT NULL,
    stories_id                      INT       NOT NULL REFERENCES stories (stories_id) ON DELETE CASCADE,
    fetch_at                        TIMESTAMP NOT NULL
);

CREATE INDEX bitly_processing_schedule_stories_id
    ON bitly_processing_schedule (stories_id);
CREATE INDEX bitly_processing_schedule_fetch_at
    ON bitly_processing_schedule (fetch_at);


-- Helper to return a number of stories for which we don't have Bit.ly statistics yet
DROP FUNCTION num_controversy_stories_without_bitly_statistics(INT);
CREATE FUNCTION num_controversy_stories_without_bitly_statistics (param_controversies_id INT) RETURNS INT AS
$$
DECLARE
    controversy_exists BOOL;
    num_stories_without_bitly_statistics INT;
BEGIN

    SELECT 1 INTO controversy_exists
    FROM controversies
    WHERE controversies_id = param_controversies_id
      AND process_with_bitly = 't';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Controversy % does not exist or is not set up for Bit.ly processing.', param_controversies_id;
        RETURN FALSE;
    END IF;

    SELECT COUNT(stories_id) INTO num_stories_without_bitly_statistics
    FROM controversy_stories
    WHERE controversies_id = param_controversies_id
      AND stories_id NOT IN (
        SELECT stories_id
        FROM bitly_clicks_total
    )
    GROUP BY controversies_id;
    IF NOT FOUND THEN
        num_stories_without_bitly_statistics := 0;
    END IF;

    RETURN num_stories_without_bitly_statistics;
END;
$$
LANGUAGE plpgsql;


-- Migrate old data to the new partitioned table infrastructure and drop it afterwards
-- (might take up ~6 minutes or so)
DROP FUNCTION IF EXISTS upsert_story_bitly_statistics(INT, INT);
DROP FUNCTION IF EXISTS upsert_story_bitly_statistics(INT, INT, INT);

INSERT INTO bitly_clicks_total (stories_id, click_count)
    SELECT stories_id, bitly_click_count
    FROM story_bitly_statistics;

DROP TABLE story_bitly_statistics;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4522;

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
