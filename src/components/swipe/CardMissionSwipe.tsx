/**
 * CardMissionSwipe — refonte « la carte qui vend » (UX vente)
 *
 * Règle : tout ce qui donne envie de postuler est AU-DESSUS de la ligne de
 * flottaison. Le hook (€ net · durée · moment · date) est l'élément le plus gros.
 * Le score est TOUJOURS justifié (« Pourquoi 85 ? … »). Visuel réel (logo) plutôt
 * qu'un dégradé + cœur générique. Quartier précis + distance.
 *
 *   <CardMissionSwipe mission={mission} onTap={() => setDetailOpen(true)} />
 */
import { MapPin, Sparkles, Star } from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { cn } from '@/lib/utils';
import { PlanningMissionCandidat } from '@/components/planning/PlanningMissionCandidat';
import { montantFinanceAfficheMission } from '@/lib/missionFinanceDisplay';
import {
  construirePlanningCandidat,
  creneauContientNuit,
  type CreneauMissionCandidat,
} from '@/components/planning/planning-candidat';

export interface MissionSwipePayload {
  mission_id: string;
  intitule: string;
  profession_requise: string | null;
  etablissement_id: string;
  etablissement_nom: string;
  etablissement_ville: string | null;
  etablissement_code_postal: string | null;
  etablissement_logo_url: string | null;
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
  type_contrat_recherche: string | null;
  soignant_assigne_id?: string | null;
  taux_rist_plafonne?: number | null;
  rist_plafond_applique?: boolean | null;
  nb_creneaux?: number | null;
  creneaux_planifies?: CreneauMissionCandidat[];
  planning_exact?: boolean;
  erreur_planning?: boolean;
  duree_heures: number | null;
  debut_le: string | null;
  fin_le: string | null;
  est_urgente: boolean;
  service: string | null;
  distance_km: number | null;
  score: number;
  breakdown: Record<string, unknown>;
  /** 7c — ⚡ Paiement rapide, gating 100 % serveur (feature flag + mission
   *  LIBERAL + étab SEPA actif). Absent/false = pas de badge. */
  paiement_rapide?: boolean;
}

interface Props {
  mission: MissionSwipePayload;
  onTap?: () => void;
  className?: string;
}

/** Quartier lisible : « Paris 16e » pour les CP parisiens, sinon « Ville CP ». */
function formatQuartier(ville: string | null, cp: string | null): string {
  if (ville && cp && /^75\d{3}$/.test(cp)) {
    const arr = parseInt(cp.slice(3), 10);
    if (arr >= 1 && arr <= 20) return `${ville} ${arr}${arr === 1 ? 'er' : 'e'}`;
  }
  return [ville, cp].filter(Boolean).join(' ') || ville || '';
}

/**
 * Moment de la mission : férié/dimanche via les majorations payées, mais le
 * jour/nuit est TOUJOURS dérivé des horaires réels (Lot 6a.3 — un montant de
 * majoration nuit absent ne doit pas afficher « jour » sur une garde de 20h).
 */
function momentLabel(m: MissionSwipePayload): string {
  if ((m.montant_majoration_ferie ?? 0) > 0) return '🎉 férié';
  if ((m.montant_majoration_dimanche ?? 0) > 0) return '☀️ dimanche';
  const planning = construirePlanningCandidat(m);
  if (!planning.exact) return 'planning à confirmer';
  return planning.creneaux.some(creneauContientNuit) ? '🌙 nuit' : '☀️ jour';
}

/** 6c.2 : libellé du type de contrat recherché — information de régime au
 *  centre de la carte (type_contrat_applique est NULL tant que non attribuée). */
function contratLabel(m: MissionSwipePayload): string | null {
  const t = m.type_contrat_recherche;
  if (t === 'SALARIE') return 'Salarié (CDD)';
  if (t === 'LIBERAL') return 'Libéral';
  if (t === 'TOUS') return 'Salarié ou libéral';
  return null;
}

/** 7d — clés alignées sur le breakdown v3 (l'ancienne clé `fiabilite` ne
 *  matchait jamais : le backend émet `soignant_fiabilite`). */
const RAISON_LABELS: Record<string, string> = {
  distance: 'proche de chez toi',
  tarif: 'bien payée vs le marché',
  horaire: 'à tes horaires préférés',
  etablissement: 'établissement bien noté',
  urgence: 'mission urgente',
  soignant_fiabilite: 'ton profil correspond',
  connaissance_etab: 'tu connais cet établissement',
  paiement_rapide: 'paiement rapide ⚡',
};

