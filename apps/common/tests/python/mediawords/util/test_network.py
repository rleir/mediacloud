import socket

from mediawords.util.network import (
    random_unused_port, tcp_port_is_open, wait_for_tcp_port_to_open,
    wait_for_tcp_port_to_close)


def test_tcp_port_is_open():
    random_port = random_unused_port()
    assert tcp_port_is_open(random_port) is False

    # Open port
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('localhost', random_port))
    # noinspection PyArgumentList
    s.listen()
    assert tcp_port_is_open(random_port) is True

    # Close port
    s.close()
    assert tcp_port_is_open(random_port) is False


def test_wait_for_tcp_port_to_open():
    random_port = random_unused_port()
    assert wait_for_tcp_port_to_open(port=random_port, retries=2) is False

    # Open port
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('localhost', random_port))
    # noinspection PyArgumentList
    s.listen()
    assert wait_for_tcp_port_to_open(port=random_port, retries=2) is True

    # Close port
    s.close()
    assert wait_for_tcp_port_to_open(port=random_port, retries=2) is False


def test_wait_for_tcp_port_to_close():
    random_port = random_unused_port()
    assert wait_for_tcp_port_to_close(port=random_port, retries=2) is True

    # Open port
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('localhost', random_port))
    # noinspection PyArgumentList
    s.listen()
    assert wait_for_tcp_port_to_close(port=random_port, retries=2) is False

    # Close port
    s.close()
    assert wait_for_tcp_port_to_close(port=random_port, retries=2) is True


def test_random_unused_port():
    random_port = random_unused_port()
    assert tcp_port_is_open(random_port) is False
