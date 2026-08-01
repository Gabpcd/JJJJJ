import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { corsHeaders, jsonResponse, preflightResponse } from '../_shared/cors.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';

const API_KEY_RE = /^sd_(?:live|test)_[a-zA-Z0-9]{24,80}$/;
const API_SECRET_RE = /^[a-fA-F0-9]{64}$/;
const PROFESSIONS = new Set([
  'IDE', 'AS', 'AES', 'IBODE', 'IADE', 'SAGE_FEMME', 'KINE', 'MEDECIN',
  'PHARMACIEN', 'MANIPULATEUR_RADIO', 'PREPARATEUR_PHARMA', 'DIETETICIEN',
  'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE', 'DENTISTE',
  'AUXILIAIRE_PUERICULTURE',
]);
const STATUTS = new Set(['BROUILLON', 'OUVERTE', 'ASSIGNEE', 'EN_COURS', 'TERMINEE', 'ANNULEE', 'LITIGE', 'EXPIREE']);
const TYPES_CONTRAT = new Set(['TOUS', 'SALARIE', 'LIBERAL']);
const MODES_REMUNERATION = new Set(['TAUX_HORAIRE', 'RETROCESSION']);
const TAILLE_PAGE_CRENEAUX = 1000;
const ISO_AVEC_FUSEAU_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?(Z|([+-])(\d{2}):(\d{2}))$/;

interface CreneauApi {
  debut: string;
  fin: string;
}

interface CreneauRelation extends CreneauApi {
  id: string;
  mission_id: string;
  ordre: number;
}

function estAnneeBissextile(annee: number): boolean {
  return annee % 4 === 0 && (annee % 100 !== 0 || annee % 400 === 0);
}

function instantIsoStrict(valeur: string): number | null {
  const correspondance = ISO_AVEC_FUSEAU_RE.exec(valeur);
  if (!correspondance) return null;

  const annee = Number(correspondance[1]);
  const mois = Number(correspondance[2]);
  const jour = Number(correspondance[3]);
  const heure = Number(correspondance[4]);
  const minute = Number(correspondance[5]);
  const seconde = correspondance[6] == null ? 0 : Number(correspondance[6]);
  const heureDecalage = correspondance[10] == null ? 0 : Number(correspondance[10]);
  const minuteDecalage = correspondance[11] == null ? 0 : Number(correspondance[11]);
  const joursParMois = [
    31,
    estAnneeBissextile(annee) ? 29 : 28,
    31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
  ];

  if (annee < 1 || mois < 1 || mois > 12) return null;
  if (jour < 1 || jour > joursParMois[mois - 1]) return null;
  if (heure > 23 || minute > 59 || seconde > 59) return null;
  // ISO 8601 borne les décalages à ±14:00.
  if (heureDecalage > 14 || minuteDecalage > 59) return null;
  if (heureDecalage === 14 && minuteDecalage !== 0) return null;

  const instant = Date.parse(valeur);
  return Number.isFinite(instant) ? instant : null;
}

