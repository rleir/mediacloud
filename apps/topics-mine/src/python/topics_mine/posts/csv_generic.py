"""Parse generic posts from a csv."""

import csv
import datetime
import io

from mediawords.util.log import create_logger

from topics_mine.posts import AbstractPostFetcher

log = create_logger(__name__)


class McPostsGenericDataException(Exception):
    """exception indicating an error in the data for generic posts."""
    pass


class CSVStaticPostFetcher(AbstractPostFetcher):

    @staticmethod
    def _get_csv_string_from_dicts(dicts: list) -> str:
        """Given a list of dicts, return a representative csv string."""
        if len(dicts) < 1:
            return ''

        csv_io = io.StringIO()

        csv_writer = csv.DictWriter(csv_io, fieldnames=dicts[0].keys())

        csv_writer.writeheader()
        [csv_writer.writerow(d) for d in dicts]

        return csv_io.getvalue()

    @staticmethod
    def _get_dicts_from_csv_string(csv_string: str) -> list:
        """Given a csv string, return a list of dicts."""
        if len(csv_string) < 1:
            return []

        csv_io = io.StringIO(csv_string)

        return list(csv.DictReader(csv_io))

    def fetch_posts(self, query: str, start_date: datetime, end_date: datetime) -> list:
        """Return posts from a csv that are within the given date range."""
        all_posts = self._get_dicts_from_csv_string(query)

        posts = []
        for p in all_posts:
            if str(start_date) <= p['publish_date'] <= str(end_date):
                posts.append(p)

        required_fields = ['content', 'author', 'channel', 'content', 'publish_date', 'post_id']
        for post in posts:
            for field in required_fields:
                if field not in post:
                    raise McPostsGenericDataException(f"Missing required field: {field}")

            post['data'] = {}

        return posts
