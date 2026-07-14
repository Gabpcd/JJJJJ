import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';
import { verifyUserOrServiceRole } from '../_shared/admin-auth.ts';
import { corsHeaders, jsonResponse, preflightResponse } from '../_shared/cors.ts';

async function fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].slice(0, 16)
    .map((octet) => octet.toString(16).padStart(2, '0')).join('');
}

const NAF_SANTE = new Set([
  '86.10Z','86.21Z','86.22A','86.22B','86.22C','86.23Z',
  '86.90A','86.90B','86.90C','86.90D','86.90E','86.90F',
  '87.10A','87.10B','87.10C','87.20A','87.20B',
  '87.30A','87.30B','87.90A','87.90B',
  '88.10A','88.10B','88.10C',
  '47.73Z',
]);

const PREFIXES_PUBLIC = ['7', '4'];

function estSecteurPublic(categorieJuridique: string | null | undefined): boolean {
  if (!categorieJuridique) return false;
  return PREFIXES_PUBLIC.some(p => categorieJuridique.startsWith(p));
}

function estNafSante(codeNaf: string | null | undefined): boolean {
  if (!codeNaf) return false;
  const normalized = codeNaf.length === 5 ? `${codeNaf.slice(0, 2)}.${codeNaf.slice(2)}` : codeNaf;
  return NAF_SANTE.has(normalized);
}

interface VerificationResult {
  statut: 'VERIFIE' | 'ALERTE' | 'INTROUVABLE';
  raison_sociale: string | null;
  est_actif: boolean;
  est_sante: boolean;
  est_public: boolean;
  code_naf: string | null;
  libelle_naf: string | null;
  categorie_juridique: string | null;
  message: string;
  // Dirigeants INSEE (match auto identité↔titulaire, Phase 3).
  dirigeants?: unknown[] | null;
}

interface SoignantIdentity {
  id: string;
  prenom: string;
  nom: string;
  date_naissance: string | null;
  siret_liberal: string | null;
  siret_liberal_verifie: boolean;
  statut_liberal: string | null;
  type_contrat: string | null;
  modifie_le: string | null;
}

interface RegistreEtablissement {
  siret?: string | null;
  activite_principale?: string | null;
  libelle_activite_principale?: string | null;
  etat_administratif?: string | null;
}

interface RegistreEntreprise extends Record<string, unknown> {
  matching_etablissements?: RegistreEtablissement[] | null;
  siege?: RegistreEtablissement | null;
  nom_raison_sociale?: string | null;
  nom_complet?: string | null;
  activite_principale?: string | null;
  libelle_activite_principale?: string | null;
  nature_juridique?: string | null;
  dirigeants?: unknown[] | null;
  complements?: { est_entrepreneur_individuel?: boolean | null } | null;
}

interface EtablissementVerificationSnapshot {
  verification_source_version: number | string;
  siret: string | null;
}

const SOIGNANT_USAGE = 'SOIGNANT_LIBERAL';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function estSiretValide(siret: string): boolean {
  if (!/^\d{14}$/.test(siret) || /^0+$/.test(siret)) return false;
  let somme = 0;
  for (let index = 0; index < siret.length; index += 1) {
    let chiffre = Number(siret[index]);
    if (index % 2 === 0) {
      chiffre *= 2;
      if (chiffre > 9) chiffre -= 9;
    }
    somme += chiffre;
  }
  return somme % 10 === 0;
}

function normaliserIdentite(value: unknown): string {
  return typeof value === 'string'
    ? value.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, ' ').trim()
    : '';
}

function contientSequence(haystack: string, needle: string): boolean {
  return !!needle && (` ${haystack} `).includes(` ${needle} `);
}

function naissanceCompatible(dateProfil: string | null, dirigeant: Record<string, unknown>): boolean | null {
  // Sans date de naissance Jolene, une simple homonymie ne doit jamais suffire
  // à activer une preuve SIRET libérale.
  if (!dateProfil) return false;
  const dateOfficielle = typeof dirigeant.date_de_naissance === 'string'
    ? dirigeant.date_de_naissance.trim()
    : '';
  if (dateOfficielle) {
    // L'API expose en général AAAA-MM, parfois une date complète.
    if (!/^\d{4}(?:-\d{2}(?:-\d{2})?)?$/.test(dateOfficielle)) return null;
    return dateProfil.slice(0, dateOfficielle.length) === dateOfficielle;
  }
  const anneeOfficielle = typeof dirigeant.annee_de_naissance === 'string'
    ? dirigeant.annee_de_naissance.trim()
    : '';
  if (!anneeOfficielle) return null;
  if (!/^\d{4}$/.test(anneeOfficielle)) return null;
  return dateProfil.slice(0, 4) === anneeOfficielle;
}

