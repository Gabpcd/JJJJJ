"""Inspect the optimized fixture APK, never sign/install/publish it or run Gradle."""
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zipfile


def require(ok):
    if not ok:
        raise ValueError('ANDROID_R8_ARTIFACT_REFUSED')


def dex_classes(data):
    # DEX header/string/type/class tables per the Android runtime format. The
    # actual binary comes from the APK, not an independently supplied name list.
    require(112 <= len(data) <= 64 * 1024 * 1024)
    require(re.fullmatch(rb'dex\n0(?:3[5-9]|40)\x00', data[:8]) is not None)
    u32 = lambda offset: struct.unpack_from('<I', data, offset)[0]
    require(u32(32) == len(data) and u32(36) == 112 and u32(40) == 0x12345678)
    strings, strings_off = u32(56), u32(60)
    types, types_off = u32(64), u32(68)
    classes, classes_off = u32(96), u32(100)
    for count, offset, size in [(strings, strings_off, 4), (types, types_off, 4), (classes, classes_off, 32)]:
        require(0 < count <= 2_000_000 and offset >= 112 and offset + count * size <= len(data))
    result = set()
    for index in range(classes):
        type_id = u32(classes_off + index * 32)
        require(type_id < types)
        string_id = u32(types_off + type_id * 4)
        require(string_id < strings)
        offset = u32(strings_off + string_id * 4)
        require(112 <= offset < len(data))
        for byte in range(5):
            require(offset < len(data))
            value = data[offset]
            offset += 1
            if value < 128:
                break
        else:
            raise ValueError('ANDROID_R8_ARTIFACT_REFUSED')
        end = data.find(b'\x00', offset, min(offset + 2048, len(data)))
        require(end > offset)
        name = data[offset:end].decode('utf-8', errors='strict')
        require(name.startswith('L') and name.endswith(';'))
        result.add(name[1:-1].replace('/', '.'))
    require(len(result) == classes)
    return result


def inspect_r8(mapping, configuration, plugins, classes):
    require('# compiler: R8' in mapping)
    require(not re.search(r'^\s*-(?:dontoptimize|dontshrink|dontobfuscate)(?:\s|$)', configuration, re.M))
    pairs = re.findall(r'^(\S+) -> (\S+):$', mapping, re.M)
    translated = dict(pairs)
    require(len(pairs) > 0 and len(pairs) == len(translated))
    renamed = sum(before != after for before, after in pairs)
    require(renamed > 0)
    require(isinstance(plugins, list) and 1 <= len(plugins) <= 64)
    names = [plugin['classpath'] for plugin in plugins]
    require(len(names) == len(set(names)))
    require(all(re.fullmatch(r'[A-Za-z_$][A-Za-z0-9_$.]*', name) for name in names))
    require(all(name in classes and translated.get(name) == name for name in names))
    require('app.jolene.android.MainActivity' in classes)
    return {'compiler': 'R8', 'mappedClasses': len(pairs), 'renamedClasses': renamed,
            'nativePluginsPreserved': len(names), 'definedDexClasses': len(classes),
            'globalDisablingOptionsAbsent': True, 'playOptimizationPercentage': None}


def main():
    require(os.environ.get('CI') == 'true' and os.environ.get('NATIVE_RECETTE') == '1'
            and os.environ.get('NATIVE_RECETTE_VARIANT') == 'optimized')
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True,
                                  env={**os.environ, 'GIT_NO_LAZY_FETCH': '1'}, stderr=subprocess.PIPE).strip()
    require(re.fullmatch(r'[a-f0-9]{40}', sha) is not None and os.environ.get('GIT_COMMIT_SHA') == sha)
    require(not Path('android/keystore.properties').exists() and not Path('android/app/google-services.json').exists())
    root = Path('android/app/build')
    apk = root / 'outputs/apk/recetteOptimized/app-recetteOptimized.apk'
    require(apk.is_file() and not apk.is_symlink() and apk.stat().st_size <= 256 * 1024 * 1024)
    classes, dex_receipts = set(), []
    with zipfile.ZipFile(apk) as archive:
        entries = [entry for entry in archive.infolist() if re.fullmatch(r'classes(?:[2-9]|[1-9][0-9]+)?\.dex', entry.filename)]
        require(1 <= len(entries) <= 32 and len({entry.filename for entry in entries}) == len(entries))
        require(sum(entry.file_size for entry in entries) <= 128 * 1024 * 1024)
        for entry in entries:
            data = archive.read(entry)
            declared = dex_classes(data)
            require(not classes.intersection(declared))
            classes.update(declared)
            dex_receipts.append({'file': entry.filename, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    mapping_dir = root / 'outputs/mapping/recetteOptimized'
    texts = {}
    for name in ['mapping.txt', 'configuration.txt']:
        path = mapping_dir / name
        require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= 32 * 1024 * 1024)
        texts[name] = path.read_text()
    plugins = json.loads(Path('android/app/src/main/assets/capacitor.plugins.json').read_text())
    metadata = json.loads((root / 'outputs/apk/recetteOptimized/output-metadata.json').read_text())
    require(metadata['applicationId'] == 'app.jolene.recette' and metadata['variantName'] == 'recetteOptimized')
    receipt = inspect_r8(texts['mapping.txt'], texts['configuration.txt'], plugins, classes)
    receipt.update({'sha': sha, 'variant': 'recetteOptimized', 'applicationId': 'app.jolene.recette', 'dex': dex_receipts,
                    'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                    'mappingSha256': hashlib.sha256(texts['mapping.txt'].encode()).hexdigest(),
                    'configurationSha256': hashlib.sha256(texts['configuration.txt'].encode()).hexdigest(),
                    'storeBuild': False, 'uiValidated': False})
    output = Path('test-results/android-native/r8-artifacts.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        raise SystemExit('ANDROID_R8_ARTIFACT_REFUSED') from None
