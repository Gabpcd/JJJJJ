/**
 * CardMissionSwipe — Sprint 13-B PR 1
 *
 * Card Y2K plein écran mobile pour swipe Hinge-style.
 * Affichage compact des infos clés d'une mission + badge score matching.
 *
 * Usage :
 *   <CardMissionSwipe mission={mission} onTap={() => setDetailOpen(true)} />
 *
 * Stylé pour ~80vh mobile, photo cover établissement, gradient rose-mauve overlay.
 */
import { CalendarDays, Clock, Euro, MapPin, Sparkles, Star, HeartPulse } from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { cn } from '@/lib/utils';

export interface MissionSwipePayload {
  mission_id: string;
  intitule: string;
  profession_requise: string | null;
  etablissement_id: string;
  etablissement_nom: string;
  etablissement_ville: string | null;
  etablissement_score: number | null;
  taux_horaire_base: number | null;
  total_brut: number | null;
  net_a_payer: number | null;
  net_estime: number | null;
  montant_ifm: number | null;
  montant_icp: number | null;
  montant_majoration_nuit: number | null;
  montant_majoration_dimanche: number | null;
  montant_majoration_ferie: number | null;
  type_contrat_applique: string | null;
  duree_heures: number | null;
  debut_le: string | null;
  fin_le: string | null;
  est_urgente: boolean;
  service: string | null;
  score: number;
  breakdown: Record<string, unknown>;
}

interface Props {
  mission: MissionSwipePayload;
  onTap?: () => void;
  className?: string;
}

function formatDate(iso: string | null): string {
  if (!iso) return '—';
  try {
    const d = new Date(iso);
    return d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' });
  } catch {
    return '—';
  }
}

function formatHeure(iso: string | null): string {
  if (!iso) return '';
  try {
    return new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  } catch {
    return '';
  }
}

