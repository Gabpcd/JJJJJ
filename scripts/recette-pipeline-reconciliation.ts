#!/usr/bin/env npx tsx
/**
 * recette-pipeline-reconciliation.ts — 9.1
 *
 * Vérifie que le KPI « À valider » du pipeline Revenus == la liste de destination
 * (onglet Historique filtré, présences en attente de validation étab). Les deux
 * doivent lire la MÊME condition : le miroir du gate 7b-B. Si ça diverge, c'est
 * la source du KPI qu'on corrige, pas la liste.
 *
 * Usage :
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *   RECETTE_SOIGNANT_ID=<uuid seed:demo> npx tsx scripts/recette-pipeline-reconciliation.ts
 *
 * Sortie : PASS si les deux ensembles de missions coïncident, FAIL sinon (avec
 * les ids en écart). Code retour 2 si FAIL.
 */
import { createClient } from '@supabase/supabase-js';

const URL = process.env.SUPABASE_URL || '';
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const SOIGNANT = process.env.RECETTE_SOIGNANT_ID || '';

if (!URL || !SERVICE || !SOIGNANT) {
  console.error('Requis : SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, RECETTE_SOIGNANT_ID');
  process.exit(1);
}

const db = createClient(URL, SERVICE, { auth: { persistSession: false } });

async function main() {
  // ── Côté LISTE (destination) : présences à pointage complet non validées,
  //    sur missions TERMINEE — exactement le filtre a_valider de PresencesSoignant. ──
  const { data: presences } = await db
    .from('presences')
    .select('mission_id, valide_par_etablissement, pointage_depart_le, missions!inner(statut, soignant_assigne_id)')
    .eq('soignant_id', SOIGNANT);
  const listeSet = new Set(
    ((presences as any[]) || [])
      .filter((p) => !p.valide_par_etablissement && p.pointage_depart_le
        && p.missions?.statut === 'TERMINEE'
        && p.missions?.soignant_assigne_id === SOIGNANT)
      .map((p) => p.mission_id),
  );

  // ── Côté KPI (Revenus) : missions TERMINEE du soignant sans facture ni
  //    paiement (= présences pas encore validées, cf. gate 7b-B). ──
  const { data: missions } = await db
    .from('missions')
    .select('id, statut, facture_id')
    .eq('soignant_assigne_id', SOIGNANT)
    .eq('statut', 'TERMINEE');
  const missionIds = ((missions as any[]) || []).map((m) => m.id);

  const { data: factures } = await db
    .from('factures_honoraires')
    .select('mission_id, statut')
    .in('mission_id', missionIds.length ? missionIds : ['00000000-0000-0000-0000-000000000000']);
  const factureParMission = new Map<string, string>();
  ((factures as any[]) || []).forEach((f) => factureParMission.set(f.mission_id, f.statut));

  const { data: paiements } = await db
    .from('paiements_soignant')
    .select('mission_id')
    .eq('soignant_id', SOIGNANT);
  const missionsPayees = new Set(((paiements as any[]) || []).map((p) => p.mission_id));

  const kpiSet = new Set(
    ((missions as any[]) || [])
      .filter((m) => !factureParMission.has(m.id) && !missionsPayees.has(m.id))
      .map((m) => m.id),
  );

  // ── Comparaison ──
  const manqueDansListe = [...kpiSet].filter((id) => !listeSet.has(id));
  const manqueDansKpi = [...listeSet].filter((id) => !kpiSet.has(id));

  console.log(`KPI « À valider » : ${kpiSet.size} mission(s)`);
  console.log(`Liste destination : ${listeSet.size} mission(s)`);

  if (manqueDansListe.length === 0 && manqueDansKpi.length === 0) {
    console.log('✅ PASS — KPI et liste coïncident (même condition = miroir gate 7b-B).');
    return;
  }
  console.error('❌ FAIL — divergence KPI ↔ liste :');
  if (manqueDansListe.length) console.error(`  Dans le KPI mais absentes de la liste : ${manqueDansListe.join(', ')}`);
  if (manqueDansKpi.length) console.error(`  Dans la liste mais absentes du KPI : ${manqueDansKpi.join(', ')}`);
  console.error('→ Corriger la SOURCE du KPI (pipeline MesGains), pas la liste.');
  process.exit(2);
}

main().catch((e) => { console.error('Échec recette :', e); process.exit(1); });
