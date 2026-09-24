import { useCallback, useEffect, useRef, useState } from 'react';
import { publicSupabase } from '@/integrations/supabase/public-client';
import type { Database } from '@/integrations/supabase/types';
import { handleErrorSilent } from '@/lib/handleError';

type MissionPublique = Database['public']['Functions']['fn_missions_publiques_recherche']['Returns'][number];
export const DELAI_RECHERCHE_PUBLIQUE_MS = 15_000;

function lireMissions(data: unknown): MissionPublique[] {
  const valeur = data && typeof data === 'object' && !Array.isArray(data)
    ? (data as { missions?: unknown; data?: unknown }).missions ?? (data as { data?: unknown }).data
    : data;
  if (!Array.isArray(valeur) || valeur.some(row => !row || typeof row !== 'object' || typeof row.id !== 'string' || !row.id)) {
    throw new Error('Réponse de recherche invalide');
  }
  return valeur;
}

/** Une panne, une annulation et une réponse vide sont trois états distincts. */
export function useMissionsPubliques(profession = '', ville = '') {
  const [missions, setMissions] = useState<MissionPublique[] | null>(null);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);
  const requeteCourante = useRef(0);
  const controleur = useRef<AbortController | null>(null);

  const rechercher = useCallback(async (prochaineProfession = '', prochaineVille = '') => {
    const numero = ++requeteCourante.current;
    controleur.current?.abort();
    const controller = new AbortController();
    controleur.current = controller;
    setLoading(true);
    setErreur(null);
    let delai: ReturnType<typeof setTimeout> | undefined;
    try {
      // Le catalogue est public : aucun verrou de renouvellement de session
      // ni aller-retour d'authentification ne doit retarder cette lecture.
      const requete = publicSupabase.rpc('fn_missions_publiques_recherche', {
        p_profession: prochaineProfession.trim() || undefined,
        p_ville: prochaineVille.trim() || undefined,
      }).abortSignal(controller.signal);
      const { data, error } = await Promise.race([
        requete,
        new Promise<never>((_resolve, reject) => {
          delai = setTimeout(() => {
            controller.abort();
            reject(new Error('Délai de recherche dépassé'));
          }, DELAI_RECHERCHE_PUBLIQUE_MS);
        }),
      ]);
      if (numero !== requeteCourante.current) return;
      if (error) throw error;
      const rows = lireMissions(data);
      setMissions(rows);
      setTotal(rows[0]?.total_count ?? rows.length);
    } catch (error) {
      if (numero !== requeteCourante.current) return;
      handleErrorSilent(error, 'MissionsPubliques.recherche');
      setErreur('La recherche de missions est temporairement indisponible. Réessayez dans un instant.');
    } finally {
      clearTimeout(delai);
      if (numero === requeteCourante.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    void rechercher(profession, ville);
    return () => {
      requeteCourante.current++;
      controleur.current?.abort();
    };
  }, [profession, ville, rechercher]);

  return { missions, total, loading, erreur, rechercher };
}
