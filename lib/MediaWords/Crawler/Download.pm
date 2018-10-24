package MediaWords::Crawler::Download;

#
# Download fetcher
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Crawler::Download::Content;
use MediaWords::Crawler::Download::Feed::Syndicated;
use MediaWords::Crawler::Download::Feed::WebPage;
use MediaWords::Crawler::Download::Feed::Univision;

use MediaWords::Util::Timing;


sub handler_for_download($$)
{
    my ( $db, $download ) = @_;

    my $downloads_id  = $download->{ downloads_id };
    my $download_type = $download->{ type };

    my $handler;
    if ( $download_type eq 'feed' )
    {
        my $feeds_id  = $download->{ feeds_id };
        my $feed      = $db->find_by_id( 'feeds', $feeds_id );
        my $feed_type = $feed->{ type };

        if ( $feed_type eq 'syndicated' )
        {
            $handler = MediaWords::Crawler::Download::Feed::Syndicated->new();
        }
        elsif ( $feed_type eq 'web_page' )
        {
            $handler = MediaWords::Crawler::Download::Feed::WebPage->new();
        }
        elsif ( $feed_type eq 'univision' )
        {
            $handler = MediaWords::Crawler::Download::Feed::Univision->new();
        }
        else
        {
            LOGCONFESS "Unknown feed type '$feed_type' for feed $feeds_id, download $downloads_id";
        }

    }
    elsif ( $download_type eq 'content' )
    {
        $handler = MediaWords::Crawler::Download::Content->new();
    }
    else
    {
        LOGCONFESS "Unknown download type '$download_type' for download $downloads_id";
    }

    return $handler;
}

sub fetch_and_handle_download($$$)
{
    my ( $db, $download, $handler ) = @_;

    unless ( $download )
    {
        LOGCONFESS "Download is unset.";
    }

    my $downloads_id = $download->{ downloads_id };
    unless ( $downloads_id ) {
        LOGCONFESS "Download's ID is unset.";
    }

    my $url = $download->{ url };
    unless ( $url ) {
        LOGCONFESS "Download's URL for download $downloads_id is unset.";
    }

    DEBUG "Fetching download $downloads_id from $url ...";

    my $start_fetch_time = MediaWords::Util::Timing::start_time( 'fetch' );
    my $response = $handler->fetch_download( $db, $download );
    MediaWords::Util::Timing::stop_time( 'fetch', $start_fetch_time );

    my $start_handle_time = MediaWords::Util::Timing::start_time( 'handle' );
    eval { $handler->handle_response( $db, $download, $response ); };
    if ( $@ )
    {
        my $error_message = $@;
        LOGDIE "Error in handle_response() for download $downloads_id from URL $url: $error_message";
    }
    MediaWords::Util::Timing::stop_time( 'handle', $start_handle_time );

    DEBUG "Done fetching download $downloads_id from URL $url";
}

1;
