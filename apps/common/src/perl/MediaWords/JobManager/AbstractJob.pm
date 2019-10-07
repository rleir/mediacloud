package MediaWords::JobManager::AbstractJob;

#
# Superclass of all Media Cloud jobs
#

use strict;
use warnings;

use Moose::Role;
with 'MediaWords::JobManager::Job';

use MediaWords::CommonLibs;

use Readonly;

use MediaWords::DB;
use MediaWords::DB::Locks;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::Config::Common;
use MediaWords::JobManager::Broker::RabbitMQ;

# (static) Return broker used the job manager
sub broker()
{
    my $rabbitmq_config = MediaWords::Util::Config::Common::rabbitmq();

    my $job_broker = MediaWords::JobManager::Broker::RabbitMQ->new(
        hostname => $rabbitmq_config->hostname(),
        port     => $rabbitmq_config->port(),
        username => $rabbitmq_config->username(),
        password => $rabbitmq_config->password(),
        vhost    => $rabbitmq_config->vhost(),
        timeout  => $rabbitmq_config->timeout(),
    );

    unless ( $job_broker )
    {
        LOGCONFESS "No supported job broker is configured.";
    }

    return $job_broker;
}

# define this in the sub class to make it so that only one job can run for each distinct value of the
# given $arg.  For instance, set this to 'topics_id' to make sure that only one MineTopic job can be running
# at a given time for a given topics_id.
sub get_run_lock_arg()
{
    return undef;
}

# return the lock type from mediawords.db.locks to use for run once locking.  default to the class name.
sub get_run_lock_type
{
    my ( $class_object_or_class_name ) = @_;

    if ( ref( $class_object_or_class_name ) ) {
        # Class / object
        return ref( $class_object_or_class_name );
    } else {
        # Simple string
        return $class_object_or_class_name;
    }
}

sub _job_is_already_running($$;$)
{
    my ( $self_or_class, $db, $args ) = @_;

    # if a job for a run locked class is already running, exit without doinig anything.
    if ( my $run_lock_arg = $self_or_class->get_run_lock_arg() )
    {
        my $lock_type = $self_or_class->get_run_lock_type();
        unless ( MediaWords::DB::Locks::get_session_lock( $db, $lock_type, $args->{ $run_lock_arg }, 0 ) )
        {
            return 1;
        }
    }

    return 0;
}

# set job state to $STATE_RUNNING, call run(), either catch any errors and set state to $STATE_ERROR and save
# the error or set state to $STATE_COMPLETED
sub __run($;$$)
{
    my ( $class, $args, $skip_testing_for_lock ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    unless ( $skip_testing_for_lock ) {
        if ( $class->_job_is_already_running( $db, $args ) ) {
            my $run_lock_arg = $class->get_run_lock_arg();
            WARN( "Stateless job with $run_lock_arg = $args->{ $run_lock_arg } is already running.  Exiting." );
            return;
        }
    }

    return $class->run( $args );
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
