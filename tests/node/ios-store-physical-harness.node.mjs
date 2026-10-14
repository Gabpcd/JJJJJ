import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const checkout = fileURLToPath(new URL('../..', import.meta.url));
const generator = path.join(checkout, 'scripts/native/prepare-ios-store-physical.rb');
const appProject = path.join(checkout, 'ios/App/App.xcodeproj/project.pbxproj');
const hash = filename => createHash('sha256').update(readFileSync(filename)).digest('hex');

test('le banc physique ne contient et ne modifie aucun produit Jolene store', () => {
  const initialAppProject = hash(appProject);
  const temporary = mkdtempSync(path.join(os.tmpdir(), 'jolene-physical-generator-'));
  const output = path.join(temporary, 'harness');
  try {
    const generated = spawnSync('ruby', [generator, '--output', output], { encoding: 'utf8', cwd: checkout });
    assert.equal(generated.status, 0, generated.stderr);
    const manifest = JSON.parse(generated.stdout);
    assert.equal(manifest.installedAppUnderTest, 'app.jolene');
    assert.equal(manifest.buildExecuted, false);
    assert.equal(manifest.deviceAccessed, false);
    assert.equal(manifest.screenshotsOptIn, false);
    assert.equal(hash(appProject), initialAppProject, 'le projet produit doit rester identique');

    // Lire le modèle Xcode réel, pas seulement rechercher les chaînes du script.
    const inspected = spawnSync('ruby', ['-rjson', '-rxcodeproj', '-e', `
      p = Xcodeproj::Project.open(ARGV.fetch(0))
      puts JSON.generate(p.targets.map { |t| {
        name: t.name, type: t.product_type, dependencies: t.dependencies.map { |d| d.target.name },
        settings: t.build_configurations.map { |c| c.build_settings },
        shellPhases: t.shell_script_build_phases.length
      } })
    `, manifest.project], { encoding: 'utf8' });
    assert.equal(inspected.status, 0, inspected.stderr);
    const targets = JSON.parse(inspected.stdout);
    assert.equal(targets.length, 2);
    assert.deepEqual(targets.map(t => t.name).sort(), ['JolenePhysicalHost', 'JoleneStorePhysicalUITests']);
    const host = targets.find(t => t.type === 'com.apple.product-type.application');
    const ui = targets.find(t => t.type === 'com.apple.product-type.bundle.ui-testing');
    assert.ok(host && ui);
    assert.deepEqual(host.dependencies, []);
    assert.deepEqual(ui.dependencies, [host.name]);
    for (const target of targets) {
      assert.equal(target.shellPhases, 0, 'aucune commande de livraison ou OTA');
      for (const settings of target.settings) {
        assert.notEqual(settings.PRODUCT_BUNDLE_IDENTIFIER, 'app.jolene');
        assert.equal(settings.DEVELOPMENT_TEAM, 'GDU5AA28M9');
        assert.equal(settings.CODE_SIGN_STYLE, 'Automatic');
        assert.equal(settings['CODE_SIGN_IDENTITY[sdk=iphoneos*]'], 'Apple Development');
      }
    }
    const plan = JSON.parse(readFileSync(path.join(output, 'JoleneStorePhysical.xctestplan'), 'utf8'));
    assert.equal(plan.defaultOptions.systemAttachmentLifetime, 'keepNever');
    assert.equal(plan.defaultOptions.userAttachmentLifetime, 'keepAlways');
    assert.equal(plan.testTargets[0].parallelizable, false);
    const scheme = readFileSync(path.join(manifest.project, 'xcshareddata/xcschemes/JoleneStorePhysical.xcscheme'), 'utf8');
    assert.doesNotMatch(scheme, /buildForArchiving="YES"|App\.xcodeproj|\.\.\//);
    assert.match(scheme, /container:JoleneStorePhysical\.xctestplan/);
    assert.equal(readFileSync(path.join(output, ui.name, 'StorePhysicalTests.swift'), 'utf8'),
      readFileSync(path.join(checkout, 'tests/native/ios/StorePhysicalTests.swift'), 'utf8'));

    const again = spawnSync('ruby', [generator, '--output', output], { encoding: 'utf8', cwd: checkout });
    assert.notEqual(again.status, 0, 'ne jamais écraser un banc et ses preuves existants');
    assert.match(again.stderr, /existe déjà/);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});
