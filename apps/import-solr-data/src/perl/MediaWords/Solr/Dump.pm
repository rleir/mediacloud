package MediaWords::Solr::Dump;

=head1 NAME

MediaWords::Solr::Dump - import story_sentences from postgres into solr

=head1 SYNOPSIS

    # import updates stories into solr
    import_data( $db );


=head1 DESCRIPTION

This module implements the functionality to import data from postgres into solr.

This module just dumbly pulls stories from the solr_import_stories queue.  There are triggers postrgres that
automatically add entries to that table whenever the stories or stories_tags_map table are changed.

Stories are imported in chunks of up to mediawords.yml->mediawords->solr->max_queued_stories (default 100k).

This module has been carefully tuned to optimize performance.  Make sure you test the performance impacts of any
changes you make to the module.

=back

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use JSON::XS;
use Data::Dumper;
use Digest::MD5;
use Encode;
use FileHandle;
use List::MoreUtils qw/natatime/;
use List::Util;
use Parallel::ForkManager;
use Readonly;
use URI;

require bytes;    # do not override length() and such

use MediaWords::DB;
use MediaWords::Util::Config::SolrImport;
use MediaWords::Util::Paths;
use MediaWords::Util::Web;
use MediaWords::Solr;
use MediaWords::Solr::Request;

# order and names of fields exported to and imported from csv
Readonly my @SOLR_FIELDS => qw/stories_id media_id publish_date publish_day publish_week publish_month publish_year
  text title language processed_stories_id tags_id_stories timespans_id/;

# how many sentences to fetch at a time from the postgres query
Readonly my $FETCH_BLOCK_SIZE => 100;

# default stories queue table
Readonly my $DEFAULT_STORIES_QUEUE_TABLE => 'solr_import_stories';

# default time sleep when there are less than MIN_STORIES_TO_PROCESS:
Readonly my $DEFAULT_THROTTLE => 60;

# if there are fewer stories than this, sleep
Readonly my $MIN_STORIES_TO_PROCESS => 1000;

# mark date before generating dump for storing in solr_imports after successful import
my $_import_date;

# options
my $_stories_queue_table;

# keep track of the max stories_id from the last time we queried the queue table so that we don't have to
# page through a ton of dead rows when importing a big queue table
my $_last_max_queue_stories_id;

=head2 FUNCTIONS

=cut

# return the $_stories_queue_table, which is set by the queue_table option of import_data()
sub _get_stories_queue_table
{
    return $_stories_queue_table;
}

# add enough stories from the stories queue table to the delta_import_stories table that there are up to
# _get_maxed_queued_stories in delta_import_stories for each solr_import
sub _add_stories_to_import
{
    my ( $db, $full ) = @_;

    my $max_queued_stories = MediaWords::Util::Config::SolrImport::max_queued_stories();

    my $stories_queue_table = _get_stories_queue_table();

    # first import any stories from snapshotted topics so that those snapshots become searchable ASAP.
    # do this as a separate query because I couldn't figure out a single query that resulted in a reasonable
    # postgres query plan given a very large stories queue table
    my $num_queued_stories = 0;
    if ( !$full )
    {
        my $num_queued_stories = $db->query(
            <<"SQL",
            INSERT INTO delta_import_stories (stories_id)
                SELECT sies.stories_id
                FROM $stories_queue_table sies
                    join snap.stories ss using ( stories_id )
                    join snapshots s on ( ss.snapshots_id = s.snapshots_id and not s.searchable )
                ORDER BY sies.stories_id
                LIMIT ?
SQL
            $max_queued_stories
        )->rows;
    }

    INFO "added $num_queued_stories topic stories to the import";

    $max_queued_stories -= $num_queued_stories;

    # by default, query for all stories and work from biggest stories_id to get latest stories first
    my $min_stories_id = 0;
    my $sort_order     = 'desc';

    # if we are doing a full import, work from the smallest stories_id up and
    # keep track of last max queued id so that we can search for only stories
    # greater than that id below.  otherwise, the index scan from the query has
    # to fetch all of the previously deleted rows from the heap and turn an
    # instant query into a 10 second query after a couple million story imports
    if ( $full && $_last_max_queue_stories_id )
    {
        $min_stories_id = $_last_max_queue_stories_id;
        $sort_order     = 'asc';
    }

    # order by stories_id so that we will tend to get story_sentences in chunked pages as much as possible; just using
    # random stories_ids for collections of old stories (for instance queued to the stories queue table from a
    # media tag update) can make this query a couple orders of magnitude slower
    $num_queued_stories += $db->query(
        <<"SQL",
        INSERT INTO delta_import_stories (stories_id)
            SELECT stories_id
            FROM $stories_queue_table s
            WHERE stories_id > ?
            ORDER BY stories_id desc
            LIMIT ?
SQL
        $min_stories_id,
        $max_queued_stories
    )->rows;

    if ( $num_queued_stories > 0 )
    {
        ( $_last_max_queue_stories_id ) = $db->query( "select max( stories_id ) from delta_import_stories" )->flat();

        my $stories_queue_table = _get_stories_queue_table();

        # remove the schema if present
        my $relname = _get_stories_queue_table();
        $relname =~ s/.*\.//;

        # use pg_class estimate to avoid expensive count(*) query
        my ( $total_queued_stories ) = $db->query( <<SQL, $relname )->flat;
select reltuples::bigint from pg_class where relname = ?
SQL

        INFO "added $num_queued_stories out of about $total_queued_stories queued stories to the import";
    }

}

