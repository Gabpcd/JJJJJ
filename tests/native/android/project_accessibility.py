"""Closed projection of a terminal, synthetic Android accessibility dump."""
import json
import re
import sys
import xml.etree.ElementTree as ET

MAX_BYTES = 1024 * 1024
PACKAGE = 'app.jolene.recette'
MARKERS = {
    'greetingFull': re.compile(r'(Bonjour|Bonsoir), bienvenue'),
    'greetingPart': re.compile(r'(Bonjour|Bonsoir), ?'),
    'welcomePart': re.compile(r'bienvenue'),
    'soignantExplanation': re.compile(re.escape('Explorez les missions librement. Votre profil sera demandé lorsque vous souhaiterez candidater.')),
    'etabPrepareMission': re.compile(re.escape('Préparer une mission')),
}
ATTRS = {'index', 'text', 'resource-id', 'class', 'package', 'content-desc',
         'checkable', 'checked', 'clickable', 'enabled', 'focusable', 'focused',
         'scrollable', 'long-clickable', 'password', 'selected', 'bounds', 'NAF'}
BOOL_ATTRS = ATTRS - {'index', 'text', 'resource-id', 'class', 'package', 'content-desc', 'bounds'}


def project(raw, width, height):
    if not isinstance(raw, bytes) or not 0 < len(raw) <= MAX_BYTES:
        raise ValueError('INVALID_XML')
    if type(width) is not int or type(height) is not int or not (1 <= width <= 16384 and 1 <= height <= 16384):
        raise ValueError('INVALID_XML')
    text = raw.decode('utf-8', errors='strict')
    if re.search(r'<!DOCTYPE|<!ENTITY|<!--', text, re.I):
        raise ValueError('INVALID_XML')
    root = ET.fromstring(text)
    if root.tag != 'hierarchy' or set(root.attrib) != {'rotation'} or root.attrib['rotation'] not in {'0', '1', '2', '3'}:
        raise ValueError('INVALID_XML')
    if root.attrib['rotation'] in {'1', '3'}:
        width, height = height, width
    result = {'schema': 1, 'fixturePackagePresent': False, 'fixtureVisibleBoundsPresent': False,
              'markers': {name: {key: False for key in ('text', 'desc', 'fixtureText', 'fixtureDesc', 'visibleFixtureText', 'visibleFixtureDesc')} for name in MARKERS}}
    count = 0
    pending = [(child, 1) for child in root]
    if (root.text or '').strip() or (root.tail or '').strip() or not pending:
        raise ValueError('INVALID_XML')
    while pending:
        node, depth = pending.pop()
        count += 1
        if depth > 64 or count > 4096 or node.tag != 'node' or not set(node.attrib) <= ATTRS:
            raise ValueError('INVALID_XML')
        if not {'text', 'content-desc', 'package', 'bounds', 'password'} <= set(node.attrib):
            raise ValueError('INVALID_XML')
        if (node.text or '').strip() or (node.tail or '').strip() or any(len(v) > 8192 for v in node.attrib.values()):
            raise ValueError('INVALID_XML')
        if any(node.attrib[k] not in {'true', 'false'} for k in BOOL_ATTRS & node.attrib.keys()):
            raise ValueError('INVALID_XML')
        match = re.fullmatch(r'\[(-?\d{1,6}),(-?\d{1,6})\]\[(-?\d{1,6}),(-?\d{1,6})\]', node.attrib['bounds'])
        if not match:
            raise ValueError('INVALID_XML')
        x1, y1, x2, y2 = map(int, match.groups())
        visible = 0 <= x1 < x2 <= width and 0 <= y1 < y2 <= height
        fixture = node.attrib['package'] == PACKAGE
        result['fixturePackagePresent'] |= fixture
        result['fixtureVisibleBoundsPresent'] |= fixture and visible
        # Sensitive fields are never considered marker evidence, even in this fixture.
        if node.attrib['password'] == 'false':
            for name, regex in MARKERS.items():
                for attribute, field in (('text', 'Text'), ('content-desc', 'Desc')):
                    matched = regex.fullmatch(node.attrib[attribute]) is not None
                    result['markers'][name][field.lower()] |= matched
                    result['markers'][name]['fixture' + field] |= matched and fixture
                    result['markers'][name]['visibleFixture' + field] |= matched and fixture and visible
        pending.extend((child, depth + 1) for child in node)
    return result


def main():
    try:
        if len(sys.argv) != 3 or not all(re.fullmatch(r'[1-9]\d{0,4}', value) for value in sys.argv[1:]):
            raise ValueError('INVALID_XML')
        result = project(sys.stdin.buffer.read(MAX_BYTES + 1), int(sys.argv[1]), int(sys.argv[2]))
    except (ValueError, UnicodeError, ET.ParseError, OverflowError, RecursionError):
        # Never emit the parser error, XML, user strings or coordinates.
        print('{"error":"INVALID_XML"}')
        return 1
    print(json.dumps(result, ensure_ascii=True, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    sys.exit(main())
