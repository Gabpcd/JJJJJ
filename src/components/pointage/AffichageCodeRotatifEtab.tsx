import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { QRCodeSVG } from 'qrcode.react';
import { CalendarClock, Hash, RefreshCw, Clock } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { extraireMessageErreur } from '@/lib/erreurs';
import { toast } from 'sonner';
import {
  choisirContratPointage,
  creneauxPrevisionnels,
  evaluerDisponibilitePointage,
  FENETRE_OUVERTURE_POINTAGE_MINUTES,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import { analyserCompletudePlanningMission } from '@/lib/completude-planning-mission';
import {
  formatParis,
  instantJolene,
  instantDepuisSaisieParis,
  memeJourParis,
  valeurSaisieDateHeureParis,
} from '@/lib/date-heure-paris';

/** Valeur "datetime-local" (heure locale) pour le défaut "maintenant". */
function nowLocalInput(): string {
  return valeurSaisieDateHeureParis();
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

function trouverCreneauAssocie(
  planifies: CreneauPointage[],
  debutEffectif: string,
): CreneauPointage | null {
  const debutEffectifMs = instantJolene(debutEffectif).getTime();
  if (!Number.isFinite(debutEffectifMs)) return null;

  const contenant = planifies.find((creneau) => {
    if (!creneau.fin) return false;
    const debutMs = instantJolene(creneau.debut).getTime();
    const finMs = instantJolene(creneau.fin).getTime();
    // Borne de fin exclusive : à l'heure exacte où un second shift démarre,
    // celui-ci doit être choisi plutôt que le shift précédent qui se termine.
    return debutEffectifMs >= debutMs && debutEffectifMs < finMs;
  });
  if (contenant) return contenant;

  return [...planifies].sort((a, b) => (
    Math.abs(instantJolene(a.debut).getTime() - debutEffectifMs)
    - Math.abs(instantJolene(b.debut).getTime() - debutEffectifMs)
  ))[0] ?? null;
}

function dureeSegment(debut: string, fin: string | null): string {
  const d = instantJolene(debut).getTime();
  const f = fin ? instantJolene(fin).getTime() : Date.now();
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
          .select('id, debut_le, fin_le, nb_creneaux')
          .eq('id', missionId)
          .single(),
        supabase
          .from('mission_creneaux')
          .select('id, mission_id, debut, fin, est_pause, type_creneau')
          .eq('mission_id', missionId)
          .eq('type_creneau', 'PREVISIONNEL')
          .eq('est_pause', false)
          .order('debut', { ascending: true }),
        supabase
          .from('contrats_mission')
          .select('id, mission_id, statut, cree_le')
          .eq('mission_id', missionId),
      ]);
      if (missionResult.error) throw missionResult.error;
      if (creneauxResult.error) throw creneauxResult.error;
      if (contratsResult.error) throw contratsResult.error;

      const analysePlanning = analyserCompletudePlanningMission(
        missionResult.data,
        (creneauxResult.data || []) as CreneauPointage[],
      );
      return {
        creneaux: analysePlanning.creneauxPlanifies,
        planningComplet: analysePlanning.complet,
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
    try {
      const heureFinInstant = instantDepuisSaisieParis(heureFin);
      const { error } = await supabase.rpc('fn_declarer_fin_retroactive' as any, {
        p_mission_id: missionId,
        p_heure_fin: heureFinInstant.toISOString(),
        p_raison: "Clôture par l'établissement (oubli de scan / sans téléphone)",
      });
      if (error) throw error;

      toast.success('Segment clôturé.');
      setFallbackOuvert(false);
      setHeureFin('');
      void refetch();
    } catch (error) {
      toast.error(
        error instanceof RangeError
          ? 'Cette heure n’existe pas à Paris en raison du passage à l’heure d’été. Choisissez une autre heure.'
          : extraireMessageErreur(error),
      );
    } finally {
      setEnvoiFallback(false);
    }
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

  const code = data.code_pointage_actif;
  const segmentsOuverts: CreneauPointage[] = data.segments
    .filter((segment) => !segment.fin)
    .map((segment) => ({
      ...segment,
      est_pause: false,
      type_creneau: 'EFFECTIF',
    }));
  const departToujoursPossible = segmentsOuverts.length > 0;
  const planningInutilisable = planningErreur || !planning || !planning.planningComplet;

  // Une arrivée ne doit jamais être autorisée depuis un planning incomplet.
  // Un départ reste toutefois possible lorsqu'un EFFECTIF est déjà ouvert.
  if (planningInutilisable && !departToujoursPossible) {
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
              {planningErreur || !planning
                ? 'Le planning détaillé est momentanément indisponible. Réessayez avant de présenter un code au soignant.'
                : 'Le planning détaillé est incomplet ou ne correspond pas au nombre de créneaux prévu. Confirmez-le avant de présenter un code d’arrivée.'}
            </p>
          </div>
        </div>
      </div>
    );
  }

  const creneauxPlanning = planning?.creneaux ?? [];
  const planifies = creneauxPrevisionnels(creneauxPlanning);
  const disponibilite = evaluerDisponibilitePointage({
    creneaux: [...creneauxPlanning, ...segmentsOuverts],
    contratStatut: planning?.contratStatut,
    maintenant,
  });
  const afficherCode = Boolean(code && disponibilite.peutPointer);
  const segmentOuvert = segmentsOuverts[0] ?? null;
  const creneauActif = segmentOuvert
    ? trouverCreneauAssocie(planifies, segmentOuvert.debut)
    : disponibilite.creneauCourant;
  const indexCreneauActif = creneauActif ? planifies.indexOf(creneauActif) : -1;
  const indexProchainCreneau = disponibilite.prochainCreneau
    ? planifies.indexOf(disponibilite.prochainCreneau)
    : -1;
  const formatCode = (c: string) => `${c.slice(0, 3)} ${c.slice(3)}`;
  const dernierSegmentFerme = [...data.segments]
    .filter((segment) => Boolean(segment.fin))
    .sort((a, b) => instantJolene(a.debut).getTime() - instantJolene(b.debut).getTime())
    .at(-1) ?? null;
  const creneauDuDernierSegment = dernierSegmentFerme
    ? trouverCreneauAssocie(planifies, dernierSegmentFerme.debut)
    : null;
  const estRepriseDuMemeCreneau = Boolean(
    dernierSegmentFerme
    && memeJourParis(dernierSegmentFerme.debut, maintenant)
    && disponibilite.creneauCourant
    && creneauDuDernierSegment === disponibilite.creneauCourant,
  );
  const prochainLabel = data.prochain_type_scan === 'OUVERTURE'
    ? (estRepriseDuMemeCreneau ? 'Reprise (fin de pause)' : 'Arrivée')
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
          {formatParis(creneauActif.debut, 'EEEE d MMMM yyyy à HH:mm')}
          {' → '}{formatParis(creneauActif.fin, 'HH:mm')}
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
                    ? `Le code sera affiché ${FENETRE_OUVERTURE_POINTAGE_MINUTES} minutes avant le créneau ${indexProchainCreneau + 1}/${planifies.length}, le ${formatParis(disponibilite.prochainCreneau.debut, 'EEEE d MMMM yyyy à HH:mm')}.`
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
                Segment {i + 1} · {formatParis(s.debut, "dd/MM/yyyy HH'h'mm")}
                {s.fin ? ` → ${formatParis(s.fin, "dd/MM/yyyy HH'h'mm")}` : ' → en cours'}
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
