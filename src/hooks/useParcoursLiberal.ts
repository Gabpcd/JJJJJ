import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { sanitiserNomFichier, verifierFichierDocument } from '@/lib/documentUpload';

export interface ParcoursLiberal {
  id: string;
  soignant_id: string;
  demarre_le: string;
  termine_le: string | null;
  parcours_kine: 'HEURES_2240' | 'ZONE_SOUS_DOTEE' | null;
  etapes: Record<string, unknown>;
  cree_le: string;
  mis_a_jour_le: string;
}

export interface CompteurHeures {
  heures_jolene: number;
  heures_externes_validees: number;
  heures_externes_en_attente: number;
  heures_totales: number;
  eligible_free_transition: boolean;
}

export interface HeureExterne {
  id: string;
  soignant_id: string;
  etablissement_nom: string;
  etablissement_type: string | null;
  date_debut: string;
  date_fin: string;
  heures_declarees: number;
  attestation_url: string | null;
  attestation_nom_fichier: string | null;
  statut_validation: 'EN_ATTENTE' | 'VALIDE' | 'REJETE';
  commentaire_validation: string | null;
  heures_extraites_ia: number | null;
  coherence_ia: boolean | null;
  verifie_ia_le: string | null;
  cree_le: string;
}

export interface ResultatVerifHeures {
  verdict: 'EN_ATTENTE' | 'VALIDE' | 'REJETE';
  heures_extraites?: number | null;
  coherence?: boolean | null;
}

