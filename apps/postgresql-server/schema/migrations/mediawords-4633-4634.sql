--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4633 and 4634.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4633, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4634, import this SQL file:
--
--     psql mediacloud < mediawords-4633-4634.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP FUNCTION story_is_annotatable_with_corenlp(corenlp_stories_id INT);

DROP FUNCTION story_is_annotatable_with_cliff(cliff_stories_id INT);

DROP FUNCTION story_is_annotatable_with_nytlabels(nytlabels_stories_id INT);


CREATE OR REPLACE FUNCTION story_is_english_and_has_sentences(param_stories_id INT) RETURNS boolean AS $$
DECLARE
    story record;
BEGIN

    SELECT stories_id, media_id, language INTO story from stories where stories_id = param_stories_id;

    IF NOT ( story.language = 'en' or story.language is null ) THEN
        RETURN FALSE;

    ELSEIF NOT EXISTS ( SELECT 1 FROM story_sentences WHERE stories_id = param_stories_id ) THEN
        RETURN FALSE;

    END IF;

    RETURN TRUE;

END;
$$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4634;

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