# query for stories to import, including concatenated sentences as story text and metadata joined in from other tables.
# return a hash in the form { json => $json_of_stories, stories_ids => $list_of_stories_ids }
sub _get_stories_json_from_db_single
{
    my ( $db, $stories_ids ) = @_;

    # query in blocks of $FETCH_BLOCK_SIZE stories to encourage postgres to generate sane query plans.

    my $all_stories = [];

    my $fetch_stories_ids = [ @{ $stories_ids } ];

    INFO( "fetching stories from postgres (" . scalar( @{ $fetch_stories_ids } ) . " remaining)" );

    while ( @{ $fetch_stories_ids } )
    {
        my $block_stories_ids = [];
        for my $i ( 1 .. $FETCH_BLOCK_SIZE )
        {
            if ( my $stories_id = pop( @{ $fetch_stories_ids } ) )
            {
                push( @{ $block_stories_ids }, $stories_id );
            }
        }

        my $block_stories_ids_list = join( ',', @{ $block_stories_ids } );

        TRACE( "fetching stories ids: $block_stories_ids_list" );
        $db->query( "SET LOCAL client_min_messages=warning" );

        my $stories = $db->query( <<SQL )->hashes();
with _block_processed_stories as (
    select max( processed_stories_id ) processed_stories_id, stories_id
        from processed_stories
        where stories_id in ( $block_stories_ids_list )
        group by stories_id
),

_timespan_stories as  (
    select  stories_id, array_agg( distinct timespans_id ) timespans_id
        from snap.story_link_counts slc
            join _block_processed_stories using ( stories_id )
        where
            slc.stories_id in ( $block_stories_ids_list )
        group by stories_id
),

_tag_stories as  (
    select stories_id, array_agg( distinct tags_id ) tags_id_stories
        from stories_tags_map stm
            join _block_processed_stories bps using ( stories_id )
        where
            stm.stories_id in ( $block_stories_ids_list )
        group by stories_id
),

_import_stories as (
    select
        s.stories_id,
        s.media_id,
        to_char( date_trunc( 'minute', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_date,
        to_char( date_trunc( 'day', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_day,
        to_char( date_trunc( 'week', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_week,
        to_char( date_trunc( 'month', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_month,
        to_char( date_trunc( 'year', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_year,
        string_agg( ss.sentence, ' ' order by ss.sentence_number ) as text,
        s.title,
        s.language,
        min( ps.processed_stories_id ) processed_stories_id,
        min( stm.tags_id_stories ) tags_id_stories,
        min( slc.timespans_id ) timespans_id

    from _block_processed_stories ps
        join story_sentences ss using ( stories_id )
        join stories s using ( stories_id )
        left join _tag_stories stm using ( stories_id )
        left join _timespan_stories slc using ( stories_id )

    where
        s.stories_id in ( $block_stories_ids_list )
    group by s.stories_id
)


select * from _import_stories
SQL

        TRACE( "found " . scalar( @{ $stories } ) . " stories from " . scalar( @{ $block_stories_ids } ) . " ids" );

        push( @{ $all_stories }, @{ $stories } );
    }

    my $all_stories_ids = [ map { $_->{ stories_id } } @{ $all_stories } ];
    my $stories_json = JSON::XS::encode_json( $all_stories );

    #DEBUG( $stories_json );

    return { stories_ids => $all_stories_ids, json => $stories_json };
}

# get stories_json for import from db and import the resulting stories into solr.  return the list of stories_ids
# imported.
sub _import_stories_from_db_single($$)
{
    my ( $db, $stories_ids ) = @_;

    # if this is called as a threaded function, $db will be undef so that it can be recreated
    $db //= MediaWords::DB::connect_to_db();

    my $json = _get_stories_json_from_db_single( $db, $stories_ids );

    my ( $import_url, $import_params ) = _get_import_url_params();

    DEBUG "importing " . scalar( @{ $json->{ stories_ids } } ) . " stories into solr ...";
    eval { MediaWords::Solr::Request::solr_request( $import_url, $import_params, $json->{ json }, 'application/json' ); };
    die( "error importing to solr: $@" ) if ( $@ );

    TRACE( "committing solr index changes ..." );
    MediaWords::Solr::Request::solr_request( 'update', { 'commit' => 'true' } );

    _delete_stories_from_import_queue( $db, $stories_ids );

    return $json->{ stories_ids };
}

# this function does the meat of the work of querying story data from postgres and importing that data to solr
sub _import_stories($$)
{
    my ( $db, $jobs ) = @_;

    my $stories_ids = $db->query( "select distinct stories_id from delta_import_stories" )->flat;

    if ( $jobs == 1 )
    {
        _import_stories_from_db_single( $db, $stories_ids );
        return;
    }

    my $pm = Parallel::ForkManager->new( $jobs );

    my $stories_per_job = int( scalar( @{ $stories_ids } ) / $jobs ) + 1;
    my $iter = natatime( $stories_per_job, @{ $stories_ids } );
    while ( my @job_stories_ids = $iter->() )
    {
        $pm->start() && next;
        _import_stories_from_db_single( undef, \@job_stories_ids );
        $pm->finish();
    }

    $pm->wait_all_children();

    return;
}

# create the delta_import_stories temporary table and fill it from the stories_queue_table
sub _create_delta_import_stories($$)
{
    my ( $db, $full ) = @_;

    $db->query( "drop table if exists delta_import_stories" );

    $db->query( "create temporary table delta_import_stories ( stories_id int )" );

    _add_stories_to_import( $db, $full );

    my $stories_ids = $db->query( "select stories_id from delta_import_stories" )->flat();

    return $stories_ids;
}

# get the solr url and parameters to send csv data to
sub _get_import_url_params
{
    my $url_params = {
        'commit'    => 'false',
        'overwrite' => 'false',
    };

    return ( 'update', $url_params );
}

# store in memory the current date according to postgres
sub _mark_import_date
{
    my ( $db ) = @_;

    ( $_import_date ) = $db->query( "select now()" )->flat;
}

# store the date marked by mark_import_date in solr_imports
sub _save_import_date
{
    my ( $db, $delta, $stories_ids ) = @_;

    die( "import date has not been marked" ) unless ( $_import_date );

    my $full_import = $delta ? 'f' : 't';
    $db->query( <<SQL, $_import_date, $full_import, scalar( @{ $stories_ids } ) );
insert into solr_imports( import_date, full_import, num_stories ) values ( ?, ?, ? )
SQL

}

# save log of all stories imported into solr
sub _save_import_log
{
    my ( $db, $stories_ids ) = @_;

    die( "import date has not been marked" ) unless ( $_import_date );

    $db->begin;
    for my $stories_id ( @{ $stories_ids } )
    {
        $db->query( <<SQL, $stories_id, $_import_date );
insert into solr_imported_stories ( stories_id, import_date ) values ( ?, ? )
SQL
    }
    $db->commit;
}

# given a list of stories_ids, return a stories_id:... solr query that replaces individual ids with ranges where
# possible.  Avoids >1MB queries that consists of lists of >100k stories_ids.
sub _get_stories_id_solr_query
{
    my ( $ids ) = @_;

    die( "empty stories_ids" ) unless ( @{ $ids } );

    $ids = [ sort { $a <=> $b } @{ $ids } ];

    my $singletons = [ -2 ];
    my $ranges = [ [ -2 ] ];
    for my $id ( @{ $ids } )
    {
        if ( $id == ( $ranges->[ -1 ]->[ -1 ] + 1 ) )
        {
            push( @{ $ranges->[ -1 ] }, $id );
        }
        elsif ( $id == ( $singletons->[ -1 ] + 1 ) )
        {
            push( @{ $ranges }, [ pop( @{ $singletons } ), $id ] );
        }
        else
        {
            push( @{ $singletons }, $id );
        }
    }

    shift( @{ $singletons } );
    shift( @{ $ranges } );

    my $long_ranges = [];
    for my $range ( @{ $ranges } )
    {
        if ( scalar( @{ $range } ) > 2 )
        {
            push( @{ $long_ranges }, $range );
        }
        else
        {
            push( @{ $singletons }, @{ $range } );
        }
    }

    my $queries = [];

    push( @{ $queries }, map { "stories_id:[$_->[ 0 ] TO $_->[ -1 ]]" } @{ $long_ranges } );
    push( @{ $queries }, 'stories_id:(' . join( ' ', @{ $singletons } ) . ')' ) if ( @{ $singletons } );

    my $query = join( ' ', @{ $queries } );

    return $query;
}

# delete the stories in the stories queue table
sub _delete_queued_stories($)
{
    my ( $db ) = @_;

    my $stories_ids = $db->query( "select stories_id from delta_import_stories" )->flat;

    return 1 unless ( $stories_ids && scalar @{ $stories_ids } );

    $stories_ids = [ sort { $a <=> $b } @{ $stories_ids } ];

    my $max_chunk_size = 5000;

    while ( @{ $stories_ids } )
    {
        my $chunk_ids = [];
        my $chunk_size = List::Util::min( $max_chunk_size, scalar( @{ $stories_ids } ) );
        map { push( @{ $chunk_ids }, shift( @{ $stories_ids } ) ) } ( 1 .. $chunk_size );

        INFO "deleting chunk: " . scalar( @{ $chunk_ids } ) . " stories ...";

        my $stories_id_query = _get_stories_id_solr_query( $chunk_ids );

        my $delete_query = "<delete><query>$stories_id_query</query></delete>";

        eval { MediaWords::Solr::Request::solr_request( 'update', undef, $delete_query, 'application/xml' ); };
        if ( $@ )
        {
            my $error = $@;
            WARN "Error while deleting stories: $error";
            return 0;
        }
    }

    return 1;
}

# delete stories that have just been imported from the media import queue
sub _delete_stories_from_import_queue
{
    my ( $db, $stories_ids ) = @_;

    TRACE( "deleting " . scalar( @{ $stories_ids } ) . " stories from import queue ..." );

    my $stories_queue_table = _get_stories_queue_table();

    return unless ( @{ $stories_ids } );

    my $stories_ids_list = join( ',', @{ $stories_ids } );

    $db->query(
        <<SQL
        DELETE FROM $stories_queue_table
        WHERE stories_id IN ($stories_ids_list)
SQL
    );
}

# guess whether this might be a production solr instance by just looking at the size.  this is useful so that we can
# cowardly refuse to delete all content from something that may be a production instance.
sub _maybe_production_solr
{
    my ( $db ) = @_;

    my $num_sentences = MediaWords::Solr::get_num_found( $db, { q => '*:*', rows => 0 } );

    die( "Unable to query solr for number of sentences" ) unless ( defined( $num_sentences ) );

    return ( $num_sentences > 100_000_000 );
}

# set snapshots.searchable to true for all snapshots that are currently false and
# have no stories in the stories queue table
sub _update_snapshot_solr_status
{
    my ( $db ) = @_;

    my $stories_queue_table = _get_stories_queue_table();

    # the combination the searchable clause and the not exists which stops after the first hit should
    # make this quite fast
    $db->query( <<SQL );
update snapshots s set searchable = true
    where
        searchable = false and
        not exists (
            select 1
                from timespans t
                    join snap.story_link_counts slc using ( timespans_id )
                    join $stories_queue_table sies using ( stories_id )
                where t.snapshots_id = s.snapshots_id
        )
SQL
}

=head2 import_data( $options )

Import stories from postgres to solr.

Options:
* update -- delete each story from solr before importing it (default true)
* empty_queue -- keep running until stories queue table is entirely empty (default false)
* throttle -- sleep this number of seconds between each block of stories (default 60)
* full -- shortcut for: update=false, empty_queue=true, throttle=1; assume and optimize for static queue
* stories_queue_table -- table from which to pull stories to import (default solr_import_stories)
* skip_logging -- skip logging the import into the solr_import_stories or solr_imports tables (default=false)

The import will run in blocks of "max_queued_stories" at a time. The function
will keep trying to find stories to import.  If there are less than
$MIN_STORIES_TO_PROCESS stories to import, it will sleep for $throttle seconds
and then look for more stories.
=cut

sub import_data($;$)
{
    my ( $db, $options ) = @_;

    $options //= {};

    my $full = $options->{ full } // 0;
    my $stories_queue_table = $options->{ stories_queue_table } // $DEFAULT_STORIES_QUEUE_TABLE;

    if ( $full )
    {
        $options->{ update }      //= 0;
        $options->{ empty_queue } //= 1;
        $options->{ throttle }    //= 1;
    }

    if ( $stories_queue_table ne $DEFAULT_STORIES_QUEUE_TABLE )
    {
        $options->{ skip_logging } //= 1;
        $options->{ empty_queue }  //= 1;
        $options->{ update }       //= 0;
    }

    my $jobs = MediaWords::Util::Config::SolrImport::jobs();

    my $update       = $options->{ update }       // 1;
    my $empty_queue  = $options->{ empty_queue }  // 0;
    my $throttle     = $options->{ throttle }     // $DEFAULT_THROTTLE;
    my $skip_logging = $options->{ skip_logging } // 0;
    my $daemon = $options->{ daemon } // 0;

    $_stories_queue_table       = $stories_queue_table;
    $_last_max_queue_stories_id = 0;

    my $i = 0;

    while ()
    {
        my $start_time = time();
        _mark_import_date( $db );

        my $stories_ids = _create_delta_import_stories( $db, $full );

        my $num_stories = scalar( @{ $stories_ids } );
        if ( $num_stories < $MIN_STORIES_TO_PROCESS )
        {
            if ( $daemon )
            {
                INFO( "too few stories ($num_stories/$MIN_STORIES_TO_PROCESS). sleeping $throttle seconds ..." );
                sleep( $throttle );
                next;
            }
            elsif ( !$num_stories || !$empty_queue )
            {
                INFO( "too few stories ($num_stories/$MIN_STORIES_TO_PROCESS). quitting." );
                last;
            }
        }

        if ( $update )
        {
            INFO "deleting updated stories ...";
            _delete_queued_stories( $db ) || die( "delete stories failed." );
        }

        _import_stories( $db, $jobs );

        # have to reconnect becaue import_stories may have forked, ruining existing db handles
        $db = MediaWords::DB::connect_to_db() if ( $jobs > 1 );

        if ( !$skip_logging )
        {
            _save_import_date( $db, !$full, $stories_ids );
            _save_import_log( $db, $stories_ids );
        }

        if ( !$skip_logging )
        {
            _update_snapshot_solr_status( $db );
        }

        my $import_time = time() - $start_time;
        INFO( "imported $num_stories stories in $import_time seconds" );
    }
}

1;
