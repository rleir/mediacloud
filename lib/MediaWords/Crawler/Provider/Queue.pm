package MediaWords::Crawler::Provider::Queue;

# Provide one request at a time a crawler process

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Fcntl qw (O_RDWR O_CREAT O_TRUNC);
use File::Path;
use Data::Dumper;
use MediaWords::DB;
use MediaWords::Util::Config;
use Readonly;

Readonly my $DEBUG_MODE => 0;

sub new
{
    my ( $class ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->{ downloads } = {};

    $self->{ downloads_count } = 0;

    return $self;
}

sub queue_download
{
    my ( $self, $download ) = @_;

    my $media_id = $download->{ _media_id };

    if ( !defined( $media_id ) )
    {
        die( "missing media_id" );
    }

    $self->{ downloads }->{ $media_id }->{ queued } ||= [];
    $self->{ downloads }->{ $media_id }->{ time }   ||= 0;
    $self->{ downloads }->{ $media_id }->{ map }    ||= {};

    my $map = $self->{ downloads }->{ $media_id }->{ map };

    return if ( $map->{ $download->{ downloads_id } } );

    $map->{ $download->{ downloads_id } } = 1;

    my $pending = $self->{ downloads }->{ $media_id }->{ queued };

    if ( $download->{ priority } && ( $download->{ priority } > 0 ) )
    {
        unshift( @{ $pending }, $download );
    }
    else
    {
        push( @{ $pending }, $download );
    }

    $self->{ downloads_count }++;
}

# pop the latest download for the given media_id off the queue
sub pop_download
{
    my ( $self, $media_id ) = @_;
    $self->{ downloads }->{ $media_id }->{ time } = time;

    $self->{ downloads }->{ $media_id }->{ queued } ||= [];

    my $download_serialized = shift( @{ $self->{ downloads }->{ $media_id }->{ queued } } );
    my $download            = $download_serialized;

    if ( $download )
    {

        # this causes a race condition which results in us redownloading a lot of
        # duplicate downloads.  The easiest thing is just to comment this line,
        # with the effect that no download can be redownloaded until the crawler
        # is restarted.  That shouldn't happen in any case unless someone is manually
        # fiddling with download rows in the database. -hal
        #$self->{ downloads }->{ $media_id }->{ map }->{ $download->{ downloads_id } } = 0;
        $self->{ downloads_count }--;
    }

    return $download;
}

# get list of download media_id times in the form of { media_id => $media_id, time => $time }
sub get_download_media_ids
{
    my ( $self ) = @_;

    return [
        map { { media_id => $_, time => $self->{ downloads }->{ $_ }->{ time } } }
          keys( %{ $self->{ downloads } } )
    ];
}

sub _verify_downloads_count
{
    my ( $self ) = @_;

    my $downloads_count_real = 0;

    for my $a ( values( %{ $self->{ downloads } } ) )
    {
        if ( @{ $a->{ queued } } )
        {
            $downloads_count_real += scalar( @{ $a->{ queued } } );
        }
    }

    die "\$downloads_counts is " . $self->{ downloads_count } . " but there are actually $downloads_count_real downloads"
      unless $downloads_count_real == $self->{ downloads_count };
}

# get total number of queued downloads
sub get_downloads_size
{
    my ( $self ) = @_;

    if ( $DEBUG_MODE )
    {
        $self->_verify_downloads_count();
    }

    return $self->{ downloads_count };
}

1;
