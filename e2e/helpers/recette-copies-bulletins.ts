import { createHash, randomUUID } from 'node:crypto';
import { jsPDF } from 'jspdf';
import { expect, type Page } from '@playwright/test';
import { ids as etabIds, etablissement } from './recette-complete-etablissement';
import { ids as soignantIds } from './recette-complete-soignant';

export function pdfFictif(texte = 'Copie fictive de recette - aucun bulletin réel') {
  const pdf = new jsPDF(); pdf.text(texte, 20, 20);
  const buffer = Buffer.from(pdf.output('arraybuffer'));
  return { name: 'copie-recette.pdf', mimeType: 'application/pdf', buffer,
    sha256: createHash('sha256').update(buffer).digest('hex') };
}
export const destinataireCopie = { id: soignantIds.user, prenom: 'Camille', nom: 'Recette' };
export const missionsCopies = [1, 2].map(n => ({
  id: `79000000-0000-4000-8000-00000000008${n}`, intitule: `Mission salariée ${n}`,
  etablissement_id: etabIds.etab, soignant_assigne_id: soignantIds.user,
  debut_le: `2026-09-${14 + n}T08:00:00.000Z`, fin_le: `2026-09-${14 + n}T16:00:00.000Z`,
  type_contrat_applique: 'SALARIE', statut: 'TERMINEE', type_paiement_soignant: 'BULLETIN_PAIE',
}));
type Copie = Record<string, any>;
/** Contrats simulés : les contrôles RLS/Storage réels sont exécutés séparément. */
export function recetteCopies() {
  const state = {
    copies: [] as Copie[], fichiers: new Map<string, ReturnType<typeof pdfFictif>>(),
    intentions: new Map<string, Copie>(), uploads: new Map<string, Buffer>(),
    appels: [] as { nom: string; body: any }[],
    panneListe: false, panneUpload: false, pannePublication: false,
    perdreReponsePublication: false, panneLecture: false, lectureCorrompue: false,
    listeInvalide: false,
  };
  function enregistrerPdf(pdf = pdfFictif()) { state.fichiers.set(pdf.sha256, pdf); return pdf; }
  function copiePubliee(pdf = enregistrerPdf(), overrides: Copie = {}) {
    const copie = {
      id: randomUUID(), etablissement_id: etabIds.etab, etablissement_nom: etablissement.nom,
      soignant_id: soignantIds.user, soignant_nom: 'Recette', soignant_prenom: 'Camille',
      periode_debut: '2026-09-01', periode_fin: '2026-09-30', statut: 'PUBLIEE',
      publie_le: '2026-09-29T10:00:00.000Z', remplace_id: null, motif_remplacement: null,
      version: 1, mission_ids: missionsCopies.map(m => m.id), taille_octets: pdf.buffer.length,
      sha256: pdf.sha256, signalee: false, ...overrides,
    };
    state.copies.push(copie); return copie;
  }
  async function installer(page: Page) {
    await page.route('**/rest/v1/rpc/fn_mes_soignants_etablissement', route => route.fulfill({ json: [destinataireCopie] }));
    await page.route('**/rest/v1/missions*', route => {
      const url = new URL(route.request().url());
      if (url.searchParams.get('select') !== 'id,intitule,debut_le,fin_le,soignant_assigne_id') return route.fallback();
      expect(url.searchParams.get('etablissement_id')).toBe(`eq.${etabIds.etab}`);
      expect(url.searchParams.get('type_contrat_applique')).toBe('eq.SALARIE');
      expect(url.searchParams.get('statut')).toBe('not.in.(OUVERTE,EXPIREE)');
      return route.fulfill({ json: missionsCopies });
    });
    await page.route('**/rest/v1/rpc/*copie*bulletin*', async route => {
      const nom = new URL(route.request().url()).pathname.split('/').pop()!;
      if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204 });
      const body = route.request().postDataJSON(); state.appels.push({ nom, body });
      if (nom === 'fn_lister_copies_bulletins') {
        if (state.panneListe) return route.fulfill({ status: 503, json: { message: 'Recette indisponible' } });
        return route.fulfill({ json: state.listeInvalide ? [{ id: 'incomplet' }] : state.copies });
      }
      if (nom === 'fn_reserver_copie_bulletin') {
        expect(body.p_soignant_id).toBe(soignantIds.user);
        expect(body.p_etablissement_id).toBe(etabIds.etab);
        expect(body.p_sha256_attendu).toMatch(/^[a-f0-9]{64}$/);
        expect(body.p_taille_attendue).toBe(state.fichiers.get(body.p_sha256_attendu)?.buffer.length);
        let reservation = state.intentions.get(body.p_idempotence);
        if (reservation?.statut === 'RETIREE') return route.fulfill({ status: 400, json: { code: '55000', message: 'COPIE_RETIREE' } });
        if (!reservation) {
          const id = randomUUID(); const precedent = state.copies.find(c => c.id === body.p_remplace_id);
          reservation = { id, statut: 'RESERVEE', version: precedent ? precedent.version + 1 : 1,
            bucket: 'copies-bulletins-paie', storage_path: `${id}/original.pdf`, body };
          state.intentions.set(body.p_idempotence, reservation);
        } else expect(reservation.body).toEqual(body);
        return route.fulfill({ json: reservation });
      }
      const copie = state.copies.find(c => c.id === body.p_copie_id); expect(copie).toBeTruthy();
      if (nom === 'fn_signaler_copie_bulletin') { copie!.signalee = true; if (body.p_motif === 'DESTINATAIRE') copie!.statut = 'RETIREE'; }
      else if (nom === 'fn_retirer_copie_bulletin') copie!.statut = 'RETIREE';
      else throw new Error(`RPC non préparée ${nom}`);
      if (copie!.statut === 'RETIREE') for (const intention of state.intentions.values()) if (intention.id === copie!.id) intention.statut = 'RETIREE';
      return route.fulfill({ json: { ok: true } });
    });
    await page.route('**/storage/v1/object/copies-bulletins-paie/**', async route => {
      const req = route.request();
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204 });
      expect(req.method()).toBe('POST'); expect(req.headers()['x-upsert']).not.toBe('true');
      const path = new URL(req.url()).pathname.split('/copies-bulletins-paie/')[1];
      state.appels.push({ nom: 'upload', body: { path } });
      if (state.panneUpload) return route.fulfill({ status: 503, json: { message: 'Envoi indisponible' } });
      if (state.uploads.has(path)) return route.fulfill({ status: 409, json: { statusCode: '409', error: 'Duplicate', message: 'The resource already exists' } });
      // Le protocole WebKit omet les octets des pièces multipart dans postData.
      // Sa simulation vérifie l'intention et le transport, pas les octets envoyés
      // (vérifiés séparément avec Storage réel). Chromium expose le corps complet.
      const webkit = page.context().browser()?.browserType().name() === 'webkit';
      const intention = [...state.intentions.values()].find(r => r.storage_path === path);
      expect(intention).toBeTruthy();
      const fichier = webkit ? state.fichiers.get(intention!.body.p_sha256_attendu)
        : [...state.fichiers.values()].find(f => req.postDataBuffer()?.includes(f.buffer));
      expect(fichier).toBeTruthy(); state.uploads.set(path, fichier!.buffer);
      return route.fulfill({ json: { Key: `copies-bulletins-paie/${path}` } });
    });
    await page.route('**/functions/v1/copies-bulletins', async route => {
      if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204 });
      const body = route.request().postDataJSON(); state.appels.push({ nom: 'copies-bulletins', body });
      if (body.action === 'telecharger') {
        const copie = state.copies.find(c => c.id === body.copie_id); expect(copie).toBeTruthy();
        if (state.panneLecture || copie!.statut === 'RETIREE') return route.fulfill({ status: 403, json: { error: 'DOCUMENT_INDISPONIBLE' } });
        return route.fulfill({ contentType: 'application/pdf', body: state.lectureCorrompue ? Buffer.from('%PDF-1.7 incorrect') : state.fichiers.get(copie!.sha256)!.buffer });
      }
      expect(body.action).toBe('finaliser'); expect(body.destinataire_confirme).toBe(true);
      if (state.pannePublication) return route.fulfill({ status: 503, json: { error: 'PUBLICATION_INDISPONIBLE' } });
      const reservation = [...state.intentions.values()].find(r => r.id === body.copie_id); expect(reservation).toBeTruthy();
      if (reservation!.statut === 'RESERVEE') {
        const p = reservation!.body;
        expect(state.uploads.get(reservation!.storage_path)).toEqual(state.fichiers.get(p.p_sha256_attendu)!.buffer);
        const ancienne = state.copies.find(c => c.id === p.p_remplace_id);
        if (ancienne) ancienne.statut = 'REMPLACEE';
        copiePubliee(state.fichiers.get(p.p_sha256_attendu), { id: reservation!.id,
          periode_debut: p.p_periode_debut, periode_fin: p.p_periode_fin, mission_ids: p.p_mission_ids,
          remplace_id: p.p_remplace_id, motif_remplacement: p.p_motif_remplacement, version: reservation!.version });
        reservation!.statut = 'PUBLIEE';
      }
      if (state.perdreReponsePublication) { state.perdreReponsePublication = false; return route.fulfill({ status: 503, json: { error: 'REPONSE_PERDUE_RECETTE' } }); }
      return route.fulfill({ json: { ok: true, id: reservation!.id, statut: reservation!.statut } });
    });
  }
  return { state, installer, enregistrerPdf, copiePubliee };
}
