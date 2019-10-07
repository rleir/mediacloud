import re
from typing import List, Pattern, Optional

from mediawords.util.config import env_value, McConfigException


class ConnectRetriesConfig(object):
    """Connect retries configuration."""

    @staticmethod
    def sleep_between_attempts() -> float:
        """Seconds (or parts of second) to sleep between retries."""
        return 1.0

    @staticmethod
    def max_attempts() -> int:
        """Max. number of attempts to connect.

        Must be positive (we want to try connecting at least one time).
        """
        return 60


class DatabaseConfig(object):
    """PostgreSQL database configuration."""

    @staticmethod
    def hostname() -> str:
        """Hostname."""
        # Container's name from docker-compose.yml
        return "postgresql-pgbouncer"

    @staticmethod
    def port() -> int:
        """Port."""
        # Container's exposed port from docker-compose.yml
        return 6432

    @staticmethod
    def database_name() -> str:
        """Database name."""
        return "mediacloud"

    @staticmethod
    def username() -> str:
        """Username."""
        return "mediacloud"

    @staticmethod
    def password() -> str:
        """Password."""
        return "mediacloud"

    @staticmethod
    def retries() -> ConnectRetriesConfig:
        """connect_to_db() retries configuration."""
        return ConnectRetriesConfig()


class AmazonS3DownloadsConfig(object):
    """Amazon S3 raw download storage configuration."""

    @staticmethod
    def access_key_id() -> str:
        """Access key ID."""
        return env_value('MC_DOWNLOADS_AMAZON_S3_ACCESS_KEY_ID')

    @staticmethod
    def secret_access_key() -> str:
        """Secret access key."""
        return env_value('MC_DOWNLOADS_AMAZON_S3_SECRET_ACCESS_KEY')

    @staticmethod
    def bucket_name() -> str:
        """Bucket name."""
        return env_value('MC_DOWNLOADS_AMAZON_S3_BUCKET_NAME')

    @staticmethod
    def directory_name() -> str:
        """Directory name (prefix)."""
        return env_value('MC_DOWNLOADS_AMAZON_S3_DIRECTORY_NAME', allow_empty_string=True)


class RabbitMQConfig(object):
    """RabbitMQ (Celery broker) client configuration."""

    @staticmethod
    def hostname() -> str:
        """Hostname."""
        # Container's name from docker-compose.yml
        return "rabbitmq-server"

    @staticmethod
    def port() -> int:
        """Port."""
        # Container's exposed port from docker-compose.yml
        return 5672

    @staticmethod
    def username() -> str:
        """Username."""
        return "mediacloud"

    @staticmethod
    def password() -> str:
        """Password."""
        return "mediacloud"

    @staticmethod
    def vhost() -> str:
        """Virtual host."""
        return "/mediacloud"

    @staticmethod
    def timeout() -> int:
        """Timeout."""
        # FIXME possibly hardcode it somewhere
        return 60


class SMTPConfig(object):
    """SMTP configuration."""

    @staticmethod
    def hostname() -> str:
        """Hostname."""
        # Container's name from docker-compose.yml
        return 'mail-postfix-server'

    @staticmethod
    def port() -> int:
        """Port."""
        # Container's exposed port from docker-compose.yml
        return 25

    @staticmethod
    def use_starttls() -> bool:
        """Use STARTTLS? If you enable that, you probably want to change the port to 587."""
        # FIXME remove altogether, not used
        return False

    @staticmethod
    def username() -> str:
        """Username."""
        # FIXME remove, not used
        return ''

    @staticmethod
    def password() -> str:
        """Password."""
        return ''


class DownloadStorageConfig(object):
    """Download storage configuration."""

    @staticmethod
    def storage_locations() -> List[str]:
        """Download storage locations."""
        value = env_value('MC_DOWNLOADS_STORAGE_LOCATIONS', required=False)
        if value is None:
            value = 'postgresql'
        locations = value.split(';')
        locations = [location.strip() for location in locations]
        if len(locations) == 0 and locations[0] == '':
            locations = []
        return locations

    @staticmethod
    def read_all_from_s3() -> bool:
        """Whether or not to read all non-inline downloads from S3."""
        value = env_value('MC_DOWNLOADS_READ_ALL_FROM_S3', required=False, allow_empty_string=True)
        if value is None:
            value = 0
        return bool(int(value))

    @staticmethod
    def fallback_postgresql_to_s3() -> bool:
        """Whether to fallback PostgreSQL downloads to Amazon S3.

        If the download doesn't exist in PostgreSQL storage, S3 will be tried instead."""
        value = env_value('MC_DOWNLOADS_FALLBACK_POSTGRESQL_TO_S3', required=False, allow_empty_string=True)
        if value is None:
            value = 0
        return bool(int(value))

    @staticmethod
    def cache_s3() -> bool:
        """Whether to enable local Amazon S3 download cache."""
        value = env_value('MC_DOWNLOADS_CACHE_S3', required=False, allow_empty_string=True)
        if value is None:
            value = 0
        return bool(int(value))


