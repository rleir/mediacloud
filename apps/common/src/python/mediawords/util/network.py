import socket
import time
from typing import Union

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def hostname_resolves(hostname: str) -> bool:
    """Return True if hostname resolves to IP."""
    try:
        socket.gethostbyname(hostname)
        return True
    except socket.error:
        return False


def tcp_port_is_open(port: int, hostname: str = 'localhost') -> bool:
    """Test if TCP port is open."""

    hostname = decode_object_from_bytes_if_needed(hostname)

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    result = sock.connect_ex((hostname, port))
    if result == 0:
        try:
            sock.shutdown(socket.SHUT_RDWR)
        except OSError as ex:
            # Quiet down "OSError: [Errno 57] Socket is not connected"
            log.warning("Error while shutting down socket: %s" % str(ex))
    sock.close()
    return result == 0


def wait_for_tcp_port_to_open(port: int,
                              hostname: str = 'localhost',
                              retries: int = 60,
                              delay: Union[int, float] = 1) -> bool:
    """Try connecting to TCP port until it opens (or not); return True if managed to connect."""

    hostname = decode_object_from_bytes_if_needed(hostname)

    port_is_open = False
    for retry in range(retries):
        if retry == 0:
            log.info("Trying to connect to %s:%d" % (hostname, port))
        else:
            log.info("Trying to connect to %s:%d, retry %d" % (hostname, port, retry))

        if tcp_port_is_open(port, hostname):
            port_is_open = True
            break
        else:
            time.sleep(delay)
    return port_is_open


def wait_for_tcp_port_to_close(port: int,
                               hostname: str = 'localhost',
                               retries: int = 60,
                               delay: Union[int, float] = 1) -> bool:
    """Try connecting to TCP port until it closes (or not); return True if port is no longer open."""

    hostname = decode_object_from_bytes_if_needed(hostname)

    port_is_closed = False
    for retry in range(retries):
        if retry == 0:
            log.info("Trying to connect to %s:%d" % (hostname, port))
        else:
            log.info("Trying to connect to %s:%d, retry %d" % (hostname, port, retry))

        if tcp_port_is_open(port, hostname):
            time.sleep(delay)
        else:
            port_is_closed = True
            break

    return port_is_closed


def random_unused_port() -> int:
    """Return random unused TCP port that could be used e.g. for testing."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('', 0))
    # noinspection PyArgumentList
    s.listen()
    port = s.getsockname()[1]
    s.close()
    return port