/** Raisons épinglées en priorité quand elles sont > 0 (bonus forts à faible
 *  valeur numérique — un tri par points les enterrerait). */
const RAISONS_EPINGLEES = ['connaissance_etab', 'paiement_rapide'];

/** « Pourquoi 85 ? » → les 2 contributeurs les plus parlants, en clair. */
function raisonsScore(breakdown: Record<string, unknown>): string {
  const b = breakdown || {};
  const epinglees = RAISONS_EPINGLEES.filter(
    (k) => typeof b[k] === 'number' && (b[k] as number) > 0,
  );
  const autres = Object.entries(b)
    .filter(([k, v]) => RAISON_LABELS[k] && !RAISONS_EPINGLEES.includes(k)
      && typeof v === 'number' && (v as number) > 0)
    .sort((a, bb) => (bb[1] as number) - (a[1] as number))
    .map(([k]) => k);
  return [...epinglees, ...autres].slice(0, 2).map((k) => RAISON_LABELS[k]).join(' · ');
}

export function CardMissionSwipe({ mission, onTap, className }: Props) {
  const scoreEleve = mission.score >= 80;
  const quartier = formatQuartier(mission.etablissement_ville, mission.etablissement_code_postal);
  const moment = momentLabel(mission);
  const planning = construirePlanningCandidat(mission);
  const raisons = raisonsScore(mission.breakdown);
  const initiale = (mission.etablissement_nom || '?').trim().charAt(0).toUpperCase();
  const financeAffichee = montantFinanceAfficheMission(mission);

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onTap}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          onTap?.();
        }
      }}
      className={cn(
        'relative w-full h-full rounded-3xl overflow-hidden flex flex-col',
        'border-2 border-jolene-rose-200 shadow-holographic bg-jolene-cloud',
        'transition-bouncy text-left',
        'focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-jolene-rose-400',
        className,
      )}
      aria-label={`Mission ${mission.profession_requise ?? ''} à ${mission.etablissement_nom}${
        financeAffichee
          ? `, ${financeAffichee.approximatif ? 'environ ' : ''}${Math.round(financeAffichee.montant)} euros ${financeAffichee.libelleCourt}`
          : ''
      }, score ${mission.score} sur 100. Toucher pour le détail.`}
    >
      {/* ── Visuel établissement (haut) ─────────────────────────────────── */}
      {/* pb-14 : le visuel central (logo ou initiale) est centré dans la PARTIE
          HAUTE, au-dessus de la bande dégradée du nom (B5 : sinon la grosse
          initiale « C » recouvrait le nom de l'établissement). */}
      <div className="relative h-[140px] shrink-0 bg-gradient-to-br from-jolene-rose-300 via-jolene-mauve-300 to-jolene-cyan-200 flex items-center justify-center overflow-hidden pb-14">
        {mission.etablissement_logo_url ? (
          <>
            {/* Fond flouté du logo pour remplir, logo net contenu au centre */}
            <img
              src={mission.etablissement_logo_url}
              alt=""
              aria-hidden="true"
              className="absolute inset-0 w-full h-full object-cover scale-110 blur-2xl opacity-50"
            />
            <img
              src={mission.etablissement_logo_url}
              alt={mission.etablissement_nom}
              className="relative h-16 w-16 object-contain rounded-2xl bg-white/90 p-1.5 shadow-lg"
            />
          </>
        ) : (
          <div
            className="relative h-16 w-16 rounded-2xl bg-white/20 backdrop-blur-sm flex items-center justify-center shadow-lg"
            aria-hidden="true"
          >
            <span className="text-3xl font-black text-white/95 drop-shadow-[0_4px_12px_rgba(0,0,0,0.2)] select-none">
              {initiale}
            </span>
          </div>
        )}

        {/* Badges overlay */}
        <div className="absolute top-4 left-4 right-4 flex items-start justify-between gap-2 z-10">
          <BadgeY2K
            variant={scoreEleve ? 'premium' : 'info'}
            size="md"
            icone={<Sparkles className="h-3.5 w-3.5" />}
            className="shadow-md"
          >
            {mission.score}/100
          </BadgeY2K>
          <div className="flex flex-col items-end gap-1.5">
            {/* 7c : ⚡ est réservé au paiement rapide — l'urgence passe à 🔥
                (aligné sur le 🔥 URGENT de DetailMissionSoignant). */}
            {mission.est_urgente && (
              <BadgeY2K variant="warning" size="md" className="shadow-md">
                🔥 Urgent
              </BadgeY2K>
            )}
            {mission.paiement_rapide && (
              <BadgeY2K
                variant="success"
                size="md"
                className="shadow-md"
                title="Payée sous 24 à 72 h après validation des présences"
              >
                ⚡ Paiement rapide
              </BadgeY2K>
            )}
          </div>
        </div>

        {/* Dégradé bas pour lisibilité du nom */}
        <div className="absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-black/55 to-transparent pointer-events-none" />
        <div className="absolute inset-x-0 bottom-0 p-4 z-10">
          <h2 className="text-xl font-extrabold text-white leading-tight drop-shadow-[0_2px_6px_rgba(0,0,0,0.4)] truncate">
            {mission.etablissement_nom}
          </h2>
          <div className="flex items-center gap-1.5 mt-0.5 text-white/95 text-sm font-medium drop-shadow-[0_1px_4px_rgba(0,0,0,0.4)]">
            <MapPin className="h-4 w-4 shrink-0" aria-hidden="true" />
            <span className="truncate">{quartier || '—'}</span>
            {mission.distance_km != null && (
              <span className="shrink-0 whitespace-nowrap">· {mission.distance_km} km</span>
            )}
            {mission.etablissement_score != null && (
              <span className="ml-auto inline-flex items-center gap-0.5 shrink-0">
                <Star className="h-3.5 w-3.5 fill-current" aria-hidden="true" />
                {Math.round(mission.etablissement_score)}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* ── Le hook + infos (bas) ───────────────────────────────────────── */}
      <div className="flex-1 flex flex-col p-5 min-h-0">
        {/* HOOK : l'élément le plus gros de la carte */}
        <div className="flex items-baseline gap-2 flex-wrap">
          {financeAffichee ? (
            <span className="text-4xl font-black text-jolene-midnight tracking-tight">
              {financeAffichee.approximatif ? '~' : ''}{Math.round(financeAffichee.montant)}€
              <span className="text-base font-bold text-jolene-bubblegum ml-1">{financeAffichee.libelleCourt}</span>
            </span>
          ) : (
            <span className="text-4xl font-black text-jolene-midnight tracking-tight">
              {mission.taux_horaire_base ? `${mission.taux_horaire_base}€` : '—'}
              <span className="text-base font-bold text-jolene-bubblegum ml-1">/h</span>
            </span>
          )}
        </div>
        <p className="text-base font-bold text-jolene-rose-700 mt-1">
          {planning.exact ? `${planning.totalHeures.toLocaleString('fr-FR', { maximumFractionDigits: 2 })} h` : 'Horaires non vérifiés'} · {moment}
        </p>
        <PlanningMissionCandidat
          mission={mission}
          compact
          limite={2}
          afficherMentionJoursNonTravailles={false}
          className="mt-2"
        />

        {/* Tags spécialité */}
        <div className="flex flex-wrap gap-1.5 mt-3">
          {mission.profession_requise && (
            <span className="inline-flex items-center rounded-full bg-jolene-rose-100 text-jolene-rose-700 text-xs font-semibold px-2.5 py-1">
              {mission.profession_requise}
            </span>
          )}
          {mission.service && (
            <span className="inline-flex items-center rounded-full bg-jolene-mauve-100 text-jolene-mauve-700 text-xs font-semibold px-2.5 py-1">
              {mission.service}
            </span>
          )}
          {contratLabel(mission) && (
            <span className="inline-flex items-center rounded-full bg-jolene-cyan-100 text-jolene-cyan-700 text-xs font-semibold px-2.5 py-1">
              {contratLabel(mission)}
            </span>
          )}
        </div>

        {/* Score expliqué */}
        {raisons && (
          <div className="mt-auto pt-3">
            <p className="text-xs text-jolene-bubblegum">
              <span className="font-semibold text-jolene-midnight">Pourquoi {mission.score} ?</span>{' '}
              {raisons}
            </p>
          </div>
        )}

        <p className="text-[11px] text-jolene-bubblegum text-center mt-2">Toucher pour voir le détail</p>
      </div>
    </div>
  );
}

export default CardMissionSwipe;
