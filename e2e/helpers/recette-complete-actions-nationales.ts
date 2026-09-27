import { expect, type BrowserContext, type Page, type Request } from '@playwright/test';
import { creerMissionSimulee, ids, type RoleRecette } from './recette-complete-mission';

const lectures = new WeakMap<Page, { enCours: Set<Request>; dernierEvenement: number }>();
export async function stabiliserActionsNationales(page: Page) {
  const suivi = lectures.get(page);
  if (suivi) await expect.poll(() => suivi.enCours.size === 0 && Date.now() - suivi.dernierEvenement >= 500,
    { message: 'Lectures API achevées avant remplacement du document' }).toBe(true);
}

/** Les autorisations, OTP et scans ci-dessous sont des contrats API simulés, jamais une preuve SQL/RLS. */
export function creerActionsNationales() {
  const base = creerMissionSimulee();
  const { state } = base;
  const refus = new Map<string, { status: number; body: unknown }>();
  const attentes = new Map<string, Promise<void>>();
  const appelsRetenus: string[] = [];
  const control = {
    horsLigne: false, codePointage: '654321', heurePointage: '2026-09-24T18:00:00.000Z',
    refuser(nom: string, body: unknown, status = 200) { refus.set(nom, { body, status }); },
    retenir(nom: string) {
      let liberer!: () => void;
      attentes.set(nom, new Promise<void>(resolve => { liberer = resolve; }));
      return () => { attentes.delete(nom); liberer(); };
    },
    appelsRetenus,
  };
  async function installer(context: BrowserContext, role: RoleRecette) {
    const suivre = (page: Page) => {
      const suivi = { enCours: new Set<Request>(), dernierEvenement: Date.now() };
      lectures.set(page, suivi);
      page.on('request', req => {
        if (/\/(auth|rest|functions|storage)\/v1\//.test(req.url())) {
          suivi.enCours.add(req); suivi.dernierEvenement = Date.now();
        }
      });
      const terminer = (req: Request) => { if (suivi.enCours.delete(req)) suivi.dernierEvenement = Date.now(); };
      page.on('requestfinished', terminer); page.on('requestfailed', terminer);
    };
    context.pages().forEach(suivre); context.on('page', suivre);
    await base.installer(context, role);
    await context.route('**/rest/v1/rpc/*', async route => {
      const req = route.request(); const url = new URL(req.url()); const name = url.pathname.split('/').pop()!;
      if (!['localhost', '127.0.0.1'].includes(url.hostname)) return route.abort('blockedbyclient');
      if (req.method() !== 'POST') { state.unknown.push(`${req.method()} ${name}`); return route.fulfill({ status: 501, json: { message: 'Méthode hors contrat de recette' } }); }
      const body = req.postDataJSON();
      const actes: Record<string, RoleRecette[]> = {
        fn_confirmer_action_planning_v1: ['SOIGNANT'], fn_traiter_candidature_planning_v1: ['ADMIN_ETABLISSEMENT'],
        fn_scanner_code_pointage: ['SOIGNANT'], fn_envoyer_otp_signature: ['SOIGNANT', 'ADMIN_ETABLISSEMENT'],
        fn_signer_contrat_otp: ['SOIGNANT', 'ADMIN_ETABLISSEMENT'],
      };
      if (actes[name]) {
        expect(actes[name]).toContain(role);
        expect(req.headers().authorization).toBe(`Bearer simulation-mission-${role}`);
        if (name.includes('signature') || name === 'fn_signer_contrat_otp') expect(body.p_contrat_id).toBe(ids.contrat);
        if (name === 'fn_confirmer_action_planning_v1') expect(body).toMatchObject({ p_mission_id: ids.mission, p_action: 'POSTULER', p_creneaux_confirmes: [{ debut: state.mission.debut_le, fin: state.mission.fin_le }] });
      }
      if (name === 'fn_score_etab_public' || name === 'fn_user_id_pour_etablissement') {
        expect(body).toEqual(name === 'fn_score_etab_public' ? { p_etab_id: ids.etablissement } : { p_etablissement_id: ids.etablissement });
        state.calls.push({ role, name, method: req.method(), body });
        return route.fulfill({ json: name === 'fn_score_etab_public' ? null : ids.etablissement });
      }
      if (control.horsLigne) {
        state.calls.push({ role, name, method: req.method(), body });
        return route.abort('internetdisconnected');
      }
      const attente = attentes.get(name);
      if (attente) { appelsRetenus.push(name); await attente; }
      const erreur = refus.get(name);
      if (erreur) {
        refus.delete(name); state.calls.push({ role, name, method: req.method(), body });
        return route.fulfill({ status: erreur.status, json: erreur.body });
      }
      if (name !== 'fn_scanner_code_pointage') return route.fallback();
      state.calls.push({ role, name, method: req.method(), body });
      expect(body.p_metadata).toMatchObject({ id_terminal: expect.any(String) });
      expect(body.p_metadata).not.toHaveProperty('latitude');
      expect(body.p_metadata).not.toHaveProperty('longitude');
      if (body.p_code !== control.codePointage) return route.fulfill({ status: 400, json: { code: 'P0002', message: 'Code de pointage invalide ou expiré.' } });
      if (state.mission.soignant_assigne_id !== ids.soignant) return route.fulfill({ status: 403, json: { code: '42501', message: 'Vous n’êtes pas assigné(e) à cette mission.' } });
      if (state.contrat.statut !== 'SIGNE_COMPLET') return route.fulfill({ status: 400, json: { code: '23514', message: 'Le contrat doit être signé avant le pointage.' } });
      const ouvert = state.segments.find(s => !s.fin);
      if (ouvert) ouvert.fin = control.heurePointage;
      else {
        const segment = { id: `segment-national-${state.segments.length}`, mission_id: ids.mission, debut: control.heurePointage, fin: null, type_creneau: 'EFFECTIF', est_pause: false };
        state.segments.push(segment); state.creneaux.push(segment);
      }
      state.mission.statut = 'EN_COURS';
      state.presence = { id: ids.presence, mission_id: ids.mission, soignant_id: ids.soignant,
        pointage_arrivee_le: state.segments[0].debut, pointage_depart_le: ouvert ? control.heurePointage : null,
        valide_par_etablissement: false, cree_le: control.heurePointage,
        methode_pointage_arrivee: 'CODE_ROTATIF', methode_pointage_depart: ouvert ? 'CODE_ROTATIF' : null,
        missions: { ...state.mission, presences: undefined } };
      state.mission.presences = [{ ...state.presence, missions: undefined }];
      control.codePointage = String(Number(control.codePointage) + 1);
      return route.fulfill({ json: { type_scan_effectue: ouvert ? 'FERMETURE' : 'OUVERTURE',
        prochain_type_scan: ouvert ? 'OUVERTURE' : 'FERMETURE', nouveau_code: control.codePointage,
        numero_scan: state.calls.filter(c => c.name === name).length, horodatage_effectif: control.heurePointage } });
    });
  }
  return { ...base, installer, control };
}
