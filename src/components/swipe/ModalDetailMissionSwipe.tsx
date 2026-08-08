/**
 * ModalDetailMissionSwipe — Sprint 13-B PR 5
 *
 * Modal détail mission complet déclenché par tap sur CardMissionSwipe.
 * Glassmorphism Y2K. La candidature passe toujours par un récapitulatif exact.
 */
import { Clock, Euro, MapPin, Sparkles, Star, Tag } from 'lucide-react';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveDescription,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { formatDureeCompacte } from '@/lib/format-mission';
import { PlanningMissionCandidat } from '@/components/planning/PlanningMissionCandidat';
import { construirePlanningCandidat } from '@/components/planning/planning-candidat';
import { montantFinanceAfficheMission } from '@/lib/missionFinanceDisplay';
import type { MissionSwipePayload } from './CardMissionSwipe';

interface Props {
  mission: MissionSwipePayload | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onPostuler: () => void;
  onSuivant: () => void;
}

function formatMontant(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(Number(v))) return '—';
  return new Intl.NumberFormat('fr-FR', {
    style: 'currency',
    currency: 'EUR',
    maximumFractionDigits: 0,
  }).format(Number(v));
}

export function ModalDetailMissionSwipe({ mission, open, onOpenChange, onPostuler, onSuivant }: Props) {
  if (!mission) return null;

  const scoreEleve = mission.score >= 80;
  const planning = construirePlanningCandidat(mission);
  const breakdown = mission.breakdown as Record<string, number | undefined> | undefined;
  const totalMajorations =
    (mission.montant_majoration_nuit || 0) +
    (mission.montant_majoration_dimanche || 0) +
    (mission.montant_majoration_ferie || 0);
  const totalBrut = mission.total_brut ?? null;
  const brutBase = totalBrut != null ? Math.max(0, totalBrut - totalMajorations) : null;
  const ifm = mission.montant_ifm || 0;
  const icp = mission.montant_icp || 0;
  const totalAvantCharges = mission.net_a_payer ?? (totalBrut != null ? totalBrut + ifm + icp : null);
  const financeAffichee = montantFinanceAfficheMission(mission);
  const missionEstLiberale = financeAffichee?.nature === 'HONORAIRES_LIBERAUX';
  const afficherFinance = totalBrut != null || totalAvantCharges != null || financeAffichee != null;

  return (
    <DialogResponsive open={open} onOpenChange={onOpenChange}>
      <DialogResponsiveContent maxWidth="lg" className="bg-jolene-cloud/95 backdrop-blur-xl border-jolene-rose-200/60">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle className="text-jolene-midnight">
            {mission.intitule}
          </DialogResponsiveTitle>
          <DialogResponsiveDescription>
            <span className="inline-flex items-center gap-2">
              <BadgeY2K
                variant={scoreEleve ? 'premium' : 'info'}
                size="sm"
                icone={<Sparkles className="h-3 w-3" />}
              >
                Match {mission.score}/100
              </BadgeY2K>
              {/* 7c : ⚡ réservé au paiement rapide, urgence en 🔥. */}
              {mission.est_urgente && (
                <BadgeY2K variant="warning" size="sm">🔥 Urgent</BadgeY2K>
              )}
              {missionEstLiberale && mission.paiement_rapide && (
                <BadgeY2K variant="success" size="sm" title="Instruction de versement normalement lancée sous 24 à 72 h après validation">
                  ⚡ Paiement rapide
                </BadgeY2K>
              )}
            </span>
          </DialogResponsiveDescription>
        </DialogResponsiveHeader>

        <DialogResponsiveBody>
          {/* Établissement */}
          <section className="space-y-3">
            <h3 className="text-sm font-semibold text-jolene-bubblegum uppercase tracking-wider">
              Établissement
            </h3>
            <div className="flex items-start gap-3 rounded-2xl bg-jolene-rose-50 p-4">
              <MapPin className="h-5 w-5 text-jolene-rose-700 shrink-0 mt-0.5" aria-hidden="true" />
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-jolene-midnight">{mission.etablissement_nom}</p>
                {mission.etablissement_ville && (
                  <p className="text-sm text-jolene-bubblegum">{mission.etablissement_ville}</p>
                )}
              </div>
              {mission.etablissement_score != null && (
                <span className="inline-flex items-center gap-1 text-sm font-semibold text-jolene-rose-700 shrink-0">
                  <Star className="h-4 w-4 fill-current" aria-hidden="true" />
                  {Math.round(mission.etablissement_score)}/100
                </span>
              )}
            </div>
          </section>

          {/* Conditions */}
          <section className="space-y-3 mt-5">
            <h3 className="text-sm font-semibold text-jolene-bubblegum uppercase tracking-wider">
              Conditions
            </h3>
            <dl className="grid grid-cols-2 gap-3 text-sm">
              <div className="rounded-xl bg-jolene-mauve-50 p-3">
                <dt className="flex items-center gap-1.5 text-xs text-jolene-bubblegum">
                  <Tag className="h-3.5 w-3.5" aria-hidden="true" /> Profession
                </dt>
                <dd className="font-semibold text-jolene-midnight mt-1">
                  {mission.profession_requise || '—'}
                </dd>
              </div>
              <div className="rounded-xl bg-jolene-mauve-50 p-3">
                <dt className="flex items-center gap-1.5 text-xs text-jolene-bubblegum">
                  <Tag className="h-3.5 w-3.5" aria-hidden="true" /> Service
                </dt>
                <dd className="font-semibold text-jolene-midnight mt-1">
                  {mission.service || '—'}
                </dd>
              </div>
              <div className="rounded-xl bg-jolene-cyan-50 p-3">
                <dt className="flex items-center gap-1.5 text-xs text-jolene-bubblegum">
                  <Euro className="h-3.5 w-3.5" aria-hidden="true" /> Tarif horaire
                </dt>
                <dd className="font-semibold text-jolene-midnight mt-1">
                  {mission.taux_horaire_base ? `${mission.taux_horaire_base} €/h` : '—'}
                </dd>
              </div>
              <div className="rounded-xl bg-jolene-cyan-50 p-3">
                <dt className="flex items-center gap-1.5 text-xs text-jolene-bubblegum">
                  <Clock className="h-3.5 w-3.5" aria-hidden="true" /> Durée
                </dt>
                <dd className="font-semibold text-jolene-midnight mt-1">
                  {formatDureeCompacte(mission)}
                </dd>
              </div>
            </dl>
            {afficherFinance && (
              <div className="mt-3 rounded-2xl bg-jolene-cloud border border-jolene-rose-100 p-4 space-y-2">
                <div className="flex items-center justify-between gap-3">
                  <p className="text-xs font-semibold text-jolene-bubblegum uppercase tracking-wider">
                    {financeAffichee?.libelle ?? 'Rémunération indicative'}
                  </p>
                  {financeAffichee && financeAffichee.montant > 0 && (
                    <p className="text-2xl font-extrabold text-jolene-midnight">
                      {financeAffichee.approximatif ? '~' : ''}{formatMontant(financeAffichee.montant)}
                    </p>
                  )}
                </div>
                <dl className="space-y-1.5 text-sm">
                  <div className="flex justify-between gap-3">
                    <dt className="text-jolene-bubblegum">Brut de base</dt>
                    <dd className="font-semibold text-jolene-midnight">{formatMontant(brutBase)}</dd>
                  </div>
                  <div className="flex justify-between gap-3">
                    <dt className="text-jolene-bubblegum">Majorations nuit/dimanche/férié</dt>
                    <dd className="font-semibold text-jolene-midnight">
                      {totalMajorations > 0 ? `+${formatMontant(totalMajorations)}` : formatMontant(0)}
                    </dd>
                  </div>
                  {totalBrut != null && (
                    <div className="flex justify-between gap-3 border-t border-jolene-rose-100 pt-1.5">
                      <dt className="text-jolene-bubblegum">Total brut</dt>
                      <dd className="font-semibold text-jolene-midnight">{formatMontant(totalBrut)}</dd>
                    </div>
                  )}
                  {!missionEstLiberale && (
                    <div className="flex justify-between gap-3">
                      <dt className="text-jolene-bubblegum">IFM + ICP</dt>
                      <dd className="font-semibold text-jolene-midnight">
                        {ifm + icp > 0 ? `+${formatMontant(ifm + icp)}` : formatMontant(0)}
                      </dd>
                    </div>
                  )}
                  {!missionEstLiberale && totalAvantCharges != null && (
                    <div className="flex justify-between gap-3 border-t border-jolene-rose-100 pt-1.5">
                      <dt className="text-jolene-bubblegum">Total avant cotisations</dt>
                      <dd className="font-bold text-jolene-midnight">{formatMontant(totalAvantCharges)}</dd>
                    </div>
                  )}
                </dl>
                {!missionEstLiberale && totalAvantCharges != null && financeAffichee?.nature === 'NET_SALARIE_ESTIME' && (
                  <p className="text-[11px] text-jolene-bubblegum">
                    Le net salarié est une estimation du moteur de paie. Le montant exact figurera sur le bulletin de l'employeur.
                  </p>
                )}
                {missionEstLiberale && (
                  <p className="text-[11px] text-jolene-bubblegum">
                    Honoraires bruts avant les cotisations libérales déclarées séparément par le soignant.
                  </p>
                )}
                {/* 7c : délai de paiement — copy différenciée ⚡ vs standard,
                    uniquement sur le libéral (le salarié est payé par la paie
                    de l'employeur, Jolene ne verse rien). */}
                {missionEstLiberale && mission.paiement_rapide ? (
                  <div>
                    <p className="text-[11px] font-semibold text-success">
                      ⚡ Versement normalement lancé sous 24 à 72 h après validation des présences.
                    </p>
                    <p className="mt-0.5 text-[10px] text-jolene-bubblegum">
                      L'arrivée bancaire peut prendre plus de temps et dépend des contrôles éventuels.
                    </p>
                  </div>
                ) : missionEstLiberale ? (
                  <p className="text-[11px] text-jolene-bubblegum">
                    Payée après règlement de l'établissement (~30 à 60 jours).
                  </p>
                ) : null}
              </div>
            )}
          </section>

          {/* Planning contractuel exact */}
          <section className="space-y-3 mt-5">
            <h3 className="text-sm font-semibold text-jolene-bubblegum uppercase tracking-wider">
              Dates et horaires travaillés
            </h3>
            <div className="rounded-2xl bg-jolene-lavender-50 p-4">
              <PlanningMissionCandidat mission={mission} />
            </div>
          </section>

          {/* Détail score matching */}
          {breakdown && Object.keys(breakdown).length > 0 && (
            <section className="space-y-3 mt-5">
              <h3 className="text-sm font-semibold text-jolene-bubblegum uppercase tracking-wider">
                Pourquoi ce match
              </h3>
              {/* 7d — barèmes alignés sur le scoring v3 (tarif/20 vs médiane
                  marché, distance/20, horaire appris/15, étab/15, urgence/10)
                  + bonus forts affichés quand présents. */}
              <ul className="space-y-1.5 text-sm">
                {breakdown.tarif != null && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">Tarif vs marché local</span>
                    <span className="font-semibold text-jolene-midnight">{breakdown.tarif} / 20</span>
                  </li>
                )}
                {breakdown.distance != null && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">
                      Distance{breakdown.distance_km != null ? ` (${breakdown.distance_km} km)` : ''}
                    </span>
                    <span className="font-semibold text-jolene-midnight">{breakdown.distance} / 20</span>
                  </li>
                )}
                {breakdown.horaire != null && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">Tes horaires préférés</span>
                    <span className="font-semibold text-jolene-midnight">{breakdown.horaire} / 15</span>
                  </li>
                )}
                {breakdown.etablissement != null && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">Qualité établissement</span>
                    <span className="font-semibold text-jolene-midnight">{breakdown.etablissement} / 15</span>
                  </li>
                )}
                {breakdown.urgence != null && breakdown.urgence > 0 && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">Urgence (bonus)</span>
                    <span className="font-semibold text-jolene-midnight">+{breakdown.urgence} / 10</span>
                  </li>
                )}
                {breakdown.connaissance_etab != null && breakdown.connaissance_etab > 0 && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">Tu connais cet établissement</span>
                    <span className="font-semibold text-jolene-midnight">+{breakdown.connaissance_etab}</span>
                  </li>
                )}
                {breakdown.paiement_rapide != null && breakdown.paiement_rapide > 0 && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">⚡ Paiement rapide</span>
                    <span className="font-semibold text-jolene-midnight">+{breakdown.paiement_rapide}</span>
                  </li>
                )}
              </ul>
            </section>
          )}
        </DialogResponsiveBody>

        <DialogResponsiveFooter>
          <BoutonY2K variant="ghost" onClick={onSuivant}>
            Suivant
          </BoutonY2K>
          <BoutonY2K variant="primary" onClick={onPostuler} disabled={!planning.exact}>
            Vérifier et postuler
          </BoutonY2K>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}

export default ModalDetailMissionSwipe;