class AuthenticatedDomain(object):
    """Single authenticated domain."""

    __slots__ = [
        '_domain',
        '_username',
        '_password',
    ]

    def __init__(self, domain: str, username: str, password: str):
        self._domain = domain
        self._username = username
        self._password = password

    def domain(self) -> str:
        """Return domain name, e.g. "ap.org"."""
        return self._domain

    def username(self) -> str:
        """Return HTTP auth username."""
        return self._username

    def password(self) -> str:
        """Return HTTP auth password."""
        return self._password

    # Tests do the comparison
    def __eq__(self, other) -> bool:
        if not isinstance(other, AuthenticatedDomain):
            return NotImplemented

        return (self.domain() == other.domain()) and (
                self.username() == other.username()) and (self.password() == other.password())

    # __eq__() disables hashing
    def __hash__(self):
        return hash((self._domain, self._username, self._password))


class McConfigAuthenticatedDomainsException(McConfigException):
    """Exception thrown on authenticated domains syntax errors."""
    pass


def _authenticated_domains_from_string(value: Optional[str]) -> List[AuthenticatedDomain]:
    """Parse the string and return a list of authenticated domains."""

    if not value:
        return []

    entries = value.split(';')

    domains = []

    for entry in entries:
        entry = entry.strip()

        if '@' not in entry:
            raise McConfigAuthenticatedDomainsException("Entry doesn't contain '@' character.")

        username_password, domain = entry.split('@', maxsplit=1)
        if not username_password:
            raise McConfigAuthenticatedDomainsException("Username + password can't be empty.")
        if not domain:
            raise McConfigAuthenticatedDomainsException("Domain can't be empty.")
        if '@' in domain:
            raise McConfigAuthenticatedDomainsException("Domain contains '@' character.")

        if ':' not in username_password:
            raise McConfigAuthenticatedDomainsException("Username + password doesn't contain ':' character.")

        username, password = username_password.split(':', maxsplit=1)
        if not username:
            raise McConfigAuthenticatedDomainsException("Username is empty.")
        if not password:
            raise McConfigAuthenticatedDomainsException("Password is empty.")
        if ':' in password:
            raise McConfigAuthenticatedDomainsException("Password contains ':' character.")

        domains.append(AuthenticatedDomain(domain=domain, username=username, password=password))

    return domains


class UserAgentConfig(object):
    """UserAgent configuration."""

    @staticmethod
    def blacklist_url_pattern() -> Optional[Pattern]:
        """URL pattern for which we should fail all of the HTTP(s) requests."""
        pattern = env_value('MC_USERAGENT_BLACKLIST_URL_PATTERN', required=False, allow_empty_string=True)
        if pattern:
            pattern = re.compile(pattern, flags=re.IGNORECASE | re.UNICODE)
        else:
            pattern = None
        return pattern

    @staticmethod
    def authenticated_domains() -> List[AuthenticatedDomain]:
        """List of authenticated domains."""
        value = env_value('MC_USERAGENT_AUTHENTICATED_DOMAINS', required=False, allow_empty_string=True)
        return _authenticated_domains_from_string(value)

    @staticmethod
    def parallel_get_num_parallel() -> int:
        """Parallel connection count."""
        value = env_value('MC_USERAGENT_PARALLEL_GET_NUM_PARALLEL', required=False)
        if value is None:
            value = 10
        return int(value)

    @staticmethod
    def parallel_get_timeout() -> int:
        """Connection timeout, in seconds."""
        value = env_value('MC_USERAGENT_PARALLEL_GET_TIMEOUT', required=False)
        if value is None:
            value = 90
        return int(value)

    @staticmethod
    def parallel_get_per_domain_timeout() -> int:
        """Per-domain timeout, in seconds."""
        value = env_value('MC_USERAGENT_PARALLEL_GET_PER_DOMAIN_TIMEOUT', required=False)
        if not value:
            value = 1
        return int(value)


class CommonConfig(object):
    """Global configuration (shared by all the apps)."""

    @staticmethod
    def database() -> DatabaseConfig:
        """PostgreSQL configuration."""
        return DatabaseConfig()

    @staticmethod
    def amazon_s3_downloads() -> AmazonS3DownloadsConfig:
        """Amazon S3 raw download storage configuration."""
        return AmazonS3DownloadsConfig()

    @staticmethod
    def rabbitmq() -> RabbitMQConfig:
        """RabbitMQ client configuration."""
        return RabbitMQConfig()

    @staticmethod
    def smtp() -> SMTPConfig:
        """SMTP configuration."""
        return SMTPConfig()

    @staticmethod
    def download_storage() -> DownloadStorageConfig:
        """Download storage configuration."""
        return DownloadStorageConfig()

    @staticmethod
    def user_agent() -> UserAgentConfig:
        """UserAgent configuration."""
        return UserAgentConfig()

    @staticmethod
    def email_from_address() -> str:
        """'From:' email address when sending emails."""
        value = env_value('MC_EMAIL_FROM_ADDRESS', required=False)
        if value is None:
            value = 'info@mediacloud.org'
        return value

    @staticmethod
    def solr_url() -> str:
        """Solr server URL."""
        # "solr-shard" container's name from docker-compose.yml; will round-robin between servers
        return 'http://solr-shard:8983/solr'

    @staticmethod
    def extractor_api_url() -> str:
        """URL of the extractor API."""
        # "extract-article-from-page" container's name from docker-compose.yml; will round-robin between servers
        return "http://extract-article-from-page:8080/extract"