export function useParcoursLiberal() {
  const { user } = useAuth();
  const [parcours, setParcours] = useState<ParcoursLiberal | null>(null);
  const [compteurHeures, setCompteurHeures] = useState<CompteurHeures | null>(null);
  const [heuresExternes, setHeuresExternes] = useState<HeureExterne[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadParcours = useCallback(async () => {
    if (!user) return;
    setIsLoading(true);
    try {
      const { data: parcoursData, error: parcoursErr } = await supabase.rpc(
        'fn_get_or_create_parcours_liberal' as any,
      );
      if (parcoursErr) throw parcoursErr;
      setParcours(parcoursData as unknown as ParcoursLiberal);

      const { data: compteurData, error: compteurErr } = await supabase.rpc(
        'fn_compteur_heures_soignant' as any,
        { p_soignant_id: user.id },
      );
      if (compteurErr) throw compteurErr;
      const compteurRow = Array.isArray(compteurData) ? compteurData[0] : compteurData;
      setCompteurHeures((compteurRow as unknown as CompteurHeures) ?? null);

      const { data: heuresData, error: heuresErr } = await supabase
        .from('heures_externes_soignants' as any)
        .select('*')
        .eq('soignant_id', user.id)
        .order('cree_le', { ascending: false });
      if (heuresErr) throw heuresErr;
      setHeuresExternes((heuresData as unknown as HeureExterne[]) ?? []);

      setError(null);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Erreur inconnue');
    } finally {
      setIsLoading(false);
    }
  }, [user]);

  useEffect(() => {
    loadParcours();
  }, [loadParcours]);

  const majEtape = useCallback(async (cle: string, valeur: boolean) => {
    const { data, error: err } = await supabase.rpc('fn_maj_etape_parcours' as any, {
      p_etape_cle: cle,
      p_valeur: valeur,
    });
    if (err) throw err;
    setParcours(data as unknown as ParcoursLiberal);
    return data as unknown as ParcoursLiberal;
  }, []);

  const choisirParcoursKine = useCallback(
    async (p: 'HEURES_2240' | 'ZONE_SOUS_DOTEE' | null) => {
      const { data, error: err } = await supabase.rpc('fn_choisir_parcours_kine' as any, {
        p_parcours: p,
      });
      if (err) throw err;
      setParcours(data as unknown as ParcoursLiberal);
      return data as unknown as ParcoursLiberal;
    },
    [],
  );

  const ajouterHeuresExternes = useCallback(
    async (payload: {
      etablissement_nom: string;
      etablissement_type?: string;
      date_debut: string;
      date_fin: string;
      heures_declarees: number;
      attestation_file?: File;
    }) => {
      if (!user) throw new Error('Non authentifié');

      if (!payload.attestation_file) {
        throw new Error('Une attestation est obligatoire pour déclarer des heures externes.');
      }

      let attestation_url: string | null = null;
      let attestation_nom_fichier: string | null = null;

      const file = payload.attestation_file;
      const validation = await verifierFichierDocument(file, {
        allowedMimes: ['application/pdf', 'image/jpeg', 'image/png'],
      });
      if (validation.ok === false) throw new Error(validation.message);
      const safeName = sanitiserNomFichier(file.name, validation.mime);
      const filename = `${Date.now()}_${safeName}`;
      const path = `${user.id}/heures-externes/${filename}`;

      const { error: uploadErr } = await supabase.storage
        .from('jolene-documents')
        .upload(path, file, { contentType: validation.mime, upsert: false });
      if (uploadErr) throw uploadErr;

      attestation_url = path;
      attestation_nom_fichier = file.name;

      // La RPC serveur vérifie que le chemin exact existe dans le bucket privé,
      // appartient au compte courant, contient des octets, ne recouvre aucune
      // période active, puis force tous les champs de verdict à EN_ATTENTE/NULL.
      const { data, error: err } = await supabase.rpc(
        'fn_declarer_heures_externes_soignant' as any,
        {
          p_etablissement_nom: payload.etablissement_nom,
          p_etablissement_type: payload.etablissement_type ?? null,
          p_date_debut: payload.date_debut,
          p_date_fin: payload.date_fin,
          p_heures_declarees: payload.heures_declarees,
          p_attestation_url: attestation_url,
          p_attestation_nom_fichier: attestation_nom_fichier,
        },
      );

      const declaration = data as unknown as {
        success?: boolean;
        id?: string;
        error?: string;
      } | null;
      if (err || !declaration?.success || !declaration.id) {
        if (attestation_url) {
          await supabase.functions.invoke('verify-heures-externes', {
            body: { action: 'cleanup_orphan', attestation_url },
          });
        }
        throw err || new Error(declaration?.error || 'Déclaration impossible');
      }

      // Vérification IA de l'attestation (lecture du document, extraction des
      // heures, cohérence vs déclaré). Elle ne valide jamais automatiquement :
      // tout document non conclusivement invalide reste en revue manuelle.
      let verification: ResultatVerifHeures | null = null;
      if (attestation_url) {
        try {
          const { data: vData } = await supabase.functions.invoke('verify-heures-externes', {
            body: { heure_externe_id: declaration.id },
          });
          if (vData?.verdict) {
            verification = {
              verdict: vData.verdict,
              heures_extraites: vData.heures_extraites ?? null,
              coherence: vData.coherence ?? null,
            };
          }
        } catch {
          /* best-effort : la ligne reste EN_ATTENTE */
        }
      }

      await loadParcours();
      return verification;
    },
    [user, loadParcours],
  );

  const supprimerHeuresExternes = useCallback(
    async (id: string) => {
      const ligne = heuresExternes.find((heure) => heure.id === id);
      const { data, error: err } = await supabase.functions.invoke('verify-heures-externes', {
        body: {
          action: 'delete',
          heure_externe_id: id,
          // Permet à l'Edge Function de reprendre uniquement le nettoyage
          // Storage si la ligne a déjà été supprimée lors d'un premier essai.
          attestation_url: ligne?.attestation_url ?? null,
        },
      });
      if (err) throw err;
      if (!data?.success) throw new Error(data?.error || 'Suppression impossible');
      await loadParcours();
    },
    [heuresExternes, loadParcours],
  );

  return {
    parcours,
    compteurHeures,
    heuresExternes,
    isLoading,
    error,
    majEtape,
    choisirParcoursKine,
    ajouterHeuresExternes,
    supprimerHeuresExternes,
    refresh: loadParcours,
  };
}
