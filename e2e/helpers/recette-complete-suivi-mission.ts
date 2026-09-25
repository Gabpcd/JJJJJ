import { expect, type BrowserContext } from '@playwright/test';
import { creerActionsNationales } from './recette-complete-actions-nationales';
import { ids, type RoleRecette } from './recette-complete-mission';

/** Contrats API simulés uniquement. Aucun statut de paiement n’est envoyé à un fournisseur. */
export function creerSuiviSimule() {
  const base = creerActionsNationales();
  const suivi = {
    paiements: [] as { statut: string; confirme_par_soignant: boolean; conteste: boolean }[],
    bulletins: [] as { statut: string; pdf_s3_key: string | null }[],
    litige: false, financeAutorisee: true,
    erreurs: new Set<string>(),
    lectures: [] as { role: RoleRecette; table: string; select: string; missionId: string | null }[],
  };
  async function installer(context: BrowserContext, role: RoleRecette) {
    await base.installer(context, role);
    await context.route('**/rest/v1/**', async route => {
      const req = route.request(); const url = new URL(req.url()); const name = url.pathname.split('/').pop()!;
      if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return route.abort('blockedbyclient');
      if (url.pathname.includes('/rpc/')) {
        if (!['fn_mes_permissions_etab', 'fn_litige_pour_mission', 'fn_presences_detail_mission'].includes(name)) return route.fallback();
        expect(req.method()).toBe('POST');
        expect(req.headers().authorization).toBe(`Bearer simulation-mission-${role}`);
        const body = req.postDataJSON(); base.state.calls.push({ role, name, method: req.method(), body });
        if (name === 'fn_presences_detail_mission') {
          expect(body).toEqual({ p_mission_id: ids.mission });
          const p = base.state.presence;
          return route.fulfill({ json: p ? {
            pointage_effectue: true, heures_planifiees: base.state.mission.duree_heures,
            pointage_arrivee: p.pointage_arrivee_le, pointage_depart: p.pointage_depart_le,
            methode_arrivee: 'CODE_ROTATIF', methode_depart: 'CODE_ROTATIF',
            pauses: [], nb_pauses: 0, valide: p.valide_par_etablissement,
          } : { pointage_effectue: false, heures_planifiees: base.state.mission.duree_heures } });
        }
        if (name === 'fn_litige_pour_mission') {
          expect(body.p_mission_id).toBe(ids.mission);
          return route.fulfill({ json: suivi.litige ? { exists: true, litige_id: '71000000-0000-4000-8000-000000000090', statut: 'OUVERT', type: 'HEURES' } : { exists: false } });
        }
        expect(role).toBe('ADMIN_ETABLISSEMENT');
        expect(body.p_etablissement_id == null || body.p_etablissement_id === ids.etablissement).toBe(true);
        return route.fulfill({ json: { success: true, role: suivi.financeAutorisee ? 'PROPRIETAIRE' : 'POINTAGE_ONLY', etablissement_id: ids.etablissement,
          permissions: Object.fromEntries(['gerer_equipe', 'supprimer_compte', 'profil_etab', 'missions', 'candidatures', 'contrats', 'pointage', 'rh', 'lecture', 'lecture_paiement', 'paiement'].map(p => [p, ['lecture_paiement', 'paiement'].includes(p) ? suivi.financeAutorisee : true])) } });
      }
      const colonnes: Record<string, string> = {
        contrats_mission: 'id,statut,signature_soignant,signature_etablissement',
        presences: 'pointage_arrivee_le,pointage_depart_le,valide_par_etablissement',
        factures_honoraires: 'statut,type_document', bulletins_paie: 'statut,pdf_s3_key',
        paiements_soignant: 'statut,confirme_par_soignant,conteste',
      };
      if (!(name in colonnes) || url.searchParams.get('select') !== colonnes[name]) return route.fallback();
      expect(req.method()).toBe('GET');
      expect(req.headers().authorization).toBe(`Bearer simulation-mission-${role}`);
      expect(url.searchParams.get('mission_id')).toBe(`eq.${ids.mission}`);
      if (['factures_honoraires', 'bulletins_paie', 'paiements_soignant'].includes(name) && role === 'ADMIN_ETABLISSEMENT') expect(suivi.financeAutorisee).toBe(true);
      suivi.lectures.push({ role, table: name, select: colonnes[name], missionId: url.searchParams.get('mission_id') });
      if (suivi.erreurs.has(name)) return route.fulfill({ status: 503, json: { message: 'Source indisponible pour la recette' } });
      const rows: Record<string, unknown[]> = { contrats_mission: base.state.contratCree ? [base.state.contrat] : [],
        presences: base.state.presence ? [base.state.presence] : [], factures_honoraires: base.state.facture ? [base.state.facture] : [],
        bulletins_paie: suivi.bulletins, paiements_soignant: suivi.paiements };
      return route.fulfill({ json: rows[name] });
    });
  }
  return { ...base, installer, suivi };
}
