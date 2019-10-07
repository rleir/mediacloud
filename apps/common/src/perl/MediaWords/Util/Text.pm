package MediaWords::Util::Text;

# various functions for manipulating text

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.util.text' );

use List::Util qw(min);
use Encode;

# Encode data into UTF-8; die() on error
sub encode_to_utf8($)
{
    my $data = shift;

    # Will die() on error
    return Encode::encode( 'utf-8', $data );
}

# Recursively encode arrayref / hashref / string to UTF-8
# Doesn't modify the original parameter (unless it's of unrecognized type)
sub recursively_encode_to_utf8
{
    my $input = shift;
    my $output;

    if ( ref $input eq ref '' )
    {
        $output = $input;
        if ( $output && ( $output =~ /[^[:ascii:]]/ ) )
        {    # don't encode numbers
            unless ( Encode::is_utf8( $output ) )
            {
                $output = encode_to_utf8( $output );
            }
        }

    }
    elsif ( ref $input eq ref [] )
    {
        $output = [];
        foreach my $value ( @{ $input } )
        {
            push( @{ $output }, recursively_encode_to_utf8( $value ) );
        }

    }
    elsif ( ref $input eq ref {} )
    {
        $output = {};
        foreach my $key ( keys %{ $input } )
        {
            my $value = $input->{ $key };

            $key              = recursively_encode_to_utf8( $key );
            $value            = recursively_encode_to_utf8( $value );
            $output->{ $key } = $value;
        }

    }
    else
    {
        WARN 'Unable to encode to UTF-8: ' . Dumper( $input );
        $output = $input;
    }

    return $output;
}

# Decode data from UTF-8; die() on error
sub decode_from_utf8($)
{
    my $data = shift;

    # Will die() on error
    return Encode::decode( 'utf-8', $data );
}

# Check whether the string is valid UTF-8
sub is_valid_utf8($)
{
    my $s = shift;

    my $valid = 1;

    Encode::_utf8_on( $s );

    $valid = 0 unless ( utf8::valid( $s ) );

    Encode::_utf8_off( $s );

    return $valid;
}

1;
