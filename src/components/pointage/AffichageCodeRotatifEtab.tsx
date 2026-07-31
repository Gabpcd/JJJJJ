import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { QRCodeSVG } from 'qrcode.react';
import { CalendarClock, Hash, RefreshCw, Clock } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { extraireMessageErreur } from '@/lib/erreurs';
import { toast } from 'sonner';
import { format, isSameDay } from 'date-fns';
import { fr } from 'date-fns/locale';
import {
  ajouterRepliMissionPonctuelle,
  choisirContratPointage,
  creneauxPrevisionnels,
  evaluerDisponibilitePointage,
  FENETRE_OUVERTURE_POINTAGE_MINUTES,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';

/** Valeur "datetime-local" (heure locale) pour le défaut "maintenant". */
function nowLocalInput(): string {
  const d = new Date();
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().slice(0, 16);
}

/**
 * Pointage rotatif (PR 2/3) — affichage côté ÉTABLISSEMENT.
 *
 * Montre le code de pointage COURANT (`code_pointage_actif`), qui se régénère à
 * chaque scan du soignant (fn_scanner_code_pointage). L'étab montre cet écran au
 * soignant qui le scanne (QR) ou le saisit (6 chiffres) depuis SON app.
 *
 * Rafraîchissement par polling (5 s) : dès que le soignant pointe, le code change
 * et le nouveau s'affiche ici.
 */
interface Segment { id: string; debut: string; fin: string | null }
interface EtatPointage {
  statut: string;
  prochain_type_scan: 'OUVERTURE' | 'FERMETURE';
  segment_ouvert: boolean;
  segments: Segment[];
  code_pointage_actif: string | null;
  error?: string;
}

function dureeSegment(debut: string, fin: string | null): string {
  const d = new Date(debut).getTime();
  const f = fin ? new Date(fin).getTime() : Date.now();
  const min = Math.max(0, Math.round((f - d) / 60000));
  const h = Math.floor(min / 60);
  return h > 0 ? `${h}h${String(min % 60).padStart(2, '0')}` : `${min} min`;
}

export function AffichageCodeRotatifEtab({ missionId }: { missionId: string }) {
  const [maintenant, setMaintenant] = useState(() => new Date());
  useEffect(() => {
    const intervalle = window.setInterval(() => setMaintenant(new Date()), 15_000);
    return () => window.clearInterval(intervalle);
  }, []);

  const { data, isLoading, isError, error: etatErreur, refetch } = useQuery({
    queryKey: ['etat-pointage-rotatif', missionId],
    queryFn: async () => {
      const { data: etat, error } = await supabase.rpc('fn_etat_pointage_mission' as any, { p_mission_id: missionId });
      if (error) throw error;
      return etat as EtatPointage;
    },
    refetchInterval: 5000,
    staleTime: 0,
  });
  const { data: planning, isLoading: planningLoading, isError: planningErreur } = useQuery({
    queryKey: ['planning-pointage-rotatif', missionId],
    queryFn: async () => {
      const [missionResult, creneauxResult, contratsResult] = await Promise.all([
        supabase
          .from('missions')
          .select('id, debut_le, fin_le')
          .eq('id', missionId)
          .single(),
        supabase
          .from('mission_creneaux')
          .select('id, mission_id, debut, fin, est_pause, type_creneau')
          .eq('mission_id', missionId)
          .eq('type_creneau', 'PREVISIONNEL')
          .eq('est_pause', false)
          .not('fin', 'is', null)
          .order('debut', { ascending: true }),
        supabase
          .from('contrats_mission')
          .select('id, mission_id, statut, cree_le')
          .eq('mission_id', missionId),
      ]);
      if (missionResult.error) throw missionResult.error;
      if (creneauxResult.error) throw creneauxResult.error;
      if (contratsResult.error) throw contratsResult.error;

      return {
        creneaux: ajouterRepliMissionPonctuelle(
          (creneauxResult.data || []) as CreneauPointage[],
          missionResult.data,
        ),
        contratStatut: choisirContratPointage(contratsResult.data || [])?.statut ?? null,
      };
    },
    staleTime: 60_000,
  });

  const [fallbackOuvert, setFallbackOuvert] = useState(false);
  const [heureFin, setHeureFin] = useState('');
  const [envoiFallback, setEnvoiFallback] = useState(false);

  const cloturerRetroactif = async () => {
    if (!heureFin || envoiFallback) return;
    setEnvoiFallback(true);
    const { error } = await supabase.rpc('fn_declarer_fin_retroactive' as any, {
      p_mission_id: missionId,
      p_heure_fin: new Date(heureFin).toISOString(),
      p_raison: "Clôture par l'établissement (oubli de scan / sans téléphone)",
    });
    setEnvoiFallback(false);
    if (error) { toast.error(extraireMessageErreur(error)); return; }
    toast.success('Segment clôturé.');
    setFallbackOuvert(false);
    setHeureFin('');
    refetch();
  };

  if (isLoading || planningLoading) {
    return <div className="card-base text-sm text-muted-foreground" role="status">Chargement du code de pointage…</div>;
  }
  if (isError || !data || data.error) {
    return (
      <div className="card-base border-destructive/30" role="alert">
        <p className="font-semibold text-destructive">Code de pointage indisponible</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {data?.error || (etatErreur ? extraireMessageErreur(etatErreur) : 'Impossible de charger l’état du pointage.')}
        </p>
        <BoutonY2K size="sm" variant="secondary" className="mt-3" onClick={() => refetch()}>
          Réessayer
        </BoutonY2K>
      </div>
    );
  }
  if (!['ASSIGNEE', 'EN_COURS'].includes(data.statut)) return null;
  if (planningErreur || !planning) {
    return (
      <div className="card-base" role="alert">
        <div className="flex items-center gap-2">
          <Hash className="h-5 w-5 text-primary" />
          <h2 className="font-semibold text-foreground">Code de pointage</h2>
        </div>
        <div className="mt-3 flex items-start gap-3 rounded-xl border border-dashed border-warning/40 bg-warning/5 p-4">
          <CalendarClock className="mt-0.5 h-5 w-5 shrink-0 text-warning" />
          <div>
            <p className="text-sm font-semibold text-foreground">Code masqué</p>
            <p className="mt-1 text-xs text-muted-foreground">
              Le planning détaillé est momentanément indisponible. Réessayez avant de présenter un code au soignant.
            </p>
          </div>
        </div>
      </div>
    );
  }

  const code = data.code_pointage_actif;
  const planifies = creneauxPrevisionnels(planning.creneaux);
  const segmentsOuverts: CreneauPointage[] = data.segments
    .filter((segment) => !segment.fin)
    .map((segment) => ({
      ...segment,
      est_pause: false,
      type_creneau: 'EFFECTIF',
    }));
  const disponibilite = evaluerDisponibilitePointage({
    creneaux: [...planning.creneaux, ...segmentsOuverts],
    contratStatut: planning.contratStatut,
    maintenant,
  });
  const afficherCode = Boolean(code && disponibilite.peutPointer);
  const segmentOuvert = segmentsOuverts[0] ?? null;
  const creneauActif = segmentOuvert
    ? planifies.find((creneau) => isSameDay(new Date(creneau.debut), new Date(segmentOuvert.debut))) ?? null
    : disponibilite.creneauCourant;
  const indexCreneauActif = creneauActif ? planifies.indexOf(creneauActif) : -1;
  const indexProchainCreneau = disponibilite.prochainCreneau
    ? planifies.indexOf(disponibilite.prochainCreneau)
    : -1;
  const formatCode = (c: string) => `${c.slice(0, 3)} ${c.slice(3)}`;
  const prochainLabel = data.prochain_type_scan === 'OUVERTURE'
    ? (data.segments.length === 0 ? 'Arrivée' : 'Reprise (fin de pause)')
    : 'Départ ou pause';

  return (
    <div className="card-base">
      <div className="flex items-center gap-2 mb-3">
        <Hash className="h-5 w-5 text-primary" />
        <h2 className="font-semibold text-foreground">Code de pointage</h2>
        {afficherCode ? (
          <span className="ml-auto inline-flex items-center gap-1 text-[11px] text-muted-foreground">
            <RefreshCw className="h-3 w-3" /> change à chaque scan
          </span>
        ) : null}
      </div>

      {afficherCode ? (
        <p className="text-xs text-muted-foreground mb-4">
          Montrez ce code (ou le QR) au soignant à chaque pointage. Prochain pointage attendu :{' '}
          <span className="font-semibold text-foreground">{prochainLabel}</span>.
        </p>
      ) : null}

      {creneauActif?.fin && (
        <p className="mb-3 text-xs font-medium text-foreground">
          Créneau {indexCreneauActif + 1}/{planifies.length} ·{' '}
          {format(new Date(creneauActif.debut), 'EEEE d MMMM yyyy à HH:mm', { locale: fr })}
          {' → '}{format(new Date(creneauActif.fin), 'HH:mm', { locale: fr })}
        </p>
      )}

      {afficherCode && code ? (
        <div className="flex flex-col items-center gap-3 rounded-2xl border border-primary/20 bg-primary/5 p-4">
          <p className="text-4xl font-mono font-black text-foreground tracking-[0.3em]">{formatCode(code)}</p>
          <div className="bg-card p-3 rounded-xl">
            <QRCodeSVG value={code} size={150} level="M" />
          </div>
          {data.segment_ouvert && (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-success/10 text-success text-xs font-semibold px-3 py-1">
              <Clock className="h-3.5 w-3.5" /> Segment en cours
            </span>
          )}
        </div>
      ) : disponibilite.peutPointer ? (
        <p className="text-sm text-muted-foreground">Code momentanément indisponible. Actualisez dans quelques secondes.</p>
      ) : (
        <div className="rounded-xl border border-dashed border-primary/30 bg-primary/5 p-4" role="status">
          <div className="flex items-start gap-3">
            <CalendarClock className="mt-0.5 h-5 w-5 shrink-0 text-primary" />
            <div>
              <p className="text-sm font-semibold text-foreground">
                {disponibilite.motif === 'CONTRAT' ? 'Code masqué — contrat non signé' : 'Code masqué hors créneau'}
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                {disponibilite.motif === 'CONTRAT'
                  ? 'Le code d’arrivée sera disponible lorsque le contrat aura été signé par les deux parties.'
                  : planifies.length === 0
                  ? 'Aucun créneau détaillé n’est planifié pour cette mission. Le code sera disponible après confirmation du planning.'
                  : disponibilite.prochainCreneau?.fin
                    ? `Le code sera affiché ${FENETRE_OUVERTURE_POINTAGE_MINUTES} minutes avant le créneau ${indexProchainCreneau + 1}/${planifies.length}, le ${format(new Date(disponibilite.prochainCreneau.debut), 'EEEE d MMMM yyyy à HH:mm', { locale: fr })}.`
                    : 'Tous les créneaux planifiés sont terminés.'}
              </p>
            </div>
          </div>
        </div>
      )}

      {data.segments.length > 0 && (
        <div className="mt-4 space-y-1.5">
          <p className="text-xs font-semibold text-muted-foreground">Pointages enregistrés</p>
          {data.segments.map((s, i) => (
            <div key={s.id} className="flex items-center justify-between text-xs text-foreground rounded-lg bg-muted/40 px-3 py-1.5">
              <span>
                Segment {i + 1} · {format(new Date(s.debut), "dd/MM/yyyy HH'h'mm", { locale: fr })}
                {s.fin ? ` → ${format(new Date(s.fin), "dd/MM/yyyy HH'h'mm", { locale: fr })}` : ' → en cours'}
              </span>
              <span className="font-semibold">{dureeSegment(s.debut, s.fin)}</span>
            </div>
          ))}
        </div>
      )}

      {/* Fallback « oubli de scan / sans téléphone » : l'étab clôture le segment
          ouvert en saisissant l'heure de fin réelle (fn_declarer_fin_retroactive). */}
      {data.segment_ouvert && (
        <div className="mt-4 pt-3 border-t border-border">
          {!fallbackOuvert ? (
            <button
              onClick={() => { setFallbackOuvert(true); setHeureFin(nowLocalInput()); }}
              className="text-xs font-medium text-primary hover:underline"
            >
              Le soignant n'a pas pu scanner sa sortie ? Clôturer le segment →
            </button>
          ) : (
            <div className="space-y-2">
              <p className="text-xs text-muted-foreground">
                Saisissez l'heure de fin réelle. La saisie est tracée (oubli de scan).
              </p>
              <input
                type="datetime-local"
                aria-label="Heure de fin réelle"
                value={heureFin}
                onChange={(e) => setHeureFin(e.target.value)}
                className="input-base text-sm w-full"
              />
              <div className="flex gap-2">
                <BoutonY2K size="sm" variant="primary" onClick={cloturerRetroactif} loading={envoiFallback} disabled={!heureFin || envoiFallback}>
                  Clôturer le segment
                </BoutonY2K>
                <BoutonY2K size="sm" variant="ghost" onClick={() => setFallbackOuvert(false)} disabled={envoiFallback}>
                  Annuler
                </BoutonY2K>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
