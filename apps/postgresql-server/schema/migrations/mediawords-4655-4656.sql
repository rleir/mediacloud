--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4655 and 4656.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4655, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4656, import this SQL file:
--
--     psql mediacloud < mediawords-4655-4656.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

drop trigger ss_insert_story_media_stats on story_sentences;
drop trigger ss_update_story_media_stats on story_sentences;
drop trigger story_delete_ss_media_stats on story_sentences;

drop function insert_ss_media_stats();
drop function update_ss_media_stats();
drop function delete_ss_media_stats();

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4656;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
