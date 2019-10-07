--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4699 and 4700.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4699, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4700, import this SQL file:
--
--     psql mediacloud < mediawords-4699-4700.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP FUNCTION partition_by_stories_id_partition_name(base_table_name TEXT, stories_id INT);

CREATE OR REPLACE FUNCTION partition_name(base_table_name TEXT, chunk_size BIGINT, object_id BIGINT) RETURNS TEXT AS $$
DECLARE

    -- Up to 100 partitions, suffixed as "_00", "_01" ..., "_99"
    -- (having more of them is not feasible)
    to_char_format CONSTANT TEXT := '00';

    -- Partition table name (e.g. "stories_tags_map_01")
    table_name TEXT;

    chunk_number INT;

BEGIN
    SELECT object_id / chunk_size INTO chunk_number;

    SELECT base_table_name || '_' || TRIM(leading ' ' FROM TO_CHAR(chunk_number, to_char_format))
        INTO table_name;

    RETURN table_name;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION partition_by_stories_id_partition_name(base_table_name TEXT, stories_id BIGINT) RETURNS TEXT AS $$
BEGIN

    RETURN partition_name(
        base_table_name := base_table_name,
        chunk_size := partition_by_stories_id_chunk_size(),
        object_id := stories_id
    );

END;
$$
LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION partition_by_stories_id_create_partitions(base_table_name TEXT) RETURNS SETOF TEXT AS
$$
DECLARE
    chunk_size INT;
    max_stories_id INT;
    partition_stories_id INT;

    -- Partition table name (e.g. "stories_tags_map_01")
    target_table_name TEXT;

    -- Partition table owner (e.g. "mediaclouduser")
    target_table_owner TEXT;

    -- "stories_id" chunk lower limit, inclusive (e.g. 30,000,000)
    stories_id_start BIGINT;

    -- stories_id chunk upper limit, exclusive (e.g. 31,000,000)
    stories_id_end BIGINT;
BEGIN

    SELECT partition_by_stories_id_chunk_size() INTO chunk_size;

    -- Create +1 partition for future insertions
    SELECT COALESCE(MAX(stories_id), 0) + chunk_size FROM stories INTO max_stories_id;

    FOR partition_stories_id IN 1..max_stories_id BY chunk_size LOOP
        SELECT partition_by_stories_id_partition_name(
            base_table_name := base_table_name,
            stories_id := partition_stories_id
        ) INTO target_table_name;
        IF table_exists(target_table_name) THEN
            RAISE NOTICE 'Partition "%" for story ID % already exists.', target_table_name, partition_stories_id;
        ELSE
            RAISE NOTICE 'Creating partition "%" for story ID %', target_table_name, partition_stories_id;

            SELECT (partition_stories_id / chunk_size) * chunk_size INTO stories_id_start;
            SELECT ((partition_stories_id / chunk_size) + 1) * chunk_size INTO stories_id_end;

            EXECUTE '
                CREATE TABLE ' || target_table_name || ' (

                    PRIMARY KEY (' || base_table_name || '_id),

                    -- Partition by stories_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id CHECK (
                        stories_id >= ''' || stories_id_start || '''
                    AND stories_id <  ''' || stories_id_end   || '''),

                    -- Foreign key to stories.stories_id
                    CONSTRAINT ' || REPLACE(target_table_name, '.', '_') || '_stories_id_fkey
                        FOREIGN KEY (stories_id) REFERENCES stories (stories_id) MATCH FULL ON DELETE CASCADE

                ) INHERITS (' || base_table_name || ');
            ';

            -- Update owner
            SELECT u.usename AS owner
            FROM information_schema.tables AS t
                JOIN pg_catalog.pg_class AS c ON t.table_name = c.relname
                JOIN pg_catalog.pg_user AS u ON c.relowner = u.usesysid
            WHERE t.table_name = base_table_name
              AND t.table_schema = 'public'
            INTO target_table_owner;

            EXECUTE 'ALTER TABLE ' || target_table_name || ' OWNER TO ' || target_table_owner || ';';

            -- Add created partition name to the list of returned partition names
            RETURN NEXT target_table_name;

        END IF;
    END LOOP;

    RETURN;

END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION feeds_stories_map_partitioned_insert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "feeds_stories_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'feeds_stories_map_partitioned',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION stories_tags_map_partition_upsert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'stories_tags_map',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ON CONFLICT (stories_id, tags_id) DO NOTHING
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION story_sentences_partitioned_insert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT partition_by_stories_id_partition_name(
        base_table_name := 'story_sentences_partitioned',
        stories_id := NEW.stories_id
    ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4700;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
