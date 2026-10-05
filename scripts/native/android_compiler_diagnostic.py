"""Run the unchanged fixture Gradle command; publish only a closed diagnostic.

No raw output is printed or written to disk. A rejected capture is drained to
EOF without cancelling Gradle. Categories are observed signals, not root causes.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

MAX_CAPTURE_BYTES = 8 * 1024 * 1024
READ_BYTES = 64 * 1024
MAX_JSON_BYTES = 8192
OUTPUT_PARTS = ('test-results', 'android-compiler-diagnostic', 'diagnostic.json')
COMMANDS = {
    'debug': ('./gradlew', '--no-daemon', 'assembleDebug'),
    'optimized': ('./gradlew', '--no-daemon', 'assembleRecetteOptimized'),
}
# Names are constants from the requested variants, never inferred from output.
TASKS = {
    variant: frozenset(':app:' + name for name in (
        'assemble' + suffix,
        'check' + suffix + 'AarMetadata',
        'check' + suffix + 'DuplicateClasses',
        'compile' + suffix + 'JavaWithJavac',
        'compile' + suffix + 'Kotlin',
        'dexBuilder' + suffix,
        'mergeExtDex' + suffix,
        'merge' + suffix + 'Assets',
        'merge' + suffix + 'JavaResource',
        'merge' + suffix + 'NativeLibs',
        'merge' + suffix + 'Resources',
        'package' + suffix,
        'process' + suffix + 'MainManifest',
        'process' + suffix + 'Manifest',
        'process' + suffix + 'ManifestForPackage',
        'process' + suffix + 'Resources',
        'strip' + suffix + 'DebugSymbols',
        'validateSigning' + suffix,
    ))
    for variant, suffix in (('debug', 'Debug'), ('optimized', 'RecetteOptimized'))
}
TASKS['optimized'] |= frozenset({':app:minifyRecetteOptimizedWithR8',
                               ':app:shrinkRecetteOptimizedRes'})
SIGNALS = {
    'r8_missing_classes': r'^(?:ERROR: )?Missing classes detected while running R8(?:\.|$)',
    'r8_compilation': r'^(?:> )?R8: Compilation failed(?:\b)',
    'resource_linker': r'^(?:> )?Android resource linking failed$',
    'manifest': r'^(?:> )?Manifest merger failed(?:\b)',
    'dependency_resolution': r'^(?:> )?Could not resolve (?:all (?:files|dependencies|artifacts) for configuration\b|all task dependencies\b)',
    'java_compile': r'^(?:> )?Compilation failed; see the compiler error output for details\.$',
    'kotlin_compile': r'^(?:> )?A failure occurred while executing org\.jetbrains\.kotlin\.compilerRunner\.',
    'gradle_configuration': r'^(?:> )?(?:A problem occurred (?:configuring project|evaluating (?:root )?project)\b|Could not (?:compile|open) (?:settings|build) file\b)',
    'gradle_daemon': r'^(?:> )?Gradle build daemon disappeared unexpectedly(?:\b)',
    'disk_space': r'^(?:> )?(?:java\.io\.IOException: )?No space left on device$',
}
CATEGORIES = frozenset(SIGNALS) | {'unclassified_failure'}
STATUSES = frozenset({'complete', 'output_limit_refused', 'text_format_refused',
                      'collection_failed', 'launch_failed', 'context_refused'})
FAILED_TASK = re.compile(r"^(?:Execution failed for task '([^']+)'\.|> Task (\S+) FAILED)$")
KEYS = frozenset({'schemaVersion', 'variant', 'compilerStarted', 'gradleExitCode',
                  'wrapperExitCode', 'diagnosticStatus', 'assemblyResult',
                  'failureCategories', 'failedTasks', 'unrecognizedFailedTask'})


def exit_code(returncode):
    # subprocess represents a POSIX signal with a negative return code.
    if type(returncode) is not int or not -127 <= returncode <= 255:
        raise ValueError('INVALID_PROCESS_STATUS')
    return 128 - returncode if returncode < 0 else returncode


def closed_document(variant, started, code, status, signals=(), tasks=(), unknown=False):
    complete = status == 'complete'
    failed = code is not None and code != 0
    return {
        'schemaVersion': 1,
        'variant': variant if variant in COMMANDS else 'unknown',
        'compilerStarted': started,
        'gradleExitCode': code,
        'wrapperExitCode': code if failed else (0 if complete and code == 0 else 1),
        'diagnosticStatus': status,
        'assemblyResult': 'unknown' if code is None else ('failed' if failed else 'succeeded'),
        'failureCategories': sorted(signals or {'unclassified_failure'}) if complete and failed else [],
        'failedTasks': sorted(tasks) if complete and failed else [],
        'unrecognizedFailedTask': bool(unknown) if complete and failed else False,
    }


def collect(pipe):
    """Retain at most 8 MiB; on overflow discard everything and keep draining."""
    capture = bytearray()
    refused = False
    while True:
        chunk = pipe.read(READ_BYTES)
        if not chunk:
            break
        if not isinstance(chunk, bytes):
            raise ValueError('INVALID_CAPTURE')
        if refused:
            continue
        if len(capture) + len(chunk) > MAX_CAPTURE_BYTES:
            refused = True
            capture.clear()
        else:
            capture.extend(chunk)
    return None if refused else capture


def classify(capture, variant, code):
    if capture is None:
        return closed_document(variant, True, code, 'output_limit_refused')
    try:
        content = capture.decode('utf-8', errors='strict')
    except UnicodeError:
        return closed_document(variant, True, code, 'text_format_refused')
    # No partial classification of binary/terminal-control output.
    if re.search(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', content):
        return closed_document(variant, True, code, 'text_format_refused')
    signals, tasks, unknown = set(), set(), False
    if code != 0:
        for line in content.splitlines():
            line = line.strip()
            for category, pattern in SIGNALS.items():
                if re.search(pattern, line):
                    signals.add(category)
            match = FAILED_TASK.fullmatch(line)
            if match:
                candidate = match.group(1) or match.group(2)
                if candidate in TASKS[variant]:
                    tasks.add(candidate)
                else:
                    unknown = True
    return closed_document(variant, True, code, 'complete', signals, tasks, unknown)


def run_compiler(root, variant, launcher=subprocess.Popen):
    """The injected launcher exists for pure tests, never as a CLI option."""
    if variant not in COMMANDS:
        return closed_document(variant, False, None, 'context_refused')
    try:
        process = launcher(list(COMMANDS[variant]), cwd=root / 'android',
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except Exception:
        return closed_document(variant, False, None, 'launch_failed')
    capture, collection_failed = None, False
    try:
        try:
            capture = collect(process.stdout)
        except Exception:
            collection_failed = True
        finally:
            process.stdout.close()
        code = exit_code(process.wait())
    except Exception:
        return closed_document(variant, True, None, 'collection_failed')
    if collection_failed:
        return closed_document(variant, True, code, 'collection_failed')
    try:
        return classify(capture, variant, code)
    except Exception:
        return closed_document(variant, True, code, 'collection_failed')


def encode_closed(document):
    """Reject unknown fields/values before a single byte reaches the artifact."""
    valid = isinstance(document, dict) and set(document) == KEYS
    valid = valid and type(document['schemaVersion']) is int and document['schemaVersion'] == 1
    valid = valid and document['variant'] in {*COMMANDS, 'unknown'}
    valid = valid and type(document['compilerStarted']) is bool
    valid = valid and (document['gradleExitCode'] is None or
                      (type(document['gradleExitCode']) is int and 0 <= document['gradleExitCode'] <= 255))
    valid = valid and type(document['wrapperExitCode']) is int and 0 <= document['wrapperExitCode'] <= 255
    valid = valid and document['diagnosticStatus'] in STATUSES
    valid = valid and document['assemblyResult'] in {'unknown', 'succeeded', 'failed'}
    valid = valid and type(document['unrecognizedFailedTask']) is bool
    for key, allowed in (('failureCategories', CATEGORIES),
                         ('failedTasks', TASKS.get(document.get('variant'), frozenset()))):
        values = document.get(key)
        valid = valid and isinstance(values, list) and len(values) <= len(allowed)
        valid = valid and all(type(value) is str and value in allowed for value in values)
        valid = valid and len(set(values)) == len(values)
    if not valid:
        raise ValueError('CLOSED_SCHEMA_REFUSED')
    encoded = (json.dumps(document, sort_keys=True, separators=(',', ':')) + '\n').encode('ascii')
    if len(encoded) > MAX_JSON_BYTES:
        raise ValueError('CLOSED_SCHEMA_REFUSED')
    return encoded


def write_closed(root, document):
    encoded = encode_closed(document)
    parent = root
    for part in OUTPUT_PARTS[:-1]:
        parent = parent / part
        if parent.is_symlink():
            raise ValueError('UNSAFE_OUTPUT_PATH')
        parent.mkdir(mode=0o700, exist_ok=True)
    output = parent / OUTPUT_PARTS[-1]
    # O_EXCL refuses stale files and symlinks; no inherited artifact is replaced.
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(encoded)


def main():
    root = Path(__file__).resolve().parents[2]
    variant = os.environ.get('NATIVE_RECETTE_VARIANT')
    valid_context = (len(sys.argv) == 1 and os.environ.get('CI') == 'true'
                     and os.environ.get('NATIVE_RECETTE') == '1')
    document = (run_compiler(root, variant) if valid_context else
                closed_document(variant, False, None, 'context_refused'))
    try:
        write_closed(root, document)
        # A fixed step output gates upload, so a rejected/stale file is never
        # uploaded merely because it already exists in a workspace.
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='ascii') as stream:
            stream.write('diagnostic_ready=true\n')
    except Exception:
        # A failed compiler is never turned into success by an artifact error.
        return document['wrapperExitCode'] or 1
    return document['wrapperExitCode']


if __name__ == '__main__':
    try:
        result = main()
    except KeyboardInterrupt:
        result = 130
    except BaseException:
        result = 1
    raise SystemExit(result)