export function CardMissionSwipe({ mission, onTap, className }: Props) {
  const scoreEleve = mission.score >= 80;
  const debut = formatDate(mission.debut_le);
  const heureDebut = formatHeure(mission.debut_le);
  const heureFin = formatHeure(mission.fin_le);

  return (
    <button
      type="button"
      onClick={onTap}
      className={cn(
        'relative w-full h-[80vh] max-h-[640px] rounded-3xl overflow-hidden',
        'bg-gradient-to-br from-jolene-rose-100 via-jolene-mauve-100 to-jolene-lavender-100',
        'border-2 border-jolene-rose-200 shadow-holographic',
        'transition-bouncy text-left',
        'focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-jolene-rose-400',
        className,
      )}
      aria-label={`Mission ${mission.intitule} à ${mission.etablissement_nom}, score matching ${mission.score} sur 100. Toucher pour détail.`}
    >
      {/* Background pattern / gradient overlay décoratif */}
      <div
        className="absolute inset-0 opacity-50 pointer-events-none"
        style={{
          background:
            'radial-gradient(circle at 30% 20%, hsl(var(--jolene-rose) / 0.4) 0%, transparent 50%), radial-gradient(circle at 70% 80%, hsl(var(--jolene-mauve) / 0.3) 0%, transparent 50%)',
        }}
        aria-hidden="true"
      />

      {/* Top : score + urgence */}
      <div className="absolute top-4 left-4 right-4 flex items-start justify-between gap-2 z-10">
        <BadgeY2K
          variant={scoreEleve ? 'premium' : 'info'}
          size="md"
          icone={<Sparkles className="h-3.5 w-3.5" />}
          className="shadow-md"
        >
          Match {mission.score}/100
        </BadgeY2K>
        {mission.est_urgente && (
          <BadgeY2K variant="warning" size="md" className="shadow-md">
            ⚡ Urgent
          </BadgeY2K>
        )}
      </div>

      {/* Hero central : remplit l'espace haut (pas de photo établissement) avec un
          watermark + la profession en grand, pour une carte vivante et lisible. */}
      <div className="absolute inset-x-0 top-[14%] flex flex-col items-center text-center px-6 z-[5] pointer-events-none">
        <HeartPulse
          className="h-20 w-20 text-white/70 drop-shadow-[0_4px_12px_rgba(0,0,0,0.15)] mb-3"
          strokeWidth={1.5}
          aria-hidden="true"
        />
        <p className="text-3xl font-extrabold text-white drop-shadow-[0_2px_8px_rgba(0,0,0,0.25)] tracking-tight">
          {mission.profession_requise || 'Mission'}
        </p>
        {mission.service && (
          <p className="text-sm font-semibold text-white/90 drop-shadow-[0_1px_4px_rgba(0,0,0,0.25)] mt-1 uppercase tracking-wider">
            {mission.service}
          </p>
        )}
      </div>

      {/* Body : infos principales */}
      <div className="absolute bottom-0 left-0 right-0 p-6 z-10">
        <div className="bg-jolene-cloud/85 backdrop-blur-xl rounded-2xl p-5 shadow-holographic border border-white/40">
          <p className="text-xs font-semibold text-jolene-bubblegum uppercase tracking-wider mb-1">
            {mission.profession_requise || 'Profession'}
            {mission.service && ` · ${mission.service}`}
          </p>
          <h2 className="text-xl font-bold text-jolene-midnight leading-tight mb-3">
            {mission.intitule}
          </h2>

          <div className="flex items-center gap-2 mb-3">
            <MapPin className="h-4 w-4 text-jolene-rose-600 shrink-0" aria-hidden="true" />
            <p className="text-sm font-medium text-jolene-midnight truncate">
              {mission.etablissement_nom}
              {mission.etablissement_ville && (
                <span className="text-jolene-bubblegum"> · {mission.etablissement_ville}</span>
              )}
            </p>
            {mission.etablissement_score != null && (
              <span className="ml-auto inline-flex items-center gap-0.5 text-xs font-semibold text-jolene-rose-700 shrink-0">
                <Star className="h-3 w-3 fill-current" aria-hidden="true" />
                {Math.round(mission.etablissement_score)}
              </span>
            )}
          </div>

          <div className="grid grid-cols-3 gap-2 text-xs">
            <div className="flex flex-col items-center justify-center bg-jolene-rose-50 rounded-xl p-2.5">
              <CalendarDays className="h-4 w-4 text-jolene-rose-700 mb-1" aria-hidden="true" />
              <span className="font-semibold text-jolene-midnight">{debut}</span>
              {heureDebut && (
                <span className="text-[10px] text-jolene-bubblegum">
                  {heureDebut}
                  {heureFin && `–${heureFin}`}
                </span>
              )}
            </div>
            <div className="flex flex-col items-center justify-center bg-jolene-mauve-50 rounded-xl p-2.5">
              <Clock className="h-4 w-4 text-jolene-mauve-700 mb-1" aria-hidden="true" />
              <span className="font-semibold text-jolene-midnight">
                {mission.duree_heures ? `${mission.duree_heures}h` : '—'}
              </span>
              <span className="text-[10px] text-jolene-bubblegum">Durée</span>
            </div>
            <div className="flex flex-col items-center justify-center bg-jolene-cyan-50 rounded-xl p-2.5">
              <Euro className="h-4 w-4 text-jolene-cyan-700 mb-1" aria-hidden="true" />
              {mission.net_estime ? (
                <>
                  <span className="font-bold text-jolene-midnight">
                    ~{Math.round(mission.net_estime)}€
                  </span>
                  <span className="text-[10px] text-jolene-bubblegum">Net estimé*</span>
                </>
              ) : (
                <>
                  <span className="font-semibold text-jolene-midnight">
                    {mission.taux_horaire_base ? `${mission.taux_horaire_base}€/h` : '—'}
                  </span>
                  <span className="text-[10px] text-jolene-bubblegum">Tarif</span>
                </>
              )}
            </div>
          </div>

          <p className="text-[11px] text-jolene-bubblegum text-center mt-3">
            Toucher pour voir le détail
          </p>
        </div>
      </div>
    </button>
  );
}

export default CardMissionSwipe;
