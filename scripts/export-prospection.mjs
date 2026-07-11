#!/usr/bin/env node
// Export CSV des ACTIFS DE PROSPECTION (lecture seule) → exports/prospection/.
//
// ⚠️ Ces données sont des ACTIFS DE PRODUCTION, jamais des données de test :
// prospects_etablissements (~64k), prospects_soignants (~245k, PII), sales_groupes.
// Aucune purge/archivage ne les touche (cf. addendum MODE AUTONOME).
//
// La PII n'est JAMAIS tirée à travers un LLM : ce script se connecte
// directement à Postgres et streame vers des fichiers. Destination : Cowork.
//
// Usage : SUPABASE_DB_URL='postgres://…' node scripts/export-prospection.mjs
//
// Requiert `pg` (déjà en devDependencies).

import { Client } from 'pg';
import { mkdirSync, createWriteStream } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'exports', 'prospection');

function csvCell(v) {
  if (v === null || v === undefined) return '';
  const s = String(v);
  return /[",\n;]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

// Chaque export = (fichier, en-têtes lisibles, requête). Les colonnes suivent le
// périmètre demandé (nom/type/zone/contact/statut ; profession/zone/canal ;
// nom/profession/taille/lien/règles).
const EXPORTS = [
  {
    file: 'etablissements.csv',
    headers: ['nom', 'type', 'finess', 'siret', 'departement', 'ville', 'code_postal', 'telephone', 'email', 'favori', 'contacte_le'],
    query: `SELECT nom, type_jolene AS type, finess, siret, departement, ville, code_postal, telephone, email, favori, email_envoye_le AS contacte_le FROM public.prospects_etablissements ORDER BY departement, ville, nom`,
  },
  {
    file: 'soignants.csv',
    headers: ['nom', 'prenom', 'profession', 'departement', 'ville', 'telephone', 'email', 'canal', 'est_etudiant', 'ecole', 'contacte_le'],
    query: `SELECT nom, prenom, profession, departement, ville, telephone, email, enseigne AS canal, est_etudiant, ecole, email_envoye_le AS contacte_le FROM public.prospects_soignants ORDER BY profession, departement, nom`,
  },
  {
    // Groupes Facebook / réseaux (table sales_groupes). Colonnes sélectionnées
    // dynamiquement : « taille » / « regles_pub » n'existent que si présentes.
    file: 'groupes-sociaux.csv',
    dynamic: 'sales_groupes',
    prefer: ['nom', 'plateforme', 'profession', 'region', 'url', 'nb_membres', 'taille', 'regles_pub', 'regles', 'statut', 'favori'],
  },
];

async function main() {
  const url = process.env.SUPABASE_DB_URL;
  if (!url) {
    console.error('❌ SUPABASE_DB_URL manquant. Usage : SUPABASE_DB_URL=… node scripts/export-prospection.mjs');
    process.exit(1);
  }
  mkdirSync(OUT_DIR, { recursive: true });
  const client = new Client({ connectionString: url });
  await client.connect();

  for (const exp of EXPORTS) {
    let headers = exp.headers;
    let query = exp.query;
    if (exp.dynamic) {
      const { rows: cols } = await client.query(
        `SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1`,
        [exp.dynamic],
      );
      const have = new Set(cols.map((c) => c.column_name));
      headers = exp.prefer.filter((c) => have.has(c));
      if (headers.length === 0) { console.warn(`⚠️ ${exp.dynamic} introuvable/vide — ${exp.file} ignoré.`); continue; }
      query = `SELECT ${headers.join(', ')} FROM public.${exp.dynamic} ORDER BY 1`;
    }
    const path = join(OUT_DIR, exp.file);
    const out = createWriteStream(path, { encoding: 'utf8' });
    out.write(headers.join(',') + '\n');
    const res = await client.query(query);
    for (const row of res.rows) {
      out.write(headers.map((h) => csvCell(row[h])).join(',') + '\n');
    }
    await new Promise((r) => out.end(r));
    console.log(`✅ ${exp.file} : ${res.rowCount} lignes → ${path}`);
  }

  await client.end();
  console.log('Terminé. Ces fichiers sont des actifs de prospection — ne pas purger.');
}

main().catch((e) => { console.error(e); process.exit(1); });
