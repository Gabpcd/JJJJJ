/**
 * ModalDetailMissionSwipe — Sprint 13-B PR 5
 *
 * Modal détail mission complet déclenché par tap sur CardMissionSwipe.
 * Glassmorphism Y2K. Bouton "Postuler maintenant" déclenche LIKE direct
 * + ferme la modal.
 */
import { useState } from 'react';
import { Calendar, Clock, Euro, MapPin, Sparkles, Star, Tag } from 'lucide-react';
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
import type { MissionSwipePayload } from './CardMissionSwipe';

interface Props {
  mission: MissionSwipePayload | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onPostuler: () => void;
  onSuivant: () => void;
}

function formatDateFull(iso: string | null): string {
  if (!iso) return '—';
  try {
    return new Date(iso).toLocaleDateString('fr-FR', {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      year: 'numeric',
    });
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

export function ModalDetailMissionSwipe({ mission, open, onOpenChange, onPostuler, onSuivant }: Props) {
  const [posting, setPosting] = useState(false);
  if (!mission) return null;

  const handlePostuler = () => {
    setPosting(true);
    onPostuler();
    // La modal se ferme via onOpenChange depuis le parent après succès.
    setTimeout(() => setPosting(false), 800);
  };

  const scoreEleve = mission.score >= 80;
  const heureDebut = formatHeure(mission.debut_le);
  const heureFin = formatHeure(mission.fin_le);
  const breakdown = mission.breakdown as Record<string, number | undefined> | undefined;

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
              {mission.est_urgente && (
                <BadgeY2K variant="warning" size="sm">⚡ Urgent</BadgeY2K>
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
                  {mission.duree_heures ? `${mission.duree_heures} h` : '—'}
                </dd>
              </div>
            </dl>
            {mission.net_estime != null && mission.net_estime > 0 && (
              <div className="mt-3 rounded-2xl bg-gradient-hero p-4 text-center">
                <p className="text-xs font-semibold text-white/80 uppercase tracking-wider mb-1">Gain net estimé*</p>
                <p className="text-2xl font-extrabold text-white">~{Math.round(mission.net_estime)} €</p>
                <p className="text-[10px] text-white/60 mt-1">*estimation, le net réel dépend des cotisations applicables</p>
              </div>
            )}
          </section>

          {/* Dates */}
          <section className="space-y-3 mt-5">
            <h3 className="text-sm font-semibold text-jolene-bubblegum uppercase tracking-wider">
              Dates
            </h3>
            <div className="rounded-2xl bg-jolene-lavender-50 p-4 space-y-2">
              <div className="flex items-center gap-3">
                <Calendar className="h-5 w-5 text-jolene-mauve-700 shrink-0" aria-hidden="true" />
                <div className="flex-1">
                  <p className="font-semibold text-jolene-midnight capitalize">
                    {formatDateFull(mission.debut_le)}
                  </p>
                  {heureDebut && (
                    <p className="text-sm text-jolene-bubblegum">
                      {heureDebut}
                      {heureFin && ` → ${heureFin}`}
                    </p>
                  )}
                </div>
              </div>
            </div>
          </section>

          {/* Détail score matching */}
          {breakdown && Object.keys(breakdown).length > 0 && (
            <section className="space-y-3 mt-5">
              <h3 className="text-sm font-semibold text-jolene-bubblegum uppercase tracking-wider">
                Pourquoi ce match
              </h3>
              <ul className="space-y-1.5 text-sm">
                {breakdown.tarif != null && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">Tarif</span>
                    <span className="font-semibold text-jolene-midnight">{breakdown.tarif} / 25</span>
                  </li>
                )}
                {breakdown.distance != null && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">
                      Distance{breakdown.distance_km != null ? ` (${breakdown.distance_km} km)` : ''}
                    </span>
                    <span className="font-semibold text-jolene-midnight">{breakdown.distance} / 25</span>
                  </li>
                )}
                {breakdown.etablissement != null && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">Qualité établissement</span>
                    <span className="font-semibold text-jolene-midnight">{breakdown.etablissement} / 20</span>
                  </li>
                )}
                {breakdown.urgence != null && breakdown.urgence > 0 && (
                  <li className="flex justify-between rounded-xl bg-jolene-cloud border border-jolene-rose-100 px-3 py-2">
                    <span className="text-jolene-bubblegum">Urgence (bonus)</span>
                    <span className="font-semibold text-jolene-midnight">+{breakdown.urgence} / 15</span>
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
          <BoutonY2K variant="primary" onClick={handlePostuler} loading={posting}>
            Postuler maintenant
          </BoutonY2K>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}

export default ModalDetailMissionSwipe;
