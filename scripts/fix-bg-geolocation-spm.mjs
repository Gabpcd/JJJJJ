// fix-bg-geolocation-spm.mjs — Corrige la contrainte capacitor-swift-pm
//
// @capacitor-community/background-geolocation@1.2.26 épingle
// `from: "7.0.0"` dans son Package.swift, incompatible avec Capacitor 8.2.0
// (conflit SPM avec capacitor-native-biometric qui exige 8.x).
//
// Contrairement à patch-package (qui échoue si le fichier n'est pas dans
// l'état exact attendu — problème de cache node_modules sur Vercel/CI), ce
// script est IDEMPOTENT : il réécrit la dépendance vers `"8.0.0" ..< "9.0.0"`
// quel que soit l'état actuel (original, déjà patché, ou cassé).
//
// Exécuté en postinstall. No-op si le package n'est pas installé (ex. CI web
// qui aurait élagué les optionalDependencies).

import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const FILE = 'node_modules/@capacitor-community/background-geolocation/Package.swift';

if (!existsSync(FILE)) {
  // Package absent → rien à faire (build web sans plugin natif)
  process.exit(0);
}

const TARGET = '"8.0.0" ..< "9.0.0"';
const src = readFileSync(FILE, 'utf8');

// Remplace n'importe quelle forme de contrainte sur capacitor-swift-pm
// dans le bloc .package(url: "...capacitor-swift-pm.git", <CONTRAINTE>)
const re = /(url:\s*"https:\/\/github\.com\/ionic-team\/capacitor-swift-pm\.git"\s*,\s*)(from:\s*"[^"]+"(?:\s*\.\.<\s*"[^"]+")?|"[^"]+"\s*\.\.<\s*"[^"]+")/;

if (!re.test(src)) {
  console.warn('[fix-bg-geolocation-spm] motif capacitor-swift-pm introuvable, fichier inchangé');
  process.exit(0);
}

const out = src.replace(re, `$1${TARGET}`);

if (out === src) {
  // Déjà à la bonne valeur
  process.exit(0);
}

writeFileSync(FILE, out, 'utf8');
console.log('[fix-bg-geolocation-spm] capacitor-swift-pm contraint à 8.0.0 ..< 9.0.0');
