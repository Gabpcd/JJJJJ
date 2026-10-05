import json
import unittest
import subprocess
import sys
from pathlib import Path
from xml.etree.ElementTree import ParseError
from project_accessibility import project, MAX_BYTES


def node(text='', desc='', package='app.jolene.recette', bounds='[0,0][20,20]', password='false', children=''):
    from xml.sax.saxutils import quoteattr
    attrs = {'text': text, 'content-desc': desc, 'package': package, 'bounds': bounds, 'password': password}
    return '<node ' + ' '.join(k+'='+quoteattr(v) for k,v in attrs.items()) + '>' + children + '</node>'


def tree(*nodes, rotation='0'):
    return ('<hierarchy rotation="'+rotation+'">'+''.join(nodes)+'</hierarchy>').encode()


class ProjectionTests(unittest.TestCase):
    def test_full_text_and_description_are_separate(self):
        r = project(tree(node('Bonjour, bienvenue'), node(desc='Préparer une mission')), 1080, 1920)
        self.assertTrue(r['markers']['greetingFull']['visibleFixtureText'])
        self.assertFalse(r['markers']['greetingFull']['desc'])
        self.assertTrue(r['markers']['etabPrepareMission']['visibleFixtureDesc'])

    def test_split_does_not_fabricate_full_label(self):
        r = project(tree(node('Bonjour, ', children=node('bienvenue'))), 1080, 1920)
        self.assertFalse(r['markers']['greetingFull']['text'])
        self.assertTrue(r['markers']['greetingPart']['visibleFixtureText'])
        self.assertTrue(r['markers']['welcomePart']['visibleFixtureText'])

    def test_evening_is_observed_without_normalizing(self):
        r = project(tree(node('Bonsoir, bienvenue'), node(desc=' Bonjour, bienvenue ')), 1080, 1920)
        self.assertTrue(r['markers']['greetingFull']['text'])
        self.assertFalse(r['markers']['greetingFull']['desc'])

    def test_foreign_package_cannot_satisfy_fixture(self):
        r = project(tree(node('Bonjour, bienvenue', package='other.fixture')), 1080, 1920)
        self.assertTrue(r['markers']['greetingFull']['text'])
        self.assertFalse(r['markers']['greetingFull']['fixtureText'])
        self.assertFalse(r['fixturePackagePresent'])

    def test_empty_or_offscreen_bounds_cannot_satisfy_visibility(self):
        for bounds in ('[0,0][0,0]', '[0,2000][20,2020]', '[-5,0][20,20]'):
            r = project(tree(node('bienvenue', bounds=bounds)), 1080, 1920)
            self.assertTrue(r['markers']['welcomePart']['fixtureText'])
            self.assertFalse(r['markers']['welcomePart']['visibleFixtureText'])

    def test_rotation_is_applied_to_physical_screen(self):
        r = project(tree(node('bienvenue', bounds='[1500,0][1600,20]'), rotation='1'), 1080, 1920)
        self.assertTrue(r['markers']['welcomePart']['visibleFixtureText'])

    def test_password_field_is_never_marker_evidence(self):
        r = project(tree(node('bienvenue', password='true')), 1080, 1920)
        self.assertFalse(r['markers']['welcomePart']['text'])

    def test_canaries_unknown_text_and_resources_never_leave_projection(self):
        canary = 'PRIVATE-CANARY-password-note-token@example.invalid'
        raw = tree(node(canary, desc=canary, package=canary)).replace(b'<node ', b'<node resource-id="PRIVATE-RESOURCE" ')
        encoded = json.dumps(project(raw, 1080, 1920))
        self.assertNotIn(canary, encoded)
        self.assertNotIn('PRIVATE-RESOURCE', encoded)
        self.assertNotIn('bounds', encoded)

    def test_truncation_dtd_entities_invalid_utf8_are_rejected(self):
        cases = [tree(node())[:-5], b'<!DOCTYPE hierarchy [<!ENTITY x "secret">]>'+tree(node()),
                 tree(node()).replace(b'text=""', b'text="&unknown;"'), tree(node()).replace(b'text=""', b'text="\xff"'),
                 tree(node())+b'garbage', b'x'*(MAX_BYTES+1)]
        for raw in cases:
            with self.assertRaises((ValueError, UnicodeError, ParseError)):
                project(raw, 1080, 1920)

    def test_unknown_node_attribute_and_malformed_bounds_fail(self):
        for raw in (tree(node()).replace(b'<node ', b'<other '), tree(node()).replace(b'<node ', b'<node arbitrary="x" '),
                    tree(node(bounds='canary')), tree(node()).replace(b'password="false"', b''), tree(node(password='maybe'))):
            with self.assertRaises((ValueError, ParseError)):
                project(raw, 1080, 1920)

    def test_depth_and_node_count_limits(self):
        for raw in (tree(node(children=node()*4096)), tree(node(children=('<node text="" content-desc="" package="" bounds="[0,0][0,0]" password="false">'*65)+('</node>'*65)))):
            with self.assertRaises(ValueError):
                project(raw, 1080, 1920)

    def test_cli_failures_are_closed_without_xml_or_traceback(self):
        for raw in (b'<PRIVATE-CANARY', b'\xff', b'<!DOCTYPE a [<!ENTITY x "PRIVATE-CANARY">]><a/>'):
            r = subprocess.run([sys.executable, str(Path(__file__).with_name('project_accessibility.py')), '1080', '1920'], input=raw, capture_output=True, timeout=3)
            self.assertEqual(r.returncode, 1)
            self.assertEqual(json.loads(r.stdout), {'error': 'INVALID_XML'})
            self.assertEqual(r.stderr, b'')

    def test_cli_success_outputs_only_closed_projection(self):
        raw = tree(node('bienvenue'), node('PRIVATE-CANARY'))
        r = subprocess.run([sys.executable, str(Path(__file__).with_name('project_accessibility.py')), '1080', '1920'], input=raw, capture_output=True, timeout=3)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(json.loads(r.stdout), project(raw, 1080, 1920))
        self.assertNotIn(b'PRIVATE-CANARY', r.stdout)
        self.assertEqual(r.stderr, b'')


if __name__ == '__main__':
    unittest.main()