function constantTimeEqual(a: string, b: string): boolean {
  const aa = new TextEncoder().encode(a.toLowerCase());
  const bb = new TextEncoder().encode(b.toLowerCase());
  const max = Math.max(aa.length, bb.length);
  let diff = aa.length ^ bb.length;
  for (let i = 0; i < max; i++) diff |= (aa[i] || 0) ^ (bb[i] || 0);
  return diff === 0;
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function hasPermission(permissions: unknown, expected: string): boolean {
  return Array.isArray(permissions) && permissions.includes(expected);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflightResponse(req);

  try {
    if (!['GET', 'POST'].includes(req.method)) {
      return jsonResponse(req, { error: 'Methode non autorisee' }, 405);
    }

    const apiKey = (req.headers.get('x-api-key') || '').trim();
    const apiSecret = (req.headers.get('x-api-secret') || '').trim();
    if (!API_KEY_RE.test(apiKey) || !API_SECRET_RE.test(apiSecret)) {
      // Meme cout de hash pour limiter les differences de timing entre header
      // absent, cle inconnue et secret incorrect.
      await sha256Hex(apiSecret || '0'.repeat(64));
      return jsonResponse(req, { error: 'Identifiants API invalides' }, 401);
    }

    const ip = getClientIp(req);
    const keyFingerprint = (await sha256Hex(apiKey)).slice(0, 20);
    if (applyRateLimit('api-v1', `${keyFingerprint}:${ip}`, { max: 120, windowMs: 60_000 })) {
      return jsonResponse(req, { error: 'Limite de requetes atteinte' }, 429);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse(req, { error: 'Service indisponible' }, 503);
    }
    const supabase = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const { data: key, error: keyError } = await supabase
      .from('api_keys')
      .select('id, etablissement_id, groupe_sante_id, cle_secret_hash, permissions, expire_le, actif')
      .eq('cle_api', apiKey)
      .eq('actif', true)
      .maybeSingle();

    const candidateHash = await sha256Hex(apiSecret);
    let secretValide = false;
    if (key?.cle_secret_hash && /^[a-f0-9]{64}$/i.test(key.cle_secret_hash)) {
      secretValide = constantTimeEqual(candidateHash, key.cle_secret_hash);
    } else if (key?.cle_secret_hash?.startsWith('$2')) {
      // Compatibilite temporaire des quelques hashes bcrypt historiques. La
      // RPC est service_role-only et ne retourne jamais le hash ni le secret.
      const { data: legacy } = await supabase.rpc('fn_verifier_api_key', {
        p_cle_api: apiKey,
        p_cle_secret: apiSecret,
      });
      secretValide = (legacy as Record<string, unknown> | null)?.valid === true;
    }

    if (keyError || !key || !secretValide) {
      return jsonResponse(req, { error: 'Identifiants API invalides' }, 401);
    }
    if (key.expire_le && new Date(key.expire_le).getTime() <= Date.now()) {
      return jsonResponse(req, { error: 'Cle API expiree' }, 403);
    }
    const etabId = key.etablissement_id;
    if (!etabId) {
      return jsonResponse(req, { error: 'Cle API non rattachee a un etablissement' }, 403);
    }

    const { data: rateAllowed, error: rateError } = await supabase.rpc('fn_verifier_rate_limit', {
      p_cle: key.id,
      p_action: 'api_v1_authenticated',
      p_max_tentatives: 2000,
      p_fenetre_secondes: 3600,
    });
    if (rateError || rateAllowed !== true) {
      return jsonResponse(req, { error: 'Quota horaire atteint' }, 429);
    }
    await supabase.from('api_keys').update({ derniere_utilisation: new Date().toISOString() }).eq('id', key.id);

    const url = new URL(req.url);
    const path = url.pathname.replace(/.*\/api-v1/, '') || '/';
    const limitRaw = Number(url.searchParams.get('limit') || '100');
    const limit = Number.isInteger(limitRaw) ? Math.max(1, Math.min(limitRaw, 100)) : 100;

    if (req.method === 'GET' && path === '/missions') {
      if (!hasPermission(key.permissions, 'missions:read')) {
        return jsonResponse(req, { error: 'Permission missions:read requise' }, 403);
      }
      const statut = url.searchParams.get('statut');
      if (statut && !STATUTS.has(statut)) return jsonResponse(req, { error: 'Statut invalide' }, 400);
      let query = supabase
        .from('missions')
        .select('id, intitule, profession_requise, service, debut_le, fin_le, nb_creneaux, taux_horaire_base, statut, soignant_assigne_id')
        .eq('etablissement_id', etabId);
      if (statut) query = query.eq('statut', statut);
      const { data, error } = await query.order('debut_le', { ascending: false }).limit(limit);
      if (error) {
        console.error('[api-v1] GET missions', error.message);
        return jsonResponse(req, { error: 'Erreur requete' }, 500);
      }
      const missionsBrutes = (data || []) as Array<Record<string, unknown>>;
      const missionIds = missionsBrutes
        .map((mission) => mission.id)
        .filter((id): id is string => typeof id === 'string');
      if (missionIds.length !== missionsBrutes.length) {
        console.error('[api-v1] GET missions: identifiant mission invalide');
        return jsonResponse(req, { error: 'Planning exact temporairement indisponible' }, 503);
      }

      const creneaux: CreneauRelation[] = [];
      const idsCreneauxVus = new Set<string>();
      let totalCreneauxAttendu: number | null = null;
      let offsetCreneaux = 0;

      if (missionIds.length > 0) {
        do {
          const {
            data: pageCreneaux,
            error: erreurCreneaux,
            count,
          } = await supabase
            .from('mission_creneaux')
            .select('id, mission_id, debut, fin, ordre', { count: 'exact' })
            .in('mission_id', missionIds)
            .eq('type_creneau', 'PREVISIONNEL')
            .eq('est_pause', false)
            .not('fin', 'is', null)
            .order('mission_id', { ascending: true })
            .order('ordre', { ascending: true })
            .order('debut', { ascending: true })
            .order('id', { ascending: true })
            .range(offsetCreneaux, offsetCreneaux + TAILLE_PAGE_CRENEAUX - 1);

          if (erreurCreneaux || count == null) {
            console.error('[api-v1] GET mission_creneaux', erreurCreneaux?.message || 'count absent');
            return jsonResponse(req, { error: 'Planning exact temporairement indisponible' }, 503);
          }
          if (totalCreneauxAttendu == null) totalCreneauxAttendu = count;
          if (count !== totalCreneauxAttendu) {
            console.error('[api-v1] GET mission_creneaux: total modifie pendant la pagination');
            return jsonResponse(req, { error: 'Planning exact modifie pendant la requete' }, 409);
          }

          const page = (pageCreneaux || []) as CreneauRelation[];
          if (page.length === 0 && offsetCreneaux < totalCreneauxAttendu) {
            console.error('[api-v1] GET mission_creneaux: page tronquee');
            return jsonResponse(req, { error: 'Planning exact temporairement indisponible' }, 503);
          }
          for (const creneau of page) {
            if (!creneau.id || idsCreneauxVus.has(creneau.id)) {
              console.error('[api-v1] GET mission_creneaux: doublon de pagination');
              return jsonResponse(req, { error: 'Planning exact modifie pendant la requete' }, 409);
            }
            idsCreneauxVus.add(creneau.id);
            creneaux.push(creneau);
          }
          offsetCreneaux += page.length;
          if (offsetCreneaux > totalCreneauxAttendu) {
            console.error('[api-v1] GET mission_creneaux: total depasse');
            return jsonResponse(req, { error: 'Planning exact temporairement indisponible' }, 503);
          }
        } while (offsetCreneaux < (totalCreneauxAttendu ?? 0));

        const { count: countFinal, error: erreurCountFinal } = await supabase
          .from('mission_creneaux')
          .select('id', { count: 'exact', head: true })
          .in('mission_id', missionIds)
          .eq('type_creneau', 'PREVISIONNEL')
          .eq('est_pause', false)
          .not('fin', 'is', null);
        if (erreurCountFinal || countFinal !== totalCreneauxAttendu) {
          console.error('[api-v1] GET mission_creneaux: total final modifie');
          return jsonResponse(req, { error: 'Planning exact modifie pendant la requete' }, 409);
        }
      }

      const planningParMission = new Map<string, CreneauApi[]>();
      for (const creneau of creneaux) {
        const planning = planningParMission.get(creneau.mission_id) || [];
        planning.push({ debut: creneau.debut, fin: creneau.fin });
        planningParMission.set(creneau.mission_id, planning);
      }

      const missions: Array<Record<string, unknown> & { creneaux: CreneauApi[] }> = [];
      for (const mission of missionsBrutes) {
        const missionId = mission.id as string;
        const planning = planningParMission.get(missionId) || [];
        const nbCreneauxDeclare = Number(mission.nb_creneaux ?? 0);
        if (!Number.isInteger(nbCreneauxDeclare)
          || nbCreneauxDeclare < 0
          || planning.length !== nbCreneauxDeclare
          || (mission.statut !== 'BROUILLON' && planning.length === 0)) {
          console.error('[api-v1] GET missions: planning incomplet ou modifie');
          return jsonResponse(req, { error: 'Planning exact temporairement indisponible' }, 503);
        }
        missions.push({ ...mission, creneaux: planning });
      }
      return jsonResponse(req, { missions, count: missions.length });
    }

    if (req.method === 'POST' && path === '/missions') {
      if (!hasPermission(key.permissions, 'missions:write')) {
        return jsonResponse(req, { error: 'Permission missions:write requise' }, 403);
      }
      const body = await req.json().catch(() => null) as Record<string, unknown> | null;
      if (!body || Array.isArray(body)) return jsonResponse(req, { error: 'Corps JSON invalide' }, 400);

      const intitule = typeof body.intitule === 'string' ? body.intitule.trim() : '';
      const profession = typeof body.profession_requise === 'string' ? body.profession_requise.trim().toUpperCase() : '';
      const service = typeof body.service === 'string' ? body.service.trim() : null;
      const taux = typeof body.taux_horaire_base === 'number' ? body.taux_horaire_base : Number(body.taux_horaire_base);
      const creneauxExplicites = Array.isArray(body.creneaux) ? body.creneaux : null;
      const debutLegacy = typeof body.debut_le === 'string' ? body.debut_le.trim() : '';
      const finLegacy = typeof body.fin_le === 'string' ? body.fin_le.trim() : '';
      const creneauxBruts = creneauxExplicites && creneauxExplicites.length > 0
        ? creneauxExplicites
        : debutLegacy && finLegacy
        ? [{ debut: debutLegacy, fin: finLegacy }]
        : null;
      const typeContrat = typeof body.type_contrat_recherche === 'string'
        ? body.type_contrat_recherche.trim().toUpperCase()
        : 'TOUS';
      const modeRemuneration = typeof body.mode_remuneration === 'string'
        ? body.mode_remuneration.trim().toUpperCase()
        : 'TAUX_HORAIRE';
      const retrocessionPct = body.retrocession_pct == null
        ? null
        : Number(body.retrocession_pct);

      if (intitule.length < 3 || intitule.length > 160) return jsonResponse(req, { error: 'intitule invalide' }, 400);
      if (!PROFESSIONS.has(profession)) return jsonResponse(req, { error: 'profession_requise invalide' }, 400);
      if (service && service.length > 120) return jsonResponse(req, { error: 'service trop long' }, 400);
      if (!creneauxBruts || creneauxBruts.length === 0) {
        return jsonResponse(req, {
          error: 'Planning requis: fournissez creneaux ou le couple legacy debut_le/fin_le',
        }, 400);
      }
      if (!Number.isFinite(taux) || taux <= 0 || taux > 1000) {
        return jsonResponse(req, { error: 'taux_horaire_base invalide' }, 400);
      }
      if (!TYPES_CONTRAT.has(typeContrat)) {
        return jsonResponse(req, { error: 'type_contrat_recherche invalide' }, 400);
      }
      if (!MODES_REMUNERATION.has(modeRemuneration)) {
        return jsonResponse(req, { error: 'mode_remuneration invalide' }, 400);
      }
      if (modeRemuneration === 'RETROCESSION') {
        if (typeContrat !== 'LIBERAL') {
          return jsonResponse(req, { error: 'La retrocession exige type_contrat_recherche=LIBERAL' }, 400);
        }
        if (retrocessionPct == null || !Number.isFinite(retrocessionPct) || retrocessionPct <= 0 || retrocessionPct > 100) {
          return jsonResponse(req, { error: 'retrocession_pct invalide (1-100)' }, 400);
        }
      }

      const creneaux: CreneauApi[] = [];
      for (const element of creneauxBruts) {
        if (!element || typeof element !== 'object' || Array.isArray(element)) {
          return jsonResponse(req, { error: 'Chaque creneau doit etre un objet { debut, fin }' }, 400);
        }
        const debut = typeof element.debut === 'string' ? element.debut.trim() : '';
        const fin = typeof element.fin === 'string' ? element.fin.trim() : '';
        if (!ISO_AVEC_FUSEAU_RE.test(debut) || !ISO_AVEC_FUSEAU_RE.test(fin)) {
          return jsonResponse(req, {
            error: 'Chaque debut et fin doit etre une date ISO 8601 avec fuseau (Z ou +HH:MM)',
          }, 400);
        }
        const debutInstant = instantIsoStrict(debut);
        const finInstant = instantIsoStrict(fin);
        if (debutInstant == null || finInstant == null || finInstant <= debutInstant) {
          return jsonResponse(req, { error: 'Dates de creneau invalides' }, 400);
        }
        // Conserver la chaîne validée permet au validateur SQL de contrôler le
        // fuseau original et évite la normalisation silencieuse des dates.
        creneaux.push({ debut, fin });
      }

      // Une seule RPC transactionnelle derive l'enveloppe et synchronise les
      // lignes mission_creneaux. L'API ne possede plus de chemin INSERT direct
      // susceptible de creer une mission sans planning exact.
      const { data, error } = await supabase.rpc('fn_creer_mission_api_v1', {
        p_etablissement_id: etabId,
        p_intitule: intitule,
        p_profession_requise: profession,
        p_service: service || null,
        p_taux_horaire_base: taux,
        p_creneaux: creneaux,
        p_type_contrat_recherche: typeContrat,
        p_mode_remuneration: modeRemuneration,
        p_retrocession_pct: modeRemuneration === 'RETROCESSION' ? retrocessionPct : null,
      });
      if (error) {
        console.error('[api-v1] POST missions', error.message);
        return jsonResponse(req, { error: 'Creation indisponible' }, 500);
      }
      const resultat = data as Record<string, unknown> | null;
      if (!resultat || resultat.success !== true || typeof resultat.mission_id !== 'string') {
        const code = typeof resultat?.code === 'string'
          && /^[A-Z0-9_]{3,80}$/.test(resultat.code)
          ? resultat.code
          : 'CREATION_MISSION_REFUSEE';
        console.warn(`[api-v1] POST missions refuse code=${code}`);
        return jsonResponse(req, {
          error: 'Creation refusee par les regles metier',
          code,
        }, 422);
      }
      return jsonResponse(req, {
        mission: {
          id: resultat.mission_id,
          intitule,
          statut: 'OUVERTE',
          nb_creneaux: resultat.nb_creneaux,
        },
      }, 201);
    }

    if (req.method === 'GET' && path === '/presences') {
      if (!hasPermission(key.permissions, 'presences:read')) {
        return jsonResponse(req, { error: 'Permission presences:read requise' }, 403);
      }
      const { data: missionIds, error: missionsError } = await supabase
        .from('missions').select('id').eq('etablissement_id', etabId).limit(1000);
      if (missionsError) return jsonResponse(req, { error: 'Erreur requete' }, 500);
      const ids = (missionIds || []).map((mission) => mission.id);
      if (ids.length === 0) return jsonResponse(req, { presences: [], count: 0 });
      const { data, error } = await supabase
        .from('presences')
        .select('id, mission_id, soignant_id, pointage_arrivee_le, pointage_depart_le, valide_par_etablissement, methode_pointage_arrivee')
        .in('mission_id', ids)
        .order('pointage_arrivee_le', { ascending: false })
        .limit(limit);
      if (error) return jsonResponse(req, { error: 'Erreur requete' }, 500);
      return jsonResponse(req, { presences: data || [], count: data?.length || 0 });
    }

    if (req.method === 'GET' && path === '/factures') {
      if (!hasPermission(key.permissions, 'factures:read')) {
        return jsonResponse(req, { error: 'Permission factures:read requise' }, 403);
      }
      const { data, error } = await supabase
        .from('factures')
        .select('id, numero_facture, statut, montant_ht, montant_tva, montant_ttc, cree_le')
        .eq('etablissement_id', etabId)
        .order('cree_le', { ascending: false })
        .limit(Math.min(limit, 50));
      if (error) return jsonResponse(req, { error: 'Erreur requete' }, 500);
      return jsonResponse(req, { factures: data || [], count: data?.length || 0 });
    }

    return jsonResponse(req, {
      error: 'Endpoint non trouve',
      endpoints: ['GET /missions', 'POST /missions', 'GET /presences', 'GET /factures'],
      documentation: 'https://jolene.app/aide/api',
    }, 404);
  } catch (error) {
    console.error('[api-v1] erreur', error);
    return new Response(JSON.stringify({ error: 'Erreur interne' }), {
      status: 500,
      headers: corsHeaders(req),
    });
  }
});