/**
 * Le SIRET libéral doit appartenir au soignant. Un rapprochement flou (préfixe
 * de prénom, simple mot commun) n'est jamais suffisant : nom exact + prénom
 * complet, et date/année de naissance obligatoirement publiée par le registre.
 * `null` signifie que le registre ne publie pas assez d'information pour une
 * activation automatique : la preuve reste en attente de revue.
 */
function identiteSoignantCoherente(
  soignant: SoignantIdentity,
  matching: RegistreEntreprise,
): boolean | null {
  const nomProfil = normaliserIdentite(soignant.nom);
  const prenomProfil = normaliserIdentite(soignant.prenom);
  if (!nomProfil || !prenomProfil) return false;

  const dirigeants = Array.isArray(matching.dirigeants) ? matching.dirigeants : [];
  const dirigeantsPhysiques = dirigeants.filter((raw) => {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return false;
    const dirigeant = raw as Record<string, unknown>;
    const type = normaliserIdentite(dirigeant.type_dirigeant);
    return (!type || type === 'personne physique')
      && typeof dirigeant.nom === 'string'
      && typeof (dirigeant.prenoms ?? dirigeant.prenom) === 'string';
  });
  let identiteSansNaissanceOfficielle = false;
  const dirigeantCorrespondant = dirigeantsPhysiques.some((raw) => {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return false;
    const dirigeant = raw as Record<string, unknown>;
    const nom = normaliserIdentite(dirigeant.nom);
    const prenoms = normaliserIdentite(dirigeant.prenoms ?? dirigeant.prenom);
    if (nom !== nomProfil || !contientSequence(prenoms, prenomProfil)) return false;
    const naissance = naissanceCompatible(soignant.date_naissance, dirigeant);
    if (naissance === null) identiteSansNaissanceOfficielle = true;
    return naissance === true;
  });
  if (dirigeantCorrespondant) return true;
  if (identiteSansNaissanceOfficielle) return null;
  // Si le registre publie des dirigeants physiques, l'absence de correspondance
  // est une incohérence ferme (notamment en cas de date de naissance différente).
  if (dirigeantsPhysiques.length > 0) return false;

  // Les entrepreneurs individuels ne publient pas toujours un tableau de
  // dirigeants. Dans ce cas, le nom complet / la raison sociale doit contenir
  // les séquences complètes du nom ET du prénom déclarés sur Jolene.
  if (matching.complements?.est_entrepreneur_individuel !== true) return false;
  const nomsOfficiels = [matching.nom_complet, matching.nom_raison_sociale]
    .map(normaliserIdentite)
    .filter(Boolean);
  const nomEiCorrespond = nomsOfficiels.some((nomOfficiel) =>
    contientSequence(nomOfficiel, nomProfil) && contientSequence(nomOfficiel, prenomProfil)
  );
  // Le nom d'un entrepreneur individuel confirme une piste, mais sans date ou
  // année officielle il ne distingue pas de façon sûre deux homonymes.
  return nomEiCorrespond ? null : false;
}

function resultatPublic(result: VerificationResult) {
  const { dirigeants: _dirigeants, ...publicResult } = result;
  return publicResult;
}

function findMatchingEtablissement(
  results: RegistreEntreprise[],
  siret: string,
): { matching: RegistreEntreprise | null; matchingEtab: RegistreEtablissement | null } {
  for (const r of results) {
    if (Array.isArray(r.matching_etablissements)) {
      for (const e of r.matching_etablissements) {
        if (e.siret === siret) return { matching: r, matchingEtab: e };
      }
    }
    if (r.siege?.siret === siret) return { matching: r, matchingEtab: r.siege };
  }
  return { matching: null, matchingEtab: null };
}

