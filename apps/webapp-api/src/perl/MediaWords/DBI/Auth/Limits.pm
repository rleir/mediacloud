package MediaWords::DBI::Auth::Limits;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'webapp.auth.limits' );

1;
