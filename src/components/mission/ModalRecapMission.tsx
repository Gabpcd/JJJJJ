import React from 'react';
import { Loader2 } from 'lucide-react';
import {
  liensSourcesModeExercice,
  type ModeExerciceMission,
} from '@/lib/modeExerciceMission';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveDescription,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import { formatParis } from '@/lib/date-heure-paris';

export interface RecapMissionData {
  intitule: string;
  description?: string | null;
  profession: string;
  service?: string | null;
  debutLe: string;
  finLe: string;
  creneaux?: Array<{
    id?: string;
    clientId: string;
    debut: string;
    fin: string;
    dureeHeures: number;
  }>;
  dureeHeures: number;
  heuresNuit: number;
  tauxHoraire: number;
  modeRemuneration?: 'TAUX_HORAIRE' | 'RETROCESSION';
  retrocessionPct?: number | null;
  contratPreference: 'TOUS' | 'SALARIE' | 'LIBERAL';
  modeAttribution: 'PREMIER_ARRIVE' | 'CANDIDATURE';
  estUrgente: boolean;
  niveauUrgence: number;
  tauxCommission: number; // pourcentage Jolene (ex: 12 ou 15)
  toleranceGpsMetres: number | null;
  qrAutoGenere: boolean;
  etablissementType: string | null;
  liberalRestreint: boolean;
  modeExerciceMission: ModeExerciceMission | null;
}

interface ModalRecapMissionProps {
  ouvert: boolean;
  data: RecapMissionData;
  onModifier: () => void;
  onConfirmer: () => void;
  loading?: boolean;
  labelConfirmer?: 'Publier' | 'Enregistrer';
}

/**
 * Sprint 7 PR 1 — P1-4
 * Modal récapitulatif affiché avant publication finale d'une mission par un établissement.
 * 4 sections : infos mission, coût estimé, restrictions Mediflash, config pointage.
 */
