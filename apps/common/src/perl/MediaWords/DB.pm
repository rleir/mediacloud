package MediaWords::DB;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB::HandlerProxy;

{

    package MediaWords::DB::PythonConnectToDB;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;    # set PYTHONPATH too

    # Imports Python's connect_to_db()
    import_python_module( __PACKAGE__, 'mediawords.db' );

    1;
}

sub connect_to_db()
{
    # Get unwrappered DatabaseHandler
    my $db = MediaWords::DB::PythonConnectToDB::connect_to_db();

    # Wrap it in HandlerProxy which will make return values writable
    my $wrappered_db = MediaWords::DB::HandlerProxy->new( $db );

    return $wrappered_db;
}

1;
