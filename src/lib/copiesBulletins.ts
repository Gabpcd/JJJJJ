import { FunctionsHttpError } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';
import { isNative } from '@/lib/platform';
import { verifierFichierDocument } from '@/lib/documentUpload';
import { debutJourParis, ajouterJoursCivilsParis } from '@/lib/date-heure-paris';
import { avecDelai } from '@/lib/avecDelai';

export type StatutCopieBulletin = 'PUBLIEE' | 'REMPLACEE' | 'RETIREE';
export type MotifSignalementCopie = 'DESTINATAIRE' | 'CONTENU' | 'AUTRE';
export type MotifRemplacementCopie = 'CONTENU' | 'AUTRE';
export interface CopieBulletin {
  id: string;
  etablissement_id: string;
  etablissement_nom: string;
  soignant_id: string;
  soignant_nom: string;
  soignant_prenom: string;
  periode_debut: string;
  periode_fin: string;
  statut: StatutCopieBulletin;
  publie_le: string;
  remplace_id: string | null;
  version: number;
  motif_remplacement: MotifRemplacementCopie | null;
  mission_ids: string[];
  taille_octets: number;
  sha256: string;
  signalee: boolean;
}
export interface MissionCopieBulletin {
  id: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  soignant_id: string;
  soignant_nom: string;
  soignant_prenom: string;
}
export interface DepotCopieBulletin {
  etablissementId: string;
  soignantId: string;
  periodeDebut: string;
  periodeFin: string;
  missionIds: string[];
  remplaceId: string | null;
  motifRemplacement: MotifRemplacementCopie | null;
}
interface ReservationCopie {
  id: string;
  statut: 'RESERVEE' | StatutCopieBulletin;
  bucket: string;
  storage_path: string;
  version: number;
}
export class CopieRetireeErreur extends Error {
  constructor() {
    super('Cette copie a été retirée. Préparez un nouveau dépôt, puis vérifiez à nouveau le destinataire avant de confirmer.');
    this.name = 'CopieRetireeErreur';
  }
}

export function copieBulletinTelechargeable(copie: Pick<CopieBulletin, 'statut'>): boolean {
  return copie.statut === 'PUBLIEE' || copie.statut === 'REMPLACEE';
}

export function validerListeCopiesBulletins(data: unknown): CopieBulletin[] {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const jour = (v: unknown) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)
    && !Number.isNaN(Date.parse(v)) && new Date(`${v}T12:00:00Z`).toISOString().slice(0, 10) === v;
  if (!Array.isArray(data) || !data.every((c: unknown) => {
    if (!c || typeof c !== 'object') return false;
    const row = c as Record<string, unknown>;
    return ['id', 'etablissement_id', 'soignant_id'].every(k => typeof row[k] === 'string' && uuid.test(row[k]))
      && ['etablissement_nom', 'soignant_nom', 'soignant_prenom'].every(k => typeof row[k] === 'string')
      && jour(row.periode_debut) && jour(row.periode_fin) && String(row.periode_debut) <= String(row.periode_fin)
      && typeof row.publie_le === 'string' && !Number.isNaN(Date.parse(row.publie_le))
      && ['PUBLIEE', 'REMPLACEE', 'RETIREE'].includes(String(row.statut))
      && Number.isSafeInteger(row.version) && Number(row.version) > 0
      && Number.isSafeInteger(row.taille_octets) && Number(row.taille_octets) > 0 && Number(row.taille_octets) <= 10 * 1024 * 1024
      && typeof row.sha256 === 'string' && /^[a-f0-9]{64}$/.test(row.sha256)
      && Array.isArray(row.mission_ids) && row.mission_ids.length > 0 && row.mission_ids.every(id => typeof id === 'string' && uuid.test(id))
      && typeof row.signalee === 'boolean'
      && (row.remplace_id === null || (typeof row.remplace_id === 'string' && uuid.test(row.remplace_id)))
      && [null, 'CONTENU', 'AUTRE'].includes(row.motif_remplacement as null | string);
  })) throw new Error('La liste des copies ne peut pas être vérifiée. Réessayez.');
  return data as CopieBulletin[];
}

export async function listerCopiesBulletins(etablissementId: string | null = null, missionId: string | null = null): Promise<CopieBulletin[]> {
  const { data, error } = await avecDelai(supabase.rpc('fn_lister_copies_bulletins' as any, {
    p_etablissement_id: etablissementId, p_mission_id: missionId,
  }), 15_000);
  if (error) throw new Error('Impossible de charger les copies des bulletins. Réessayez.');
  return validerListeCopiesBulletins(data);
}

