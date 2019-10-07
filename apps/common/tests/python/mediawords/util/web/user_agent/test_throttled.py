"""test ThrottledUserAgent."""

import time

import pytest

from mediawords.db import connect_to_db
from mediawords.test.hash_server import HashServer
# noinspection PyProtectedMember
from mediawords.util.web.user_agent.throttled import (
    ThrottledUserAgent,
    McThrottledDomainException,
    _DEFAULT_DOMAIN_TIMEOUT,
)


def test_throttled_user_agent() -> None:
    """Test requests with throttling."""

    db = connect_to_db()

    pages = {'/test': 'Hello!', }
    port = 8888
    hs = HashServer(port=port, pages=pages)
    hs.start()

    ua = ThrottledUserAgent(db, domain_timeout=2)
    test_url = hs.page_url('/test')

    # first request should work
    response = ua.get(test_url)
    assert response.decoded_content() == 'Hello!'

    # fail because we're in the timeout
    ua = ThrottledUserAgent(db, domain_timeout=2)
    with pytest.raises(McThrottledDomainException):
        ua.get(test_url)

    # succeed because it's a different domain
    ua = ThrottledUserAgent(db, domain_timeout=2)
    response = ua.get('http://127.0.0.1:8888/test')
    assert response.decoded_content() == 'Hello!'

    # still fail within the timeout
    ua = ThrottledUserAgent(db, domain_timeout=2)
    with pytest.raises(McThrottledDomainException):
        ua.get(test_url)

    time.sleep(2)

    # now we're outside the timeout, so it should work
    ua = ThrottledUserAgent(db, domain_timeout=2)
    response = ua.get(test_url)
    assert response.decoded_content() == 'Hello!'

    # and follow up request on the same ua object should work
    response = ua.get(test_url)
    assert response.decoded_content() == 'Hello!'

    # but then fail within the new timeout period with a new object
    ua = ThrottledUserAgent(db, domain_timeout=2)
    with pytest.raises(McThrottledDomainException):
        ua.get(test_url)

    hs.stop()

    # test domain_timeout assignment logic
    ua = ThrottledUserAgent(db, domain_timeout=100)
    assert ua.domain_timeout == 100

    ua = ThrottledUserAgent(db=db)
    assert ua.domain_timeout == _DEFAULT_DOMAIN_TIMEOUT
