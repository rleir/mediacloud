import os

import errno

from mediawords.util.log import create_logger

l = create_logger(__name__)

__FILE_THAT_EXISTS_AT_ROOT_PATH = 'mediawords.yml.dist'


class McRootPathException(Exception):
    pass


def mc_root_path() -> str:
    # FIXME MC_REWRITE_TO_PYTHON: Inline::Python doesn't always set __file__
    # properly, but chances are that we're running from Media Cloud root directory
    try:
        __file__
    except NameError:
        pwd = os.getcwd()
        l.debug("__file__ is undefined, trying current directory to pass as Media Cloud root: %s" % pwd)
        root_path = pwd
    else:
        root_path = os.path.realpath(os.path.join(__file__, "..", "..", "..", ".."))

    if not os.path.isfile(os.path.join(root_path, __FILE_THAT_EXISTS_AT_ROOT_PATH)):
        raise McRootPathException("Unable to determine Media Cloud root path (tried '%s')" % root_path)
    l.debug("Root path is %s" % root_path)
    return root_path


class McScriptPathException(Exception):
    pass


def mc_script_path() -> str:
    root_path = mc_root_path()
    script_path = os.path.join(root_path, "script")
    if not os.path.isdir(script_path):
        raise McScriptPathException("Unable to determine Media Cloud script path (tried '%s')" % script_path)
    l.debug("Script path is %s" % script_path)
    return script_path


def mkdir_p(path: str) -> None:
    """mkdir -p"""
    l.debug("Creating directory '%s'..." % path)
    try:
        os.makedirs(path)
    except OSError as e:  # Python >2.5
        if e.errno == errno.EEXIST and os.path.isdir(path):
            pass
        else:
            raise
    l.debug("Created directory '%s'." % path)


def resolve_absolute_path_under_mc_root(path: str, must_exist: bool = False) -> str:
    """Return absolute path to object (file or directory) under Media Cloud root."""
    mc_root = mc_root_path()
    dist_path = os.path.join(mc_root, path)
    if must_exist:
        if not os.path.exists(dist_path):
            raise Exception("Object '%s' at path '%s' does not exist." % (path, dist_path))
    return os.path.abspath(dist_path)
