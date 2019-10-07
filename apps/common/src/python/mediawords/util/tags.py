"""
Various functions for editing feed and medium tags
"""

# FIXME move everything to "Tags" / "Tag sets" models?
import re
from typing import Dict, Any, Optional

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def lookup_tag(db: DatabaseHandler, tag_name: str) -> Optional[Dict[str, Any]]:
    """Lookup the tag given the tag_set:tag format."""
    tag_name = decode_object_from_bytes_if_needed(tag_name)

    if not tag_name:
        log.warning("Tag name is empty.")
        return None

    if not re.match(pattern='^([^:]*):([^:]*)$', string=tag_name):
        log.warning("Unable to parse tag name '{}'.".format(tag_name))
        return None

    tag_set_name, tag = tag_name.split(':')

    found_tag = db.query("""
        SELECT t.*
        FROM tags AS t,
             tag_sets AS ts
        WHERE t.tag_sets_id = ts.tag_sets_id
          AND t.tag = %(tag)s
          AND ts.name = %(tag_set_name)s
    """, {'tag': tag, 'tag_set_name': tag_set_name}).hash()

    # MC_REWRITE_TO_PYTHON: Perlism
    if found_tag is None:
        found_tag = {}

    return found_tag
