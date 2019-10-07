"""Routines for interacting with twitter api and data."""

import tweepy
from tweepy.parsers import RawParser

from mediawords.util.parse_json import decode_json
from mediawords.util.log import create_logger
from topics_base.config import TopicsBaseConfig

log = create_logger(__name__)

# configure retry behavior for tweepy
TWITTER_RETRY_DELAY = 60
TWITTER_RETRY_COUNT = 45
TWITTER_RETRY_ERRORS = {401, 404, 500, 503}


class McFetchTweetsException(Exception):
    """error while fetching tweets from twitter."""
    pass


def _get_tweepy_api() -> tweepy.API:
    """Return an authenticated tweepy api object configured for retries."""

    config = TopicsBaseConfig()
    twitter_config = config.twitter_api()

    auth = tweepy.OAuthHandler(twitter_config.consumer_key(), twitter_config.consumer_secret())
    auth.set_access_token(twitter_config.access_token(), twitter_config.access_token_secret())

    # the RawParser lets us directly decode from json to dict below
    api = tweepy.API(
        auth_handler=auth,
        retry_delay=TWITTER_RETRY_DELAY,
        retry_count=TWITTER_RETRY_COUNT,
        retry_errors=TWITTER_RETRY_ERRORS,
        wait_on_rate_limit=True,
        wait_on_rate_limit_notify=True,
        parser=RawParser())

    return api


def fetch_100_users(screen_names: list) -> list:
    """Fetch data for up to 100 users."""
    if len(screen_names) > 100:
        raise McFetchTweetsException('tried to fetch more than 100 users')

    # tweepy returns a 404 if none of the screen names exist, and that 404 is indistinguishable from a 404
    # indicating that tweepy can't connect to the twitter api.  in the latter case, we want to let tweepy use its
    # retry mechanism, but not the former.  so we add a dummy account that we know exists to every request
    # to make sure any 404 we get back is an actual 404.
    dummy_account = 'cyberhalroberts'
    dummy_account_appended = False

    if 'cyberhalroberts' not in screen_names:
        screen_names.append('cyberhalroberts')
        dummy_account_appended = True

    users_json = _get_tweepy_api().lookup_users(screen_names=screen_names, include_entities=False)

    users = list(decode_json(users_json))

    # if we added the dummy account, remove it from the results
    if dummy_account_appended:
        users = list(filter(lambda u: u['screen_name'] != dummy_account, users))

    # return simple list so that this can be mocked. relies on RawParser() in _get_tweepy_api()
    return users


def fetch_100_tweets(tweet_ids: list) -> list:
    """Fetch data for up to 100 tweets."""
    if len(tweet_ids) > 100:
        raise McFetchTweetsException('tried to fetch more than 100 tweets')

    if len(tweet_ids) == 0:
        return []

    tweets = _get_tweepy_api().statuses_lookup(tweet_ids, include_entities=True, trim_user=False, tweet_mode='extended')

    # return simple list so that this can be mocked. relies on RawParser() in _get_tweepy_api()
    tweets = list(decode_json(tweets))

    for tweet in tweets:
        if 'full_text' in tweet:
            tweet['text'] = tweet['full_text']

    return tweets