export async function chargerMissionsCopies(etablissementId: string, debut: string, fin: string): Promise<MissionCopieBulletin[]> {
  const { data: profils, error: erreurProfils } = await avecDelai(supabase.rpc('fn_mes_soignants_etablissement'), 15_000);
  if (erreurProfils || !Array.isArray(profils)) throw new Error('Les destinataires ne peuvent pas être vérifiés. Réessayez.');
  const noms = new Map((profils as unknown as { id: string; nom: string; prenom: string }[]).map(p => [p.id, p]));
  const missions: MissionCopieBulletin[] = [];
  for (let offset = 0; ; offset += 200) {
    const { data, error } = await avecDelai(supabase.from('missions')
      .select('id,intitule,debut_le,fin_le,soignant_assigne_id')
      .eq('etablissement_id', etablissementId).eq('type_contrat_applique', 'SALARIE')
      .not('statut', 'in', '(OUVERTE,EXPIREE)')
      .not('soignant_assigne_id', 'is', null)
      .lt('debut_le', ajouterJoursCivilsParis(debutJourParis(fin), 1).toISOString()).gt('fin_le', debutJourParis(debut).toISOString())
      .order('id').range(offset, offset + 199), 15_000);
    if (error || !data) throw new Error('Les missions salariées ne peuvent pas être chargées. Réessayez.');
    for (const m of data) {
      const profil = noms.get(m.soignant_assigne_id ?? '');
      if (!profil) throw new Error('Le destinataire d’une mission ne peut pas être vérifié. Réessayez.');
      missions.push({ id: m.id, intitule: m.intitule, debut_le: m.debut_le, fin_le: m.fin_le,
        soignant_id: profil.id, soignant_nom: profil.nom, soignant_prenom: profil.prenom });
    }
    if (data.length < 200) return missions;
  }
}

export async function empreintePdfCopie(file: File): Promise<string> {
  const verification = await verifierFichierDocument(file, { maxBytes: 10 * 1024 * 1024, allowedMimes: ['application/pdf'] });
  if (verification.ok === false) throw new Error(verification.message);
  const hash = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
  return Array.from(new Uint8Array(hash), octet => octet.toString(16).padStart(2, '0')).join('');
}

async function obtenirIdempotenceCopie(userId: string, depot: DepotCopieBulletin, sha256: string, idempotenceRetiree?: string): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify({ ...depot, missionIds: [...depot.missionIds].sort(), sha256 }));
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
  const key = `jolene.copie-bulletin.${userId}.${hash}`;
  try {
    const previous = sessionStorage.getItem(key);
    if (previous && /^[0-9a-f-]{36}$/i.test(previous) && previous !== idempotenceRetiree) return previous;
  } catch { /* The caller retains its intention for in-memory retries. */ }
  const id = crypto.randomUUID();
  try { sessionStorage.setItem(key, id); } catch { /* Session storage may be disabled. */ }
  return id;
}

/** Stable across a lost response and a reload; no PDF, name or period is stored. */
export async function idempotenceCopie(userId: string, depot: DepotCopieBulletin, sha256: string): Promise<string> {
  return obtenirIdempotenceCopie(userId, depot, sha256);
}

/** Explicit user action after a confirmed withdrawal; the old server intention is untouched. */
export async function nouvelleIdempotenceCopie(userId: string, depot: DepotCopieBulletin, sha256: string, idempotenceRetiree: string): Promise<string> {
  return obtenirIdempotenceCopie(userId, depot, sha256, idempotenceRetiree);
}

async function pdfRefuseParServeur(error: unknown): Promise<boolean> {
  if (!(error instanceof FunctionsHttpError) || typeof Response === 'undefined'
    || !(error.context instanceof Response) || error.context.status !== 422) return false;
  try {
    // Inspect only the known refusal, without consuming the original response
    // or letting a stalled/malformed body hide the existing retry guidance.
    const payload: unknown = await avecDelai(error.context.clone().json(), 1_000);
    return payload !== null && typeof payload === 'object' && !Array.isArray(payload)
      && 'error' in payload && payload.error === 'COPIE_PDF_INVALIDE';
  } catch { return false; }
}

