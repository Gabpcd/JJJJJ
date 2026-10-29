#!/usr/bin/env python3
"""Private stdin only. This helper never prints its payload or the source plist."""
import json
import os
import pathlib
import plistlib
import sys


def inject(value, environment):
    matches = []

    def walk(node):
        if isinstance(node, dict):
            bundle = node.get('TestBundlePath', '')
            if isinstance(bundle, str) and bundle.endswith('/NativeAuthUITests.xctest'):
                matches.append(node)
            for child in node.values():
                walk(child)
        elif isinstance(node, list):
            for child in node:
                walk(child)
    walk(value)
    if len(matches) != 1 or set(environment) != {'JOLENE_AUTH_COHORT_JSON', 'JOLENE_AUTH_FORMAT'}:
        raise ValueError('PRIVATE_XCTEST_TARGET')
    target = matches[0]
    # This is the UI test runner environment. Never set the target app environment.
    if target.get('UITargetAppEnvironmentVariables') or target.get('TestHostEnvironmentVariables'):
        raise ValueError('PRIVATE_XCTEST_APP_ENV')
    target['EnvironmentVariables'] = {**target.get('EnvironmentVariables', {}), **environment}
    target['SystemAttachmentLifetime'] = 'deleteOnSuccess'
    target['UserAttachmentLifetime'] = 'keepAlways'
    return value


def main():
    payload = sys.stdin.buffer.read(32769)
    if len(payload) > 32768:
        raise ValueError('PRIVATE_XCTEST_SIZE')
    request = json.loads(payload)
    if set(request) != {'source', 'destination', 'environment'}:
        raise ValueError('PRIVATE_XCTEST_REQUEST')
    source, destination = pathlib.Path(request['source']), pathlib.Path(request['destination'])
    if source.parent != destination.parent or source == destination:
        raise ValueError('PRIVATE_XCTEST_PATH')
    result = inject(plistlib.loads(source.read_bytes()), request['environment'])
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as file:
        plistlib.dump(result, file, fmt=plistlib.FMT_XML)
        file.flush()
        os.fsync(file.fileno())


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Python exception contexts can contain arbitrary JSON/passwords.
        sys.stderr.write('PRIVATE_XCTEST_PREPARATION_FAILED\n')
        sys.exit(1)
