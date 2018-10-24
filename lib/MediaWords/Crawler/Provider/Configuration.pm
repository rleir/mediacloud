package MediaWords::Crawler::Provider::Configuration;

# Provider's configuration

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

Readonly my $DEFAULT_THROTTLE => 30;
Readonly my $DEFAULT_PENDING_CHECK_INTERVAL => 600;
Readonly my $DEFAULT_SLEEP_INTERVAL => 10;

sub new($;$)
{
    my ( $class, $args ) = @_;

    my $self = {};
    bless( $self, $class );

    $args //= {};

    $self->{ _throttle } = $args->{ throttle } // int($DEFAULT_THROTTLE);
    $self->{ _pending_check_interval } = $args->{ pending_check_interval } // int( $DEFAULT_PENDING_CHECK_INTERVAL );
    $self->{ _sleep_interval } = $args->{ sleep_interval } // int( $DEFAULT_SLEEP_INTERVAL );

    return $self;
}

# Throttle each host to one request every this many seconds.
sub throttle($)
{
    return $self->{ _throttle };
}

# Interval to check downloads for pending downloads to add to queue
sub pending_check_interval($)
{
    return $self->{ _pending_check_interval };
}

# Sleep for up to this many seconds each time the provider provides 0 downloads
sub sleep_interval($)
{
	return $self->{ _sleep_interval };
}

1;
