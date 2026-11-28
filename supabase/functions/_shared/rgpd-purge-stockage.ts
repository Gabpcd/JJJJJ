/**
 * Purge RGPD des fichiers Storage d'un compte soignant supprimé (migration 20261128140100, docs/CONFORMITE.md §6).
 *
 * La base possède la file (private.rgpd_purges_stockage) et décide : la réservation rend un lot de fichiers, la
 * confirmation ne tient un fichier pour effacé que s'il a disparu de storage.objects. Cette boucle ne fait que
 * l'effacement par l'API Storage, seule voie admise (aucune suppression SQL de storage.objects).
 *
 * Aucun chemin n'est journalisé ni renvoyé : il peut contenir le nom de fichier d'origine, donc le nom de la personne.
 * Le module n'importe rien : testable sous Node (tests/node/rgpd-purge-stockage.node.mjs) comme sous Deno.
 */

export type ErreurClient = { message?: string; code?: string; statusCode?: string | number } | null;

export type ClientPurge = {
  rpc: (nom: string, args?: Record<string, unknown>) => PromiseLike<{ data: unknown; error: ErreurClient }>;
  storage: {
    from: (bucket: string) => {
      remove: (chemins: string[]) => PromiseLike<{ data: unknown; error: ErreurClient }>;
    };
  };
};

export type BilanPurge = { reserves: number; confirmes: number; en_echec: number; lots: number };

export const BUCKETS_PURGEABLES = Object.freeze(['jolene-documents', 'attestations-heures-externes', 'justificatifs']);
export const TAILLE_LOT_MAX = 100;
export const LOTS_MAX = 20;

type Ligne = { id: string; bucket: string; chemin: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function ligneValide(valeur: unknown): valeur is Ligne {
  if (!valeur || typeof valeur !== 'object') return false;
  const { id, bucket, chemin } = valeur as Record<string, unknown>;
  return typeof id === 'string' && UUID.test(id)
    && typeof bucket === 'string' && BUCKETS_PURGEABLES.includes(bucket)
    && typeof chemin === 'string' && chemin.length > 0 && chemin.length <= 1024
    && !chemin.startsWith('/') && !chemin.split('/').includes('..');
}

/** Code d'erreur borné, sans message libre (il peut citer un chemin). */
function codeErreur(prefixe: string, erreur: ErreurClient): string {
  const code = String(erreur?.statusCode ?? erreur?.code ?? '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40);
  return code ? `${prefixe}:${code}` : prefixe;
}

/**
 * Traite au plus `lots` lots de `taille` fichiers. Lève si la base refuse une réservation ou une confirmation
 * (l'appelant renvoie alors une erreur : le cron réessaiera, l'alerte à 24 h reste due).
 */
export async function purgerStockageRgpd(
  client: ClientPurge,
  { taille = TAILLE_LOT_MAX, lots = LOTS_MAX }: { taille?: number; lots?: number } = {},
): Promise<BilanPurge> {
  const tailleLot = Math.min(Math.max(Math.trunc(taille) || 1, 1), TAILLE_LOT_MAX);
  const lotsMax = Math.min(Math.max(Math.trunc(lots) || 1, 1), LOTS_MAX);
  const bilan: BilanPurge = { reserves: 0, confirmes: 0, en_echec: 0, lots: 0 };

  for (let lot = 0; lot < lotsMax; lot += 1) {
    const { data, error } = await client.rpc('fn_rgpd_purges_stockage_reserver', { p_limite: tailleLot });
    if (error) throw new Error(codeErreur('RESERVATION_REFUSEE', error));
    const lignes = Array.isArray(data) ? data : [];
    if (lignes.length === 0) break;
    bilan.lots += 1;
    bilan.reserves += lignes.length;

    const parBucket = new Map<string, Ligne[]>();
    const invalides: string[] = [];
    for (const ligne of lignes) {
      if (!ligneValide(ligne)) {
        const id = (ligne as { id?: unknown })?.id;
        if (typeof id === 'string' && UUID.test(id)) invalides.push(id);
        continue;
      }
      parBucket.set(ligne.bucket, [...(parBucket.get(ligne.bucket) ?? []), ligne]);
    }

    const confirmations: Array<{ ids: string[]; erreur: string | null }> = [];
    if (invalides.length) confirmations.push({ ids: invalides, erreur: 'LIGNE_INVALIDE' });
    for (const [bucket, groupe] of parBucket) {
      const { error: erreurStockage } = await client.storage.from(bucket).remove(groupe.map(l => l.chemin));
      confirmations.push({
        ids: groupe.map(l => l.id),
        erreur: erreurStockage ? codeErreur('STORAGE_REMOVE', erreurStockage) : null,
      });
    }

    for (const { ids, erreur } of confirmations) {
      const { data: retour, error: erreurConfirmation } = await client.rpc('fn_rgpd_purges_stockage_confirmer', {
        p_ids: ids,
        p_erreur: erreur,
      });
      if (erreurConfirmation) throw new Error(codeErreur('CONFIRMATION_REFUSEE', erreurConfirmation));
      const r = (retour ?? {}) as { confirmes?: unknown; en_echec?: unknown };
      bilan.confirmes += Number.isFinite(Number(r.confirmes)) ? Number(r.confirmes) : 0;
      bilan.en_echec += Number.isFinite(Number(r.en_echec)) ? Number(r.en_echec) : 0;
    }

    if (lignes.length < tailleLot) break;
  }
  return bilan;
}