function buildResult(
  matching: RegistreEntreprise | null,
  matchingEtab: RegistreEtablissement | null,
): VerificationResult {
  if (!matching) {
    return {
      statut: 'INTROUVABLE', raison_sociale: null, est_actif: false,
      est_sante: false, est_public: false, code_naf: null,
      libelle_naf: null, categorie_juridique: null,
      message: 'SIRET introuvable dans le registre INSEE',
    };
  }

  const raisonSociale = matching.nom_raison_sociale || matching.nom_complet || null;
  const codeNaf = matchingEtab?.activite_principale || matching.activite_principale || null;
  const libelleNaf = matchingEtab?.libelle_activite_principale || matching.libelle_activite_principale || null;
  const catJuridique = matching.nature_juridique || null;
  const dirigeants = Array.isArray(matching.dirigeants) ? matching.dirigeants : null;
  const estActif = matchingEtab?.etat_administratif === 'A';
  const sante = estNafSante(codeNaf);
  const secteurPublic = estSecteurPublic(catJuridique);

  if (!estActif) {
    return {
      statut: 'INTROUVABLE', raison_sociale: raisonSociale, est_actif: false,
      est_sante: sante, est_public: secteurPublic, code_naf: codeNaf,
      libelle_naf: libelleNaf, categorie_juridique: catJuridique, dirigeants,
      message: 'Établissement fermé ou radié',
    };
  }

  if (sante) {
    return {
      statut: 'VERIFIE', raison_sociale: raisonSociale, est_actif: true,
      est_sante: true, est_public: secteurPublic, code_naf: codeNaf,
      libelle_naf: libelleNaf, categorie_juridique: catJuridique, dirigeants,
      message: `SIRET vérifié — ${raisonSociale} — Établissement de santé actif`,
    };
  }

  return {
    statut: 'ALERTE', raison_sociale: raisonSociale, est_actif: true,
    est_sante: false, est_public: secteurPublic, code_naf: codeNaf,
    libelle_naf: libelleNaf, categorie_juridique: catJuridique,
    message: `SIRET valide mais activité non-santé (${libelleNaf || codeNaf}) — Vérification manuelle requise`,
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return preflightResponse(req);
  }
  if (req.method !== 'POST') {
    return jsonResponse(req, {
      ok: false,
      code: 'METHOD_NOT_ALLOWED',
      error: 'Methode non autorisee',
    }, 405);
  }

  // Rate-limit IP : 20 vérifs SIRET/min/IP (API INSEE quota partagé).
  const clientIp = getClientIp(req);
  if (applyRateLimit('verify-siret', clientIp, { max: 20, windowMs: 60_000 })) {
    return new Response(JSON.stringify({ ok: false, code: 'RATE_LIMITED', error: 'Trop de vérifications. Réessayez dans 1 minute.' }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  try {
    // Lecture publique : la recherche SIRET interroge le registre ouvert
    // recherche-entreprises.api.gouv.fr (données publiques), exactement comme
    // verify-finess. Aucune session n'est requise — la page d'inscription appelle
    // cette fonction AVANT que le compte n'existe (avec la clé anon). On ne gate
    // donc PAS la lecture : seule l'écriture en base (plus bas) exige une
    // autorisation (service-role ou membre PROPRIETAIRE/ADMIN_GROUPE). La fonction
    // est protégée contre l'abus par le rate-limit IP (20/min) défini au-dessus.
    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || Array.isArray(body)) {
      return jsonResponse(req, {
        ok: false,
        code: 'INVALID_JSON',
        error: 'Corps JSON invalide',
      }, 400);
    }
    const siret = typeof body.siret === 'string' ? body.siret.replace(/\s/g, '') : '';
    const etablissement_id = typeof body.etablissement_id === 'string' ? body.etablissement_id : null;
    const usage = body.usage === SOIGNANT_USAGE ? SOIGNANT_USAGE : null;
    if (!estSiretValide(siret)) {
      return new Response(JSON.stringify({ ok: false, code: 'SIRET_INVALID', error: 'SIRET invalide' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    if (!serviceRoleKey || !supabaseUrl) return jsonResponse(req, { error: 'Service indisponible' }, 503);
    const authHeader = req.headers.get('Authorization') || '';
    const tokenVal = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    if (etablissement_id && !UUID_RE.test(etablissement_id)) {
      return jsonResponse(req, {
        ok: false,
        code: 'ETABLISSEMENT_ID_INVALID',
        error: 'Identifiant établissement invalide',
      }, 400);
    }

    // Snapshot pris AVANT l'appel au registre. L'autorisation d'écrire sera
    // volontairement recalculée après l'appel ; la RPC exige en plus que cette
    // version n'ait pas bougé entre les deux.
    let etablissementSnapshot: EtablissementVerificationSnapshot | null = null;
    if (usage !== SOIGNANT_USAGE && etablissement_id) {
      const { data: snapshot, error: snapshotError } = await supabaseAdmin
        .from('etablissements')
        .select('verification_source_version, siret')
        .eq('id', etablissement_id)
        .maybeSingle();
      if (snapshotError) {
        console.error('verify-siret: snapshot établissement impossible', snapshotError.code || snapshotError.message);
        return jsonResponse(req, { ok: false, code: 'SERVICE_INDISPONIBLE', error: 'Vérification temporairement indisponible' }, 503);
      }
      etablissementSnapshot = snapshot as EtablissementVerificationSnapshot | null;
    }

    let soignant: SoignantIdentity | null = null;
    if (usage === SOIGNANT_USAGE) {
      const auth = await verifyUserOrServiceRole(req);
      if (!auth.ok) return jsonResponse(req, { ok: false, code: 'NON_AUTHENTIFIE', error: auth.error }, auth.status);
      const requestedSoignantId = typeof body.soignant_id === 'string'
        ? body.soignant_id.trim()
        : '';
      const targetSoignantId = auth.isServiceRole ? requestedSoignantId : auth.userId;
      if (!targetSoignantId || !UUID_RE.test(targetSoignantId)) {
        return jsonResponse(req, {
          ok: false,
          code: auth.isServiceRole ? 'SOIGNANT_ID_REQUIS' : 'SESSION_UTILISATEUR_REQUISE',
          error: auth.isServiceRole
            ? 'Identifiant soignant exact requis pour la revalidation interne'
            : 'Session soignant requise',
        }, auth.isServiceRole ? 400 : 403);
      }
      // Un utilisateur ne peut cibler que son propre profil. Le service_role
      // doit, au contraire, fournir explicitement la cible exacte du batch.
      if (!auth.isServiceRole && requestedSoignantId && requestedSoignantId !== auth.userId) {
        return jsonResponse(req, { ok: false, code: 'NON_AUTORISE', error: 'Modification non autorisée' }, 403);
      }

      const { data: profil, error: profilError } = await supabaseAdmin
        .from('soignants')
        .select('id, prenom, nom, date_naissance, siret_liberal, siret_liberal_verifie, statut_liberal, type_contrat, modifie_le')
        .eq('id', targetSoignantId)
        .maybeSingle();
      if (profilError) {
        console.error('verify-siret: lecture profil soignant impossible', profilError.message);
        return jsonResponse(req, { ok: false, code: 'SERVICE_INDISPONIBLE', error: 'Vérification temporairement indisponible' }, 503);
      }
      if (!profil) return jsonResponse(req, { ok: false, code: 'PROFIL_INTROUVABLE', error: 'Profil soignant introuvable' }, 404);
      soignant = profil as SoignantIdentity;

      if (auth.isServiceRole && soignant.siret_liberal !== siret) {
        return jsonResponse(req, {
          ok: false,
          code: 'SIRET_PROFILE_MISMATCH',
          error: 'Le SIRET demandé ne correspond plus au profil ciblé',
        }, 409);
      }

      const revoquerPreuveSiret = async (code: string): Promise<Response | null> => {
        // Lors d'une première saisie, aucune preuve canonique n'existe encore.
        // Pour une revalidation, le numero exact est obligatoirement persiste.
        if (soignant?.siret_liberal !== siret || soignant.siret_liberal_verifie !== true) {
          return null;
        }
        const { data: revoque, error: revocationError } = await supabaseAdmin.rpc(
          'fn_revoquer_siret_liberal_soignant',
          {
            p_soignant_id: soignant.id,
            p_siret_attendu: siret,
            p_code: code,
          },
        );
        if (revocationError || revoque !== true) {
          console.error(
            'verify-siret: revocation SIRET soignant impossible',
            revocationError?.code || 'SNAPSHOT_CHANGED',
          );
          return jsonResponse(req, {
            ok: false,
            code: 'VERIFICATION_STATE_UPDATE_FAILED',
            error: 'Impossible de sécuriser l’état de vérification SIRET',
          }, 503);
        }
        soignant.siret_liberal_verifie = false;
        return null;
      };

      if (!soignant.date_naissance) {
        const revocationError = await revoquerPreuveSiret('IDENTITE_INCOMPLETE');
        if (revocationError) return revocationError;
        return jsonResponse(req, {
          ok: false,
          code: 'IDENTITE_INCOMPLETE',
          enregistre: false,
          error: 'Renseignez et vérifiez votre date de naissance avant le contrôle du SIRET',
        }, 409);
      }

      const liberalActif = soignant.statut_liberal === 'ACTIF' || soignant.type_contrat === 'LIBERAL';
      if (liberalActif && soignant.siret_liberal && soignant.siret_liberal !== siret) {
        return jsonResponse(req, {
          ok: false,
          code: 'SIRET_MODIFICATION_VERROUILLEE',
          error: 'Le SIRET d’un statut libéral actif ne peut pas être remplacé depuis ce formulaire',
        });
      }
    }

    if (tokenVal !== serviceRoleKey) {
      const { data: allowed, error: rateError } = await supabaseAdmin.rpc('fn_verifier_rate_limit', {
        p_cle: await fingerprint(clientIp === 'unknown'
          ? `unknown|${(req.headers.get('user-agent') || '').slice(0, 160)}`
          : clientIp),
        p_action: 'edge_verify_siret',
        p_max_tentatives: 60,
        p_fenetre_secondes: 600,
      });
      if (rateError) return jsonResponse(req, { error: 'Service temporairement indisponible' }, 503);
      if (allowed !== true) return jsonResponse(req, { code: 'RATE_LIMITED', error: 'Quota de verification atteint' }, 429);
    }

    let result: VerificationResult;
    let matching: RegistreEntreprise | null = null;
    let registreDisponible = true;

    try {
      const rechercheUrl = `https://recherche-entreprises.api.gouv.fr/search?q=${siret}&mtm_campaign=jolene`;
      const response = await fetch(rechercheUrl, {
        headers: { 'Accept': 'application/json' },
        signal: AbortSignal.timeout(8_000),
      });

      if (!response.ok) {
        registreDisponible = false;
        result = {
          statut: 'ALERTE', raison_sociale: null, est_actif: false,
          est_sante: false, est_public: false, code_naf: null,
          libelle_naf: null, categorie_juridique: null,
          message: 'Service de vérification temporairement indisponible — réessaie plus tard',
        };
      } else {
        const data = await response.json() as { results?: RegistreEntreprise[] };
        const found = findMatchingEtablissement(Array.isArray(data.results) ? data.results : [], siret);
        matching = found.matching;
        result = buildResult(found.matching, found.matchingEtab);
      }
    } catch (fetchErr) {
      registreDisponible = false;
      console.error('API recherche-entreprises error:', fetchErr);
      result = {
        statut: 'ALERTE', raison_sociale: null, est_actif: false,
        est_sante: false, est_public: false, code_naf: null,
        libelle_naf: null, categorie_juridique: null,
        message: 'Service de vérification temporairement indisponible — Vérification manuelle requise',
      };
    }

    if (usage === SOIGNANT_USAGE && soignant) {
      if (!registreDisponible) {
        return jsonResponse(req, {
          ok: false,
          code: 'REGISTRE_INDISPONIBLE',
          enregistre: false,
          ...resultatPublic(result),
        });
      }
      if (!matching || !result.est_actif) {
        const { data: revoque, error: revocationError } = soignant.siret_liberal === siret
          && soignant.siret_liberal_verifie === true
          ? await supabaseAdmin.rpc('fn_revoquer_siret_liberal_soignant', {
              p_soignant_id: soignant.id,
              p_siret_attendu: siret,
              p_code: matching ? 'SIRET_INACTIF' : 'SIRET_INTROUVABLE',
            })
          : { data: true, error: null };
        if (revocationError || revoque !== true) {
          return jsonResponse(req, {
            ok: false,
            code: 'VERIFICATION_STATE_UPDATE_FAILED',
            error: 'Impossible de sécuriser l’état de vérification SIRET',
          }, 503);
        }
        return jsonResponse(req, {
          ok: false,
          code: matching ? 'SIRET_INACTIF' : 'SIRET_INTROUVABLE',
          enregistre: false,
          ...resultatPublic(result),
          message: matching ? 'Ce SIRET est fermé ou radié' : result.message,
        });
      }
      if (!result.est_sante) {
        const { data: revoque, error: revocationError } = soignant.siret_liberal === siret
          && soignant.siret_liberal_verifie === true
          ? await supabaseAdmin.rpc('fn_revoquer_siret_liberal_soignant', {
              p_soignant_id: soignant.id,
              p_siret_attendu: siret,
              p_code: 'ACTIVITE_NON_SANTE',
            })
          : { data: true, error: null };
        if (revocationError || revoque !== true) {
          return jsonResponse(req, {
            ok: false,
            code: 'VERIFICATION_STATE_UPDATE_FAILED',
            error: 'Impossible de sécuriser l’état de vérification SIRET',
          }, 503);
        }
        return jsonResponse(req, {
          ok: false,
          code: 'ACTIVITE_NON_SANTE',
          enregistre: false,
          ...resultatPublic(result),
          message: 'L’activité officielle de ce SIRET ne relève pas du secteur de la santé',
        });
      }

      const coherenceIdentite = identiteSoignantCoherente(soignant, matching);
      if (coherenceIdentite === null) {
        const preuveDejaVerifiee = soignant.siret_liberal === siret
          && soignant.siret_liberal_verifie === true;
        const { data: revue, error: revueError } = await supabaseAdmin.rpc(
          'fn_ouvrir_revue_siret_liberal_soignant',
          {
            p_soignant_id: soignant.id,
            p_code: 'IDENTITE_NON_CONFIRMABLE',
            p_donnees: {
              siret_candidat: siret,
              siret_canonique_avant: soignant.siret_liberal,
              preuve_deja_verifiee: preuveDejaVerifiee,
              prenom_declare: soignant.prenom,
              nom_declare: soignant.nom,
              date_naissance_declaree: soignant.date_naissance,
              statut_liberal: soignant.statut_liberal,
              type_contrat: soignant.type_contrat,
              profil_modifie_le: soignant.modifie_le,
              raison_sociale_officielle: result.raison_sociale,
              siret_officiel_actif: result.est_actif,
              activite_officielle_sante: result.est_sante,
              code_naf_officiel: result.code_naf,
              categorie_juridique_officielle: result.categorie_juridique,
              source_officielle: 'API Recherche Entreprises / INSEE',
            },
          },
        );
        const revuePayload = revue && typeof revue === 'object'
          ? revue as Record<string, unknown>
          : {};
        if (revueError || revuePayload.success !== true) {
          return jsonResponse(req, {
            ok: false,
            code: 'REVIEW_QUEUE_FAILED',
            error: 'La revue humaine n’a pas pu être enregistrée. Réessayez.',
          }, 503);
        }
        return jsonResponse(req, {
          ok: true,
          code: 'IDENTITE_NON_CONFIRMABLE',
          enregistre: false,
          siret_candidat: siret,
          canonique_conserve: true,
          candidat_conserve_en_revue: true,
          revue_manuelle: true,
          revue_id: revuePayload.revue_id,
          ...resultatPublic(result),
          statut: 'ALERTE',
          coherence_identite: null,
          message: 'Le registre ne publie pas de date ou d’année de naissance permettant de confirmer automatiquement le titulaire. Revue manuelle requise.',
        }, 202);
      }
      if (coherenceIdentite === false) {
        const { data: revoque, error: revocationError } = soignant.siret_liberal === siret
          && soignant.siret_liberal_verifie === true
          ? await supabaseAdmin.rpc('fn_revoquer_siret_liberal_soignant', {
              p_soignant_id: soignant.id,
              p_siret_attendu: siret,
              p_code: 'IDENTITE_INCOHERENTE',
            })
          : { data: true, error: null };
        if (revocationError || revoque !== true) {
          return jsonResponse(req, {
            ok: false,
            code: 'VERIFICATION_STATE_UPDATE_FAILED',
            error: 'Impossible de sécuriser l’état de vérification SIRET',
          }, 503);
        }
        return jsonResponse(req, {
          ok: false,
          code: 'IDENTITE_INCOHERENTE',
          enregistre: false,
          ...resultatPublic(result),
          statut: 'ALERTE',
          coherence_identite: false,
          message: 'Le titulaire ou dirigeant officiel de ce SIRET ne correspond pas à ton identité Jolene',
        });
      }

      const { data: applique, error: updateError } = await supabaseAdmin.rpc(
        'fn_appliquer_verification_siret_soignant',
        {
          p_soignant_id: soignant.id,
          p_expected_prenom: soignant.prenom,
          p_expected_nom: soignant.nom,
          p_expected_date_naissance: soignant.date_naissance,
          p_expected_siret_liberal: soignant.siret_liberal,
          p_expected_statut_liberal: soignant.statut_liberal,
          p_expected_type_contrat: soignant.type_contrat,
          p_siret: siret,
          p_raison_sociale: result.raison_sociale,
        },
      );
      if (updateError) {
        console.error('verify-siret: persistance SIRET libéral impossible', updateError.code);
        const dejaUtilise = updateError.code === '23505';
        return jsonResponse(req, {
          ok: false,
          code: dejaUtilise ? 'SIRET_DEJA_UTILISE' : 'PERSISTENCE_IMPOSSIBLE',
          error: dejaUtilise ? 'Ce SIRET est déjà rattaché à un autre compte' : 'Impossible d’enregistrer le SIRET vérifié',
        }, dejaUtilise ? 200 : 503);
      }
      if (applique !== true) {
        return jsonResponse(req, {
          ok: false,
          code: 'VERIFICATION_SOURCE_CHANGED',
          enregistre: false,
          error: 'Votre identité, votre SIRET ou votre statut a changé pendant la vérification. Relancez le contrôle.',
        }, 409);
      }

      return jsonResponse(req, {
        ok: true,
        enregistre: true,
        ...resultatPublic(result),
        coherence_identite: true,
      });
    }

    // Écriture en base : UNIQUEMENT si SIRET vérifié + etablissement_id fourni
    // + appelant autorisé. Autorisé = service-role (inscription server-side, crons)
    // OU membre PROPRIETAIRE/ADMIN_GROUPE de cet établissement (UI de vérification).
    // À l'inscription publique il n'y a PAS d'etablissement_id → on ne fait que lire,
    // donc la vérification anti-usurpation côté serveur reste intacte.
    if (registreDisponible && etablissement_id) {
      let autorise = false;
      if (tokenVal && serviceRoleKey && tokenVal === serviceRoleKey) {
        autorise = true; // service-role
      } else if (tokenVal) {
        try {
          const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
            global: { headers: { Authorization: authHeader } },
          });
          const { data: { user } } = await userClient.auth.getUser();
          if (user) {
            const adminCheck = createClient(supabaseUrl, serviceRoleKey);
            const { data: membre } = await adminCheck.from('membres_etablissement')
              .select('role').eq('etablissement_id', etablissement_id).eq('user_id', user.id)
              .eq('actif', true).maybeSingle();
            autorise = (!!membre && ['PROPRIETAIRE', 'ADMIN_GROUPE'].includes((membre as Record<string, string>).role))
              || user.id === etablissement_id;
          }
        } catch { /* non autorisé → on se contente de renvoyer la lecture */ }
      }

      if (autorise) {
        if (!etablissementSnapshot) {
          return jsonResponse(req, { ok: false, code: 'VERIFICATION_SOURCE_CHANGED', error: 'Le profil établissement a changé. Relancez le contrôle.' }, 409);
        }
        const { data: applique, error: updateError } = await supabaseAdmin.rpc(
          'fn_appliquer_verification_siret_etablissement',
          {
            p_etablissement_id: etablissement_id,
            p_version_attendue: Number(etablissementSnapshot.verification_source_version),
            p_siret: siret,
            p_verifie: result.statut === 'VERIFIE',
            p_est_actif: result.est_actif,
            p_code_naf: result.code_naf,
            p_raison_sociale: result.raison_sociale,
            p_categorie_juridique: result.categorie_juridique,
            p_dirigeants: result.dirigeants ?? null,
            p_est_secteur_public: result.est_public,
          },
        );
        if (updateError) {
          console.error('verify-siret: persistance établissement impossible', updateError.code || updateError.message);
          return jsonResponse(req, { ok: false, code: 'PERSISTENCE_IMPOSSIBLE', error: 'Impossible d’enregistrer la vérification SIRET' }, 503);
        }
        if (applique !== true) {
          return jsonResponse(req, {
            ok: false,
            code: 'VERIFICATION_SOURCE_CHANGED',
            error: 'Le SIRET ou le profil a changé pendant la vérification. Relancez le contrôle.',
          }, 409);
        }
      }
    }

    return new Response(JSON.stringify({ ok: true, ...resultatPublic(result) }), {
      status: 200,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('verify-siret error:', err);
    return new Response(JSON.stringify({ ok: false, code: 'INTERNAL_ERROR', error: 'Erreur interne' }), {
      status: 500,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
