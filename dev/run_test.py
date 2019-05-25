#!/usr/bin/env python3

import os
import shlex
from pathlib import Path
from typing import List

from utils import DockerArgumentParser, DockerArguments

RUN_SCRIPT_FILENAME = 'run.py'
"""Script that will be called to run a single command in a Compose environment."""


def docker_test_commands(all_apps_dir: str, test_file: str) -> List[List[str]]:
    """
    Return list commands to execute in order to run all tests in a single test file.

    :param all_apps_dir: Directory with container subdirectories.
    :param test_file: Perl or Python test file.
    :return: List of commands (as lists) to execute in order to run tests in a test file.
    """
    if not os.path.isfile(test_file):
        raise ValueError("Test file '{}' does not exist.".format(test_file))
    if not os.path.isdir(all_apps_dir):
        raise ValueError("Apps directory '{}' does not exist.".format(all_apps_dir))

    all_apps_dir = os.path.abspath(all_apps_dir)
    test_file = os.path.abspath(test_file)

    if not test_file.startswith(all_apps_dir):
        raise ValueError("Test file '{}' is not in apps directory '{}'.".format(test_file, all_apps_dir))

    test_file_extension = os.path.splitext(test_file)[1]
    if test_file_extension not in ['.py', '.t']:
        raise ValueError("Test file '{}' doesn't look like one.".format(test_file))

    test_file_relative_path = test_file[(len(all_apps_dir)):]
    test_file_relative_path_dirs = Path(test_file_relative_path).parts
    app_dirname = test_file_relative_path_dirs[1]

    container_dir = os.path.join(all_apps_dir, app_dirname)
    tests_dir = os.path.join(container_dir, 'tests')
    if not os.path.isdir(tests_dir):
        raise ValueError("Test file '{}' is not located in '{}' subdirectory.".format(test_file, tests_dir))

    commands = list()

    test_path_in_container = '/opt/mediacloud/tests' + test_file[len(tests_dir):]

    if test_file.endswith('.py'):
        test_command = 'py.test -s --verbose ' + test_path_in_container
    elif test_file.endswith('.t'):
        test_command = 'prove ' + test_path_in_container
    else:
        raise ValueError("Not sure how to run this test: {}".format(test_path_in_container))

    pwd = os.path.dirname(os.path.realpath(__file__))
    run_script = os.path.join(pwd, RUN_SCRIPT_FILENAME)
    if not os.path.isfile(run_script):
        raise ValueError("Print run commands script '{}' does not exist.".format(run_script))
    if not os.access(run_script, os.X_OK):
        raise ValueError("Print run commands script '{}' is not executable.".format(run_script))

    commands.append([
        run_script,
        '--all_apps_dir', all_apps_dir,
        app_dirname,
        test_command,
    ])

    return commands


class DockerRunTestArguments(DockerArguments):
    """
    Arguments with a test file path.
    """

    def test_file(self) -> str:
        """
        Return path to file to test.

        :return: Path to test file.
        """
        return self._args.test_file


class DockerRunTestArgumentParser(DockerArgumentParser):
    """
    Argument parser that includes a path to test file.
    """

    def __init__(self, description: str):
        """
        Constructor.

        :param description: Description of the script to print when "--help" is passed.
        """
        super().__init__(description=description)
        self._parser.add_argument('test_file',
                                  help='Perl or Python test file.')

    def parse_arguments(self) -> DockerRunTestArguments:
        """
        Parse arguments and return an object with parsed arguments.

        :return: DockerRunTestArguments object.
        """
        return DockerRunTestArguments(self._parser.parse_args())


if __name__ == '__main__':
    parser = DockerRunTestArgumentParser(description='Print commands to run tests in a single test file.')
    args = parser.parse_arguments()

    for command_ in docker_test_commands(all_apps_dir=args.all_apps_dir(), test_file=args.test_file()):
        print('bash <(' + ' '.join([shlex.quote(c) for c in command_]) + ')')