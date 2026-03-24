import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin.endsWith(".lovable.app")
  ) {
    return origin;
  }
  return "https://app.jolene.app";
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}

// Codes NAF considérés comme établissements de santé
const NAF_SANTE = new Set([
  '86.10Z', // Activités hospitalières
  '86.21Z', // Activité des médecins généralistes
  '86.22A', // Activités de radiodiagnostic et de radiothérapie
  '86.22B', // Activités chirurgicales
  '86.22C', // Autres activités des médecins spécialistes
  '86.23Z', // Pratique dentaire
  '86.90A', // Ambulances
  '86.90B', // Laboratoires d'analyses médicales
  '86.90C', // Centres de collecte et banques d'organes
  '86.90D', // Activités des infirmiers et des sages-femmes
  '86.90E', // Activités des professionnels de la rééducation, de l'appareillage et des pédicures-podologues
  '86.90F', // Activités de santé humaine non classées ailleurs
  '87.10A', // Hébergement médicalisé pour personnes âgées
  '87.10B', // Hébergement médicalisé pour enfants handicapés
  '87.10C', // Hébergement médicalisé pour adultes handicapés et autre hébergement médicalisé
  '87.20A', // Hébergement social pour handicapés mentaux et malades mentaux
  '87.20B', // Hébergement social pour toxicomanes
  '87.30A', // Hébergement social pour personnes âgées
  '87.30B', // Hébergement social pour handicapés physiques
  '87.90A', // Hébergement social pour enfants en difficultés
  '87.90B', // Hébergement social pour adultes et familles en difficultés et autre hébergement social
  '88.10A', // Aide à domicile
  '88.10B', // Accueil ou accompagnement sans hébergement d'adultes handicapés ou de personnes âgées
  '88.10C', // Aide par le travail
  '47.73Z', // Commerce de détail de produits pharmaceutiques en magasin spécialisé (Pharmacies)
]);

// Catégories juridiques secteur public (préfixes)
const PREFIXES_PUBLIC = ['7', '4']; // 7xxx = collectivités, 4xxx = établissements publics

function estSecteurPublic(categorieJuridique: string): boolean {
  if (!categorieJuridique) return false;
  return PREFIXES_PUBLIC.some(p => categorieJuridique.startsWith(p));
}

function estNafSante(codeNaf: string): boolean {
  if (!codeNaf) return false;
  // Normalise: API returns "86.10Z" or "8610Z"
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
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  try {
    const { siret } = await req.json();
    if (!siret || !/^\d{14}$/.test(siret)) {
      return new Response(JSON.stringify({ error: 'SIRET invalide' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    // Call API Entreprise (data.gouv.fr) — free, no auth required
    const apiUrl = `https://api.insee.fr/api-sirene/3.11/siret/${siret}`;
    // Fallback: use recherche-entreprises.api.gouv.fr (no auth)
    const rechercheUrl = `https://recherche-entreprises.api.gouv.fr/search?q=${siret}&mtm_campaign=jolene`;

    let result: VerificationResult;

    try {
      const response = await fetch(rechercheUrl, {
        headers: { 'Accept': 'application/json' },
      });

      if (!response.ok) {
        result = {
          statut: 'INTROUVABLE',
          raison_sociale: null,
          est_actif: false,
          est_sante: false,
          est_public: false,
          code_naf: null,
          libelle_naf: null,
          categorie_juridique: null,
          message: 'SIRET introuvable dans le registre INSEE',
        };
      } else {
        const data = await response.json();
        const results = data.results || [];

        // Find matching establishment by SIRET
        let matching: any = null;
        let matchingEtab: any = null;
        for (const r of results) {
          if (r.matching_etablissements) {
            for (const e of r.matching_etablissements) {
              if (e.siret === siret) {
                matching = r;
                matchingEtab = e;
                break;
              }
            }
          }
          if (matching) break;
          // Also check siege
          if (r.siege?.siret === siret) {
            matching = r;
            matchingEtab = r.siege;
            break;
          }
        }

        if (!matching) {
          result = {
            statut: 'INTROUVABLE',
            raison_sociale: null,
            est_actif: false,
            est_sante: false,
            est_public: false,
            code_naf: null,
            libelle_naf: null,
            categorie_juridique: null,
            message: 'SIRET introuvable dans le registre INSEE',
          };
        } else {
          const raisonSociale = matching.nom_raison_sociale || matching.nom_complet || null;
          const codeNaf = matchingEtab?.activite_principale || matching.activite_principale || null;
          const libelleNaf = matchingEtab?.libelle_activite_principale || matching.libelle_activite_principale || null;
          const catJuridique = matching.nature_juridique || null;
          const estActif = matchingEtab?.etat_administratif === 'A';
          const sante = estNafSante(codeNaf);
          const secteurPublic = estSecteurPublic(catJuridique);

          if (!estActif) {
            result = {
              statut: 'INTROUVABLE',
              raison_sociale: raisonSociale,
              est_actif: false,
              est_sante: sante,
              est_public: secteurPublic,
              code_naf: codeNaf,
              libelle_naf: libelleNaf,
              categorie_juridique: catJuridique,
              message: 'Établissement fermé ou radié',
            };
          } else if (sante) {
            result = {
              statut: 'VERIFIE',
              raison_sociale: raisonSociale,
              est_actif: true,
              est_sante: true,
              est_public: secteurPublic,
              code_naf: codeNaf,
              libelle_naf: libelleNaf,
              categorie_juridique: catJuridique,
              message: `SIRET vérifié — ${raisonSociale} — Établissement de santé actif`,
            };
          } else {
            result = {
              statut: 'ALERTE',
              raison_sociale: raisonSociale,
              est_actif: true,
              est_sante: false,
              est_public: secteurPublic,
              code_naf: codeNaf,
              libelle_naf: libelleNaf,
              categorie_juridique: catJuridique,
              message: `SIRET valide mais activité non-santé (${libelleNaf || codeNaf}) — Vérification manuelle requise`,
            };
          }
        }
      }
    } catch (fetchErr) {
      console.error('API recherche-entreprises error:', fetchErr);
      result = {
        statut: 'ALERTE',
        raison_sociale: null,
        est_actif: false,
        est_sante: false,
        est_public: false,
        code_naf: null,
        libelle_naf: null,
        categorie_juridique: null,
        message: 'Service de vérification temporairement indisponible — Vérification manuelle requise',
      };
    }

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('verify-siret error:', err);
    return new Response(JSON.stringify({ error: 'Erreur interne' }), {
      status: 500,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