export function ModalRecapMission({
  ouvert,
  data,
  onModifier,
  onConfirmer,
  loading = false,
  labelConfirmer = 'Publier',
}: ModalRecapMissionProps) {
  const {
    intitule,
    description,
    profession,
    service,
    debutLe,
    finLe,
    creneaux = [],
    dureeHeures,
    heuresNuit,
    tauxHoraire,
    modeRemuneration = 'TAUX_HORAIRE',
    retrocessionPct = null,
    contratPreference,
    modeAttribution,
    estUrgente,
    niveauUrgence,
    tauxCommission,
    toleranceGpsMetres,
    qrAutoGenere,
    liberalRestreint,
    modeExerciceMission,
  } = data;

  const estRetrocession = modeRemuneration === 'RETROCESSION';
  const brutSoignant = tauxHoraire * dureeHeures;
  const commissionMontant = brutSoignant * (tauxCommission / 100);
  const totalHT = brutSoignant + commissionMontant;
  const sourcesModeExerciceMission = modeExerciceMission
    ? liensSourcesModeExercice(modeExerciceMission)
    : [];

  const formaterDateHeure = (iso: string) => {
    if (!iso) return '—';
    try {
      return formatParis(iso, "EEE dd MMM 'à' HH:mm");
    } catch {
      return iso;
    }
  };

  const labelContrat =
    contratPreference === 'TOUS'
      ? 'Tous profils (salarié + libéral)'
      : contratPreference === 'SALARIE'
        ? 'Salarié uniquement (CDD)'
        : 'Libéral uniquement (remplacement)';

  const labelMode =
    modeAttribution === 'PREMIER_ARRIVE' ? '⚡ Premier arrivé' : '👤 Sur candidature';

  const labelUrgence = estUrgente
    ? niveauUrgence === 3
      ? '🚨 Critique — sous 6h'
      : niveauUrgence === 2
        ? '🔥 Élevé — sous 24h'
        : '⚡ Modéré — sous 48h'
    : null;

  const majorationsCcn: string[] = [];
  if (heuresNuit > 0) majorationsCcn.push(`Nuit (21h-6h) — ~${heuresNuit.toFixed(0)}h estimées`);
  // Dimanche et fériés détectés au pointage par le moteur de paie
  majorationsCcn.push('Dimanche et jours fériés (calculés au pointage)');
  majorationsCcn.push('IFM 10% + ICP 10% (CDD salarié)');

  return (
    <DialogResponsive open={ouvert} onOpenChange={(o) => { if (!o && !loading) onModifier(); }}>
      <DialogResponsiveContent maxWidth="2xl" aria-labelledby="modal-recap-titre">
        <DialogResponsiveHeader>
          <DialogResponsiveTitle id="modal-recap-titre">
            📋 Récapitulatif avant {labelConfirmer === 'Publier' ? 'publication' : 'enregistrement'}
          </DialogResponsiveTitle>
          <DialogResponsiveDescription>
            Vérifiez les informations et chaque créneau avant de {labelConfirmer === 'Publier' ? 'publier' : 'modifier'} la mission.
          </DialogResponsiveDescription>
        </DialogResponsiveHeader>
        <DialogResponsiveBody className="space-y-5">
          {/* Section 1 — Infos mission */}
          <section className="space-y-2">
            <h3 className="text-sm font-bold text-foreground uppercase tracking-wide">
              1. Informations mission
            </h3>
            <div className="bg-muted/30 rounded-xl p-4 space-y-2 text-sm">
              <div className="flex justify-between gap-3">
                <span className="text-muted-foreground shrink-0">Intitulé</span>
                <span className="font-medium text-right text-foreground">{intitule}</span>
              </div>
              <div className="flex justify-between gap-3">
                <span className="text-muted-foreground shrink-0">Profession</span>
                <span className="font-medium text-foreground">{profession}</span>
              </div>
              {service && (
                <div className="flex justify-between gap-3">
                  <span className="text-muted-foreground shrink-0">Service</span>
                  <span className="font-medium text-foreground">{service}</span>
                </div>
              )}
              <div className="flex justify-between gap-3">
                <span className="text-muted-foreground shrink-0">Début</span>
                <span className="font-medium text-foreground">{formaterDateHeure(debutLe)}</span>
              </div>
              <div className="flex justify-between gap-3">
                <span className="text-muted-foreground shrink-0">Fin</span>
                <span className="font-medium text-foreground">{formaterDateHeure(finLe)}</span>
              </div>
              <div className="flex justify-between gap-3 pt-1 border-t border-border">
                <span className="text-muted-foreground shrink-0">Durée estimée</span>
                <span className="font-bold text-primary">
                  {Math.floor(dureeHeures)}h
                  {String(Math.round((dureeHeures % 1) * 60)).padStart(2, '0')}
                </span>
              </div>
              {creneaux.length > 0 && (
                <div className="border-t border-border pt-2">
                  <p className="mb-2 text-xs font-semibold text-foreground">
                    Planning exact · {creneaux.length} créneau{creneaux.length > 1 ? 'x' : ''}
                  </p>
                  <div className="max-h-48 space-y-1 overflow-y-auto">
                    {creneaux.map((creneau) => (
                      <p key={creneau.clientId} className="text-xs text-foreground">
                        <span className="capitalize">{formatParis(creneau.debut, 'EEEE d MMMM yyyy')}</span>
                        {' · '}{formatParis(creneau.debut, 'HH:mm')} →{' '}
                        <span className="capitalize">{formatParis(creneau.fin, 'EEEE d MMMM yyyy')}</span>
                        {' · '}{formatParis(creneau.fin, 'HH:mm')}
                      </p>
                    ))}
                  </div>
                </div>
              )}
              <div className="flex justify-between gap-3">
                <span className="text-muted-foreground shrink-0">Type de profil</span>
                <span className="font-medium text-foreground text-right">{labelContrat}</span>
              </div>
              <div className="flex justify-between gap-3">
                <span className="text-muted-foreground shrink-0">Mode de sélection</span>
                <span className="font-medium text-foreground">{labelMode}</span>
              </div>
              {labelUrgence && (
                <div className="flex justify-between gap-3">
                  <span className="text-muted-foreground shrink-0">Urgence</span>
                  <span className="font-medium text-foreground">{labelUrgence}</span>
                </div>
              )}
              {description && (
                <div className="pt-2 border-t border-border">
                  <p className="text-xs text-muted-foreground mb-1">Description</p>
                  <p className="text-sm text-foreground whitespace-pre-wrap">{description}</p>
                </div>
              )}
            </div>
          </section>

          {/* Section 2 — Coût estimé */}
          <section className="space-y-2">
            <h3 className="text-sm font-bold text-foreground uppercase tracking-wide">
              2. Coût estimé
            </h3>
            <div className="bg-gradient-to-r from-primary/5 to-info/5 border border-primary/20 rounded-xl p-4 space-y-2 text-sm">
              {estRetrocession ? (
                <>
                  <div className="flex justify-between gap-3">
                    <span className="text-muted-foreground">Rétrocession au remplaçant</span>
                    <span className="font-bold text-primary">{retrocessionPct ?? '—'} % des honoraires</span>
                  </div>
                  <p className="border-t border-border pt-2 text-[10px] italic text-muted-foreground">
                    Le montant sera calculé sur les honoraires réellement encaissés et confirmés. Aucun taux horaire ne détermine la rémunération contractuelle.
                  </p>
                </>
              ) : (
                <>
              <div className="flex justify-between">
                <span className="text-muted-foreground">
                  Brut soignant ({tauxHoraire.toFixed(2)} €/h × {dureeHeures.toFixed(1)}h)
                </span>
                <span className="font-medium text-foreground">{brutSoignant.toFixed(2)} €</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">
                  Commission Jolene ({tauxCommission}% HT)
                </span>
                <span className="font-medium text-foreground">
                  +{commissionMontant.toFixed(2)} €
                </span>
              </div>
              <div className="flex justify-between border-t border-border pt-2">
                <span className="font-semibold text-foreground">Total estimé HT</span>
                <span className="font-bold text-primary text-base">{totalHT.toFixed(2)} €</span>
              </div>
              <p className="text-[10px] text-muted-foreground italic pt-1">
                Estimation indicative. Le montant final inclura majorations CCN (nuit, dimanche,
                fériés), IFM 10% et ICP 10% pour les CDD.
              </p>
                </>
              )}
            </div>
          </section>

          {/* Section 3 — Mode d'exercice résolu par la table serveur */}
          {liberalRestreint && modeExerciceMission && (
            <section className="space-y-2">
              <h3 className="text-sm font-bold text-foreground uppercase tracking-wide">
                3. Mode d'exercice
              </h3>
              <div className="bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 rounded-xl p-4 text-sm">
                <p className="font-semibold text-amber-900 dark:text-amber-200">
                  {modeExerciceMission.niveau === 'BLOQUE'
                    ? 'Mode libéral non disponible'
                    : 'Mission proposée en salarié'}
                </p>
                <p className="text-xs text-amber-800 dark:text-amber-300 mt-1">
                  {modeExerciceMission.source_libelle}
                </p>
                {sourcesModeExerciceMission.length > 0 && (
                  <div className="mt-2 flex flex-col items-start gap-1">
                    {sourcesModeExerciceMission.map((source) => (
                      <a
                        key={source.href}
                        href={source.href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-xs text-amber-900 underline hover:no-underline dark:text-amber-200"
                      >
                        {source.libelle}
                      </a>
                    ))}
                  </div>
                )}
              </div>
            </section>
          )}

          {/* Section 4 — Config pointage */}
          <section className="space-y-2">
            <h3 className="text-sm font-bold text-foreground uppercase tracking-wide">
              {liberalRestreint ? '4' : '3'}. Configuration pointage
            </h3>
            <div className="bg-muted/30 rounded-xl p-4 space-y-2 text-sm">
              <div className="flex justify-between gap-3">
                <span className="text-muted-foreground shrink-0">Tolérance GPS</span>
                <span className="font-medium text-foreground">
                  {toleranceGpsMetres != null ? `${toleranceGpsMetres} m` : '100 m (défaut)'}
                </span>
              </div>
              <div className="flex justify-between gap-3">
                <span className="text-muted-foreground shrink-0">QR de pointage</span>
                <span className="font-medium text-foreground">
                  {qrAutoGenere ? '✅ Généré à la signature du contrat' : '⏳ Manuel'}
                </span>
              </div>
              <div className="pt-2 border-t border-border">
                <p className="text-xs text-muted-foreground mb-1.5">Majorations CCN potentielles</p>
                <ul className="text-xs text-foreground space-y-0.5 list-disc list-inside">
                  {majorationsCcn.map((m, i) => (
                    <li key={i}>{m}</li>
                  ))}
                </ul>
              </div>
            </div>
          </section>
        </DialogResponsiveBody>
        <DialogResponsiveFooter>
          <button
            type="button"
            onClick={onModifier}
            disabled={loading}
            className="btn-secondary flex-1 min-h-[44px] disabled:opacity-50"
          >
            ← Modifier
          </button>
          <button
            type="button"
            onClick={onConfirmer}
            disabled={loading}
            className="btn-primary flex-1 min-h-[44px] flex items-center justify-center gap-2 disabled:opacity-50"
          >
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            {labelConfirmer === 'Publier' ? '📤 Publier' : '💾 Enregistrer'}
          </button>
        </DialogResponsiveFooter>
      </DialogResponsiveContent>
    </DialogResponsive>
  );
}