export async function publierCopieBulletin(depot: DepotCopieBulletin, file: File, sha256: string, idempotence: string, progression: (message: string) => void): Promise<string> {
  progression('Réservation du dépôt…');
  const { data, error } = await avecDelai(supabase.rpc('fn_reserver_copie_bulletin' as any, {
    p_etablissement_id: depot.etablissementId, p_soignant_id: depot.soignantId,
    p_periode_debut: depot.periodeDebut, p_periode_fin: depot.periodeFin,
    p_mission_ids: depot.missionIds, p_idempotence: idempotence,
    p_sha256_attendu: sha256, p_taille_attendue: file.size,
    p_remplace_id: depot.remplaceId, p_motif_remplacement: depot.motifRemplacement,
  }), 15_000);
  if (error?.message === 'COPIE_RETIREE') throw new CopieRetireeErreur();
  if (error) throw new Error('Le dépôt ne peut pas être réservé. Vérifiez le destinataire, la période, les missions et vos droits, puis réessayez.');
  const reservation = data as unknown as ReservationCopie;
  if (!reservation || typeof reservation.id !== 'string' || !/^[0-9a-f-]{36}$/i.test(reservation.id)
    || !['RESERVEE', 'PUBLIEE', 'REMPLACEE', 'RETIREE'].includes(reservation.statut)) throw new Error('La réservation du dépôt n’a pas été confirmée. Réessayez.');
  if (reservation.statut === 'RETIREE') throw new CopieRetireeErreur();
  if (reservation.statut === 'RESERVEE') {
    if (reservation.bucket !== 'copies-bulletins-paie' || reservation.storage_path !== `${reservation.id}/original.pdf`) throw new Error('Le dépôt réservé ne peut pas être vérifié.');
    progression('Envoi du PDF…');
    const upload = await avecDelai(supabase.storage.from(reservation.bucket).upload(reservation.storage_path, file.slice(0, file.size, 'application/pdf'), { contentType: 'application/pdf', upsert: false }), 60_000,
      'L’envoi n’a pas été confirmé à temps. Réessayez avec le même fichier pour reprendre ce dépôt.');
    // A lost upload response can leave the immutable object in place. The
    // server must verify that exact reservation before declaring publication.
    if (upload.error && !['409', 'Duplicate'].includes(String((upload.error as { statusCode?: string; error?: string }).statusCode ?? (upload.error as { error?: string }).error ?? ''))) {
      throw new Error('L’envoi n’a pas été confirmé. Gardez ce fichier et réessayez : le même dépôt sera repris.');
    }
  }
  progression('Vérification et publication du PDF…');
  const result = await avecDelai(supabase.functions.invoke('copies-bulletins', { body: { action: 'finaliser', copie_id: reservation.id, destinataire_confirme: true } }), 30_000,
    'La publication n’a pas été confirmée à temps. Réessayez avec le même fichier pour retrouver le résultat du dépôt.');
  if (result.error || !result.data?.ok || !['PUBLIEE', 'REMPLACEE'].includes(result.data.statut)) {
    if (await pdfRefuseParServeur(result.error)) {
      throw new Error('Le PDF a été refusé : il est illisible, invalide ou protégé. Choisissez « Modifier le dépôt », puis sélectionnez un PDF lisible et non protégé.');
    }
    throw new Error('La publication n’a pas été confirmée. Le serveur doit vérifier le PDF et vos droits. Réessayez avec ce même fichier ; aucun second dépôt ne sera créé.');
  }
  return reservation.id;
}

export async function signalerCopieBulletin(id: string, motif: MotifSignalementCopie): Promise<void> {
  const { data, error } = await avecDelai(supabase.rpc('fn_signaler_copie_bulletin' as any, { p_copie_id: id, p_motif: motif }), 15_000);
  if (error || !(data as { ok?: boolean } | null)?.ok) throw new Error('Le signalement n’a pas été confirmé. Réessayez.');
}
export async function retirerCopieBulletin(id: string): Promise<void> {
  const { data, error } = await avecDelai(supabase.rpc('fn_retirer_copie_bulletin' as any, { p_copie_id: id }), 15_000);
  if (error || !(data as { ok?: boolean } | null)?.ok) throw new Error('Le retrait n’a pas été confirmé. Réessayez.');
}

/** Original bytes only: no jsPDF reconstruction, persistent URL or PDF cache. */
export async function ouvrirCopieBulletin(copie: CopieBulletin): Promise<void> {
  if (!copieBulletinTelechargeable(copie)) throw new Error('Cette copie a été retirée. Son PDF n’est plus accessible.');
  const native = isNative();
  const fenetre = native ? null : window.open('', '_blank');
  if (!native && !fenetre) throw new Error('Autorisez l’ouverture du PDF dans votre navigateur, puis réessayez.');
  if (fenetre) { fenetre.opener = null; fenetre.document.title = 'Chargement du PDF…'; }
  try {
    const { data, error } = await avecDelai(supabase.functions.invoke('copies-bulletins', { body: { action: 'telecharger', copie_id: copie.id } }), 30_000);
    if (error || !(data instanceof Blob) || data.type !== 'application/pdf' || data.size === 0) {
      throw new Error('Le PDF ne peut pas être ouvert. Votre accès ou la disponibilité du document a pu changer. Réessayez.');
    }
    const bytes = await data.arrayBuffer();
    const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
    if (sha256 !== copie.sha256 || data.size !== copie.taille_octets) throw new Error('L’intégrité du PDF ne peut pas être confirmée. Réessayez.');
    if (fenetre) {
      const url = URL.createObjectURL(data);
      fenetre.location.replace(url);
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    } else {
      const [{ Filesystem, Directory }, { Share }] = await Promise.all([import('@capacitor/filesystem'), import('@capacitor/share')]);
      const path = `copie-paie-${copie.id}.pdf`;
      const octets = new Uint8Array(bytes);
      let binary = '';
      for (let start = 0; start < octets.length; start += 8192) binary += String.fromCharCode(...octets.subarray(start, start + 8192));
      let fichierEcrit = false;
      try {
        await Filesystem.writeFile({ path, data: btoa(binary), directory: Directory.Cache });
        fichierEcrit = true;
        const { uri } = await Filesystem.getUri({ path, directory: Directory.Cache });
        await Share.share({ url: uri, title: 'Copie du bulletin de paie' });
      } finally {
        if (fichierEcrit) await Filesystem.deleteFile({ path, directory: Directory.Cache });
      }
    }
  } catch (error) {
    fenetre?.close();
    if (error instanceof Error && /share cancel(?:ed|led)|partage annul/i.test(error.message)) return;
    throw error;
  }
}
