package MediaWords::DBI::Auth::User::AbstractUser;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

{
    # Proxy to Python's implementation
    package MediaWords::DBI::Auth::User::AbstractUser::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    import_python_module( __PACKAGE__, 'webapp.auth.user' );

    1;
}

sub new
{
    my ( $class, %args ) = @_;

    my $self = {};
    bless $self, $class;

    unless ( $args{ python_object } )
    {
        LOGCONFESS "Python user object is not set.";
    }

    $self->{ _python_object } = $args{ python_object };

    return $self;
}

sub email($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->email();
}

sub full_name($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->full_name();
}

sub notes($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->notes();
}

sub active($)
{
    my ( $self ) = @_;

    return int( $self->{ _python_object }->active() );
}

sub weekly_requests_limit($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->weekly_requests_limit();
}

sub weekly_requested_items_limit($)
{
    my ( $self ) = @_;

    return $self->{ _python_object }->weekly_requested_items_limit();
}

1;
