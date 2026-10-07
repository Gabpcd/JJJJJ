"""Pure structural witnesses only: these bytes are not a compiled/runnable APK."""
import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('r8', Path(__file__).resolve().parents[3] / 'scripts/native/check_android_r8.py')
r8 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r8)


def dex_witness(names):
    count = len(names)
    strings_off, types_off, classes_off = 112, 112 + 4 * count, 112 + 8 * count
    data = bytearray(classes_off + 32 * count)
    data[:8] = b'dex\n038\0'
    for offset, value in [(36, 112), (40, 0x12345678), (56, count), (60, strings_off),
                          (64, count), (68, types_off), (96, count), (100, classes_off)]:
        struct.pack_into('<I', data, offset, value)
    for index, name in enumerate(names):
        encoded = ('L' + name.replace('.', '/') + ';').encode()
        assert len(encoded) < 128
        struct.pack_into('<I', data, strings_off + 4 * index, len(data))
        struct.pack_into('<I', data, types_off + 4 * index, index)
        struct.pack_into('<I', data, classes_off + 32 * index, index)
        data.extend(bytes([len(encoded)]) + encoded + b'\0')
    struct.pack_into('<I', data, 32, len(data))
    return bytes(data)


class R8Tests(unittest.TestCase):
    def test_reads_actual_class_table_and_refuses_invalid_tables(self):
        binary = dex_witness(['example.Plugin', 'app.jolene.android.MainActivity'])
        self.assertEqual(r8.dex_classes(binary), {'example.Plugin', 'app.jolene.android.MainActivity'})
        for offset, invalid in [(32, 0), (40, 0), (96, 999999), (100, len(binary) + 1)]:
            changed = bytearray(binary)
            struct.pack_into('<I', changed, offset, invalid)
            with self.assertRaises(ValueError): r8.dex_classes(changed)

    def test_proves_renaming_and_preserved_plugin_without_claiming_play_percentage(self):
        summary = r8.inspect_r8('# compiler: R8\nexample.Plugin -> example.Plugin:\nexample.Helper -> a.b:\n',
                                 '-keep class example.Plugin { *; }', [{'classpath': 'example.Plugin'}],
                                 {'example.Plugin', 'app.jolene.android.MainActivity', 'a.b'})
        self.assertEqual(summary['renamedClasses'], 1)
        self.assertIsNone(summary['playOptimizationPercentage'])

    def test_refuses_each_global_disabling_flag(self):
        for option in ['dontoptimize', 'dontshrink', 'dontobfuscate']:
            with self.assertRaises(ValueError):
                r8.inspect_r8('# compiler: R8\na -> b:\n', '-' + option, [{'classpath': 'example.Plugin'}], set())

    def test_refuses_removed_or_renamed_plugin_and_absent_r8_renaming(self):
        for mapping, classes in [
            ('# compiler: R8\nexample.Plugin -> p:\n', {'p', 'app.jolene.android.MainActivity'}),
            ('# compiler: R8\nexample.Plugin -> example.Plugin:\na -> b:\n', {'app.jolene.android.MainActivity'}),
            ('# compiler: R8\nexample.Plugin -> example.Plugin:\n', {'example.Plugin', 'app.jolene.android.MainActivity'}),
        ]:
            with self.assertRaises(ValueError):
                r8.inspect_r8(mapping, '', [{'classpath': 'example.Plugin'}], classes)


if __name__ == '__main__':
    unittest.main()
