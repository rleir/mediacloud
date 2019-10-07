use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Auth::Info;
use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Register;
use MediaWords::Util::Mail;

sub test_login_with_api_key($)
{
    my ( $db ) = @_;

    my $email      = 'test@user.login';
    my $password   = 'userlogin123';
    my $full_name  = 'Test user login';
    my $ip_address = '1.2.3.4';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => $full_name,
            notes           => 'Test test test',
            role_ids        => [ 1 ],
            active          => 1,
            password        => $password,
            password_repeat => $password,
            activation_url  => '',                 # user is active, no need for activation URL
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    # Get sample API keys
    my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password, $ip_address );
    ok( $user );
    my $global_api_key = $user->global_api_key();
    ok( $global_api_key );
    ok( length( $global_api_key ) > 1 );

    my $per_ip_api_key = $user->api_key_for_ip_address( $ip_address );
    ok( $per_ip_api_key );
    ok( length( $per_ip_api_key ) > 1 );

    isnt( $global_api_key, $per_ip_api_key );

    {
        # Non-existent API key
        eval { MediaWords::DBI::Auth::Login::login_with_api_key( $db, 'Non-existent API key', $ip_address ); };
        ok( $@ );
    }

    {
        # Global API key
        my $api_key_user = MediaWords::DBI::Auth::Login::login_with_api_key( $db, $global_api_key, $ip_address );
        ok( $api_key_user );
        is( $api_key_user->email(),          $email );
        is( $api_key_user->global_api_key(), $global_api_key );
    }

    {
        # Per-IP API key
        my $api_key_user = MediaWords::DBI::Auth::Login::login_with_api_key( $db, $per_ip_api_key, $ip_address );
        ok( $api_key_user );
        is( $api_key_user->email(), $email );
    }

    # Inactive user
    {
        my $inactive_user_email = 'inactive@user.com';

        eval {
            my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
                email           => $inactive_user_email,
                full_name       => $full_name,
                notes           => 'Test test test',
                role_ids        => [ 1 ],
                active          => 0,
                password        => $password,
                password_repeat => $password,
                activation_url  => 'https://activate.com/activate',
            );

            MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
        };
        ok( !$@, "Unable to add user: $@" );

        my $user = MediaWords::DBI::Auth::Info::user_info( $db, $inactive_user_email );
        ok( $user );
        my $global_api_key = $user->global_api_key();

        eval { MediaWords::DBI::Auth::Login::login_with_api_key( $db, $global_api_key, $ip_address ); };
        my $error_message = $@;
        ok( $error_message );

        # Make sure the error message explicitly states that login failed due to user not being active
        like( $error_message, qr/not active/i );
    }
}

sub main
{
    # Don't actually send any emails
    MediaWords::Util::Mail::enable_test_mode();

    my $db = MediaWords::DB::connect_to_db();

    test_login_with_api_key( $db );

    done_testing();
}

main();
