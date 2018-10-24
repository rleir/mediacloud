package MediaWords::Job::FetchDownload;

#
# Fetch a crawler download
#
# Start this worker script by running:
#
# ./script/run_in_env.sh mjm_worker.pl lib/MediaWords/Job/FetchDownload.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Crawler::Download;

use Readonly;

sub run($$)
{
    my ( $self, $args ) = @_;

    my $downloads_id = $args->{ downloads_id };
    unless ( $downloads_id )
    {
        LOGDIE "downloads_id is unset.";
    }

    my $db = MediaWords::DB::connect_to_db();

    my $download = $db->find_by_id( 'downloads', $downloads_id );
    unless ( $download ) {
        LOGDIE "Download with downloads_id = $downloads_id was not found.";
    }

    eval {

        my $handler = MediaWords::Crawler::Download::handler_for_download( $db, $download );
        MediaWords::Crawler::Download::fetch_and_handle_download( $db, $download, $handler );

    };
    if ( $@ ) {
        my $error_message = $@;

        WARN "Unable to fetch download $downloads_id: $error_message";

        if ( !grep { $_ eq $download->{ state } } ( 'fetching', 'queued' ) )
        {
            $download->{ state }         = 'error';
            $download->{ error_message } = $error_message;
            $db->update_by_id( 'downloads', $downloads_id, $download );
        }
    }

    return 1;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
