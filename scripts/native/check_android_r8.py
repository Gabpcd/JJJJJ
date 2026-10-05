"""Inspect the optimized fixture APK, never sign/install/publish it or run Gradle."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import zipfile


REASONS = frozenset(('APK_FILE', 'CI_CONTEXT', 'COMMIT_IDENTITY', 'DEX_ARCHIVE_ENTRIES', 'DEX_ARCHIVE_SIZE', 'DEX_CLASS_DESCRIPTOR', 'DEX_CROSS_FILE_DUPLICATE', 'DEX_DUPLICATE_CLASS', 'DEX_HEADER', 'DEX_SIZE', 'DEX_STRING_INDEX', 'DEX_STRING_OFFSET', 'DEX_STRING_TERMINATOR', 'DEX_TABLE_BOUNDS', 'DEX_TYPE_INDEX', 'DEX_ULEB_BOUNDS', 'DEX_ULEB_INVALID', 'DEX_VERSION', 'FIXTURE_IDENTITY', 'GLOBAL_OPTIMIZATION_DISABLED', 'MAIN_ACTIVITY_ABSENT', 'MAPPING_CLASS_ENTRIES', 'MAPPING_FILE', 'MAPPING_LINE_SIZE', 'MAPPING_STREAM_SIZE', 'MAPPING_TABLE_SIZE', 'PLUGIN_DUPLICATE', 'PLUGIN_LIST_SHAPE', 'PLUGIN_NAME_INVALID', 'PLUGIN_NOT_PRESERVED', 'PRODUCTION_CONFIG_PRESENT', 'R8_COMPILER_MARKER', 'RENAMING_ABSENT', 'UNCLASSIFIED'))


class R8Refused(ValueError):
    def __init__(self, reason):
        self.reason = reason if reason in REASONS else 'UNCLASSIFIED'
        super().__init__('ANDROID_R8_ARTIFACT_REFUSED')


def require(ok, reason='UNCLASSIFIED'):
    if not ok:
        raise R8Refused(reason)


MAPPING_FILES = ('mapping.txt', 'configuration.txt')
MAPPING_SIZE_CATEGORIES = ('0', '0_32M', '32_128M', '128_256M', 'over256M')
MAPPING_STREAM_LIMIT = 128 * 1024 * 1024
MAPPING_LINE_LIMIT = 128 * 1024
MAPPING_TABLE_LIMIT = 8 * 1024 * 1024


def read_mapping(path, expected_bytes):
    # R8 line/method metadata can exceed 32 MiB even for a valid small DEX.
    # Read and hash every byte, retaining only the class entries used below.
    # Unlike a whole-file read, both line and retained-table memory are bounded.
    require(type(expected_bytes) is int and 0 < expected_bytes <= MAPPING_STREAM_LIMIT, 'MAPPING_STREAM_SIZE')
    entries, retained, consumed, compiler = [], 0, 0, False
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        while True:
            line = stream.readline(MAPPING_LINE_LIMIT + 1)
            if not line:
                break
            require(len(line) <= MAPPING_LINE_LIMIT, 'MAPPING_LINE_SIZE')
            consumed += len(line)
            require(consumed <= expected_bytes, 'MAPPING_STREAM_SIZE')
            digest.update(line)
            text = line.decode('utf-8', errors='strict').rstrip('\r\n')
            compiler |= '# compiler: R8' in text
            if re.fullmatch(r'(\S+) -> (\S+):', text):
                retained += len(line)
                require(retained <= MAPPING_TABLE_LIMIT and len(entries) < 100_000, 'MAPPING_TABLE_SIZE')
                entries.append(text + '\n')
    require(consumed == expected_bytes, 'MAPPING_STREAM_SIZE')
    return ('# compiler: R8\n' if compiler else '') + ''.join(entries), digest.hexdigest()


def unavailable_mapping_files():
    return [{'file': name, 'present': None, 'regular': None, 'symlink': None,
             'sizeCategory': 'unavailable'} for name in MAPPING_FILES]


def mapping_file_states(mapping_dir):
    # Only fixed local file metadata: no contents, paths, timestamps or target reads.
    result = []
    for name in MAPPING_FILES:
        row = {'file': name, 'present': None, 'regular': None, 'symlink': None,
               'sizeCategory': 'unavailable'}
        try:
            info = (mapping_dir / name).lstat()
        except FileNotFoundError:
            row.update(present=False, regular=False, symlink=False, sizeCategory='absent')
        except OSError:
            pass
        else:
            regular, symlink = stat.S_ISREG(info.st_mode), stat.S_ISLNK(info.st_mode)
            category = 'not_regular'
            if regular:
                size = info.st_size
                if type(size) is not int or size < 0:
                    result.append(row)
                    continue
                category = ('0' if size == 0 else '0_32M' if size <= 32 * 1024 * 1024
                            else '32_128M' if size <= 128 * 1024 * 1024
                            else '128_256M' if size <= 256 * 1024 * 1024 else 'over256M')
            row.update(present=True, regular=regular, symlink=symlink, sizeCategory=category)
        result.append(row)
    return result


def closed_mapping_files(value):
    # Reconstruct a fixed alphabet at the output boundary; never serialize input rows.
    if type(value) is not list or len(value) != len(MAPPING_FILES):
        return unavailable_mapping_files()
    result = []
    keys = {'file', 'present', 'regular', 'symlink', 'sizeCategory'}
    for name, row in zip(MAPPING_FILES, value):
        if type(row) is not dict or set(row) != keys or type(row['file']) is not str or row['file'] != name:
            return unavailable_mapping_files()
        category = row['sizeCategory']
        if type(category) is not str:
            return unavailable_mapping_files()
        flags = (row['present'], row['regular'], row['symlink'])
        if category == 'unavailable':
            valid = all(flag is None for flag in flags)
        else:
            valid = all(type(flag) is bool for flag in flags) and (
                category == 'absent' and flags == (False, False, False)
                or category == 'not_regular' and flags in ((True, False, False), (True, False, True))
                or category in MAPPING_SIZE_CATEGORIES and flags == (True, True, False))
        if not valid:
            return unavailable_mapping_files()
        result.append({'file': name, 'present': flags[0], 'regular': flags[1],
                       'symlink': flags[2], 'sizeCategory': category})
    return result


def closed_failure(error):
    # No exception message, file content, class name or stack leaves this path.
    kinds = {ValueError: 'VALUE', KeyError: 'KEY', TypeError: 'TYPE',
             UnicodeDecodeError: 'ENCODING', FileNotFoundError: 'FILE_ABSENT',
             PermissionError: 'FILE_ACCESS', zipfile.BadZipFile: 'ZIP',
             subprocess.CalledProcessError: 'GIT_PROCESS', struct.error: 'BINARY'}
    result = {'schemaVersion': 1, 'status': 'refused',
              'reason': error.reason if isinstance(error, R8Refused) and error.reason in REASONS else 'UNCLASSIFIED',
              'exceptionKind': 'INVARIANT' if isinstance(error, R8Refused) else kinds.get(type(error), 'OTHER'),
              'uiValidated': False, 'storeBuild': False}
    if result['reason'] == 'MAPPING_FILE':
        result['mappingFiles'] = closed_mapping_files(getattr(error, 'mapping_files', None))
    return result


def dex_classes(data):
    # DEX header/string/type/class tables per the Android runtime format. The
    # actual binary comes from the APK, not an independently supplied name list.
    require(112 <= len(data) <= 64 * 1024 * 1024, 'DEX_SIZE')
    require(re.fullmatch(rb'dex\n0(?:3[5-9]|40)\x00', data[:8]) is not None, 'DEX_VERSION')
    u32 = lambda offset: struct.unpack_from('<I', data, offset)[0]
    require(u32(32) == len(data) and u32(36) == 112 and u32(40) == 0x12345678, 'DEX_HEADER')
    strings, strings_off = u32(56), u32(60)
    types, types_off = u32(64), u32(68)
    classes, classes_off = u32(96), u32(100)
    for count, offset, size in [(strings, strings_off, 4), (types, types_off, 4), (classes, classes_off, 32)]:
        require(0 < count <= 2_000_000 and offset >= 112 and offset + count * size <= len(data), 'DEX_TABLE_BOUNDS')
    result = set()
    for index in range(classes):
        type_id = u32(classes_off + index * 32)
        require(type_id < types, 'DEX_TYPE_INDEX')
        string_id = u32(types_off + type_id * 4)
        require(string_id < strings, 'DEX_STRING_INDEX')
        offset = u32(strings_off + string_id * 4)
        require(112 <= offset < len(data), 'DEX_STRING_OFFSET')
        for byte in range(5):
            require(offset < len(data), 'DEX_ULEB_BOUNDS')
            value = data[offset]
            offset += 1
            if value < 128:
                break
        else:
            raise R8Refused('DEX_ULEB_INVALID')
        end = data.find(b'\x00', offset, min(offset + 2048, len(data)))
        require(end > offset, 'DEX_STRING_TERMINATOR')
        name = data[offset:end].decode('utf-8', errors='strict')
        require(name.startswith('L') and name.endswith(';'), 'DEX_CLASS_DESCRIPTOR')
        result.add(name[1:-1].replace('/', '.'))
    require(len(result) == classes, 'DEX_DUPLICATE_CLASS')
    return result


def inspect_r8(mapping, configuration, plugins, classes):
    require('# compiler: R8' in mapping, 'R8_COMPILER_MARKER')
    require(not re.search(r'^\s*-(?:dontoptimize|dontshrink|dontobfuscate)(?:\s|$)', configuration, re.M), 'GLOBAL_OPTIMIZATION_DISABLED')
    pairs = re.findall(r'^(\S+) -> (\S+):$', mapping, re.M)
    translated = dict(pairs)
    require(len(pairs) > 0 and len(pairs) == len(translated), 'MAPPING_CLASS_ENTRIES')
    renamed = sum(before != after for before, after in pairs)
    require(renamed > 0, 'RENAMING_ABSENT')
    require(isinstance(plugins, list) and 1 <= len(plugins) <= 64, 'PLUGIN_LIST_SHAPE')
    names = [plugin['classpath'] for plugin in plugins]
    require(len(names) == len(set(names)), 'PLUGIN_DUPLICATE')
    require(all(re.fullmatch(r'[A-Za-z_$][A-Za-z0-9_$.]*', name) for name in names), 'PLUGIN_NAME_INVALID')
    require(all(name in classes and translated.get(name) == name for name in names), 'PLUGIN_NOT_PRESERVED')
    require('app.jolene.android.MainActivity' in classes, 'MAIN_ACTIVITY_ABSENT')
    return {'compiler': 'R8', 'mappedClasses': len(pairs), 'renamedClasses': renamed,
            'nativePluginsPreserved': len(names), 'definedDexClasses': len(classes),
            'globalDisablingOptionsAbsent': True, 'playOptimizationPercentage': None}


def main():
    require(os.environ.get('CI') == 'true' and os.environ.get('NATIVE_RECETTE') == '1'
            and os.environ.get('NATIVE_RECETTE_VARIANT') == 'optimized', 'CI_CONTEXT')
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True,
                                  env={**os.environ, 'GIT_NO_LAZY_FETCH': '1'}, stderr=subprocess.PIPE).strip()
    require(re.fullmatch(r'[a-f0-9]{40}', sha) is not None and os.environ.get('GIT_COMMIT_SHA') == sha, 'COMMIT_IDENTITY')
    require(not Path('android/keystore.properties').exists() and not Path('android/app/google-services.json').exists(), 'PRODUCTION_CONFIG_PRESENT')
    root = Path('android/app/build')
    apk = root / 'outputs/apk/recetteOptimized/app-recetteOptimized.apk'
    require(apk.is_file() and not apk.is_symlink() and apk.stat().st_size <= 256 * 1024 * 1024, 'APK_FILE')
    classes, dex_receipts = set(), []
    with zipfile.ZipFile(apk) as archive:
        entries = [entry for entry in archive.infolist() if re.fullmatch(r'classes(?:[2-9]|[1-9][0-9]+)?\.dex', entry.filename)]
        require(1 <= len(entries) <= 32 and len({entry.filename for entry in entries}) == len(entries), 'DEX_ARCHIVE_ENTRIES')
        require(sum(entry.file_size for entry in entries) <= 128 * 1024 * 1024, 'DEX_ARCHIVE_SIZE')
        for entry in entries:
            data = archive.read(entry)
            declared = dex_classes(data)
            require(not classes.intersection(declared), 'DEX_CROSS_FILE_DUPLICATE')
            classes.update(declared)
            dex_receipts.append({'file': entry.filename, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    mapping_dir = root / 'outputs/mapping/recetteOptimized'
    sizes = {}
    for name in ['mapping.txt', 'configuration.txt']:
        path = mapping_dir / name
        try:
            limit = MAPPING_STREAM_LIMIT if name == 'mapping.txt' else 32 * 1024 * 1024
            require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= limit, 'MAPPING_FILE')
            sizes[name] = path.stat().st_size
        except R8Refused as error:
            try:
                error.mapping_files = mapping_file_states(mapping_dir)
            except Exception:
                pass  # A diagnostic error must not replace the original refusal.
            raise
    mapping, mapping_sha = read_mapping(mapping_dir / 'mapping.txt', sizes['mapping.txt'])
    configuration = (mapping_dir / 'configuration.txt').read_text()
    plugins = json.loads(Path('android/app/src/main/assets/capacitor.plugins.json').read_text())
    metadata = json.loads((root / 'outputs/apk/recetteOptimized/output-metadata.json').read_text())
    require(metadata['applicationId'] == 'app.jolene.recette' and metadata['variantName'] == 'recetteOptimized', 'FIXTURE_IDENTITY')
    receipt = inspect_r8(mapping, configuration, plugins, classes)
    receipt.update({'sha': sha, 'variant': 'recetteOptimized', 'applicationId': 'app.jolene.recette', 'dex': dex_receipts,
                    'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                    'mappingSha256': mapping_sha,
                    'mappingBytes': sizes['mapping.txt'],
                    'configurationSha256': hashlib.sha256(configuration.encode()).hexdigest(),
                    'storeBuild': False, 'uiValidated': False})
    output = Path('test-results/android-native/r8-artifacts.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        try:
            diagnostic = Path('test-results/android-native/r8-failure.json')
            diagnostic.parent.mkdir(parents=True, exist_ok=True)
            diagnostic.write_text(json.dumps(closed_failure(error), sort_keys=True) + '\n')
        except Exception:
            pass  # The original refusal remains fatal even if diagnostics cannot be saved.
        raise SystemExit('ANDROID_R8_ARTIFACT_REFUSED') from None
