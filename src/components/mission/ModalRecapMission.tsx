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

export type NatureTvaPrestation =
  | 'SOIN_THERAPEUTIQUE_EXONERE'
  | 'PRESTATION_TAXABLE';

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
  contratPreference: 'TOUS' | 'SALARIE' | 'LIBERAL';
  natureTvaPrestation: NatureTvaPrestation | null;
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
    contratPreference,
    natureTvaPrestation,
    modeAttribution,
    estUrgente,
    niveauUrgence,
    tauxCommission,
    toleranceGpsMetres,
    qrAutoGenere,
    liberalRestreint,
    modeExerciceMission,
  } = data;

  const remunerationEstimee = tauxHoraire * dureeHeures;
  const commissionMontantHt = remunerationEstimee * (tauxCommission / 100);
  const commissionTva = commissionMontantHt * 0.20;
  const totalAvecTvaJolene = remunerationEstimee + commissionMontantHt + commissionTva;
  const estLiberalUniquement = contratPreference === 'LIBERAL';
  const estSalarieUniquement = contratPreference === 'SALARIE';
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
        : 'Libéral uniquement (mission d’honoraires)';

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
  if (!estLiberalUniquement) {
    if (heuresNuit > 0) majorationsCcn.push(`Nuit (21h-6h) — ~${heuresNuit.toFixed(0)}h estimées`);
    // Dimanche et fériés détectés au pointage par le moteur de paie.
    majorationsCcn.push('Dimanche et jours fériés (calculés au pointage)');
    majorationsCcn.push('IFM 10% + ICP 10% (CDD salarié)');
  }

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
              {!estSalarieUniquement && natureTvaPrestation && (
                <div className="flex justify-between gap-3">
                  <span className="text-muted-foreground shrink-0">Nature TVA prévue</span>
                  <span className="font-medium text-foreground text-right">
                    {natureTvaPrestation === 'SOIN_THERAPEUTIQUE_EXONERE'
                      ? 'Soin à finalité thérapeutique — exonération à confirmer'
                      : 'Prestation taxable — statut TVA du soignant applicable'}
                  </span>
                </div>
              )}
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
              <div className="flex justify-between">
                <span className="text-muted-foreground">
                  {estLiberalUniquement
                    ? 'Honoraires estimés HT'
                    : estSalarieUniquement
                      ? 'Base brute estimée'
                      : 'Base proposée — brut salarié ou honoraires HT'} ({tauxHoraire.toFixed(2)} €/h × {dureeHeures.toFixed(1)}h)
                </span>
                <span className="font-medium text-foreground">{remunerationEstimee.toFixed(2)} €</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">
                  Frais Jolene ({tauxCommission}% HT)
                </span>
                <span className="font-medium text-foreground">
                  +{commissionMontantHt.toFixed(2)} €
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">TVA 20 % sur les frais Jolene</span>
                <span className="font-medium text-foreground">+{commissionTva.toFixed(2)} €</span>
              </div>
              <div className="flex justify-between border-t border-border pt-2">
                <span className="font-semibold text-foreground">
                  Total estimé{estLiberalUniquement
                    ? ' hors éventuelle TVA sur les honoraires'
                    : estSalarieUniquement
                      ? ' avant charges employeur'
                      : ' selon le régime finalement retenu'}
                </span>
                <span className="font-bold text-primary text-base">{totalAvecTvaJolene.toFixed(2)} €</span>
              </div>
              {estLiberalUniquement ? (
                <div className="space-y-1 pt-1 text-[10px] text-muted-foreground">
                  <p>
                    Un seul paiement pourra régler deux factures distinctes : 100 % des honoraires au soignant et les frais Jolene à l’établissement.
                  </p>
                  <p>
                    La nature de la prestation sera confirmée par le soignant assigné. Pour une prestation taxable, son statut TVA déterminera si une TVA s’ajoute aux honoraires. Les heures et ajustements validés dans Jolene font foi ; un litige produit une correction traçable sans écraser la facture initiale.
                  </p>
                </div>
              ) : (
                <p className="text-[10px] text-muted-foreground italic pt-1">
                  Estimation indicative. Le bulletin employeur fera foi et ajoutera les charges,
                  majorations CCN, IFM 10 % et ICP 10 % applicables au CDD.
                </p>
              )}
              {!estLiberalUniquement && !estSalarieUniquement && (
                <p className="text-[10px] text-muted-foreground">
                  Le total final dépendra du statut du soignant retenu : paie employeur en salarié ou facture d’honoraires en libéral.
                </p>
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
              {majorationsCcn.length > 0 && (
                <div className="pt-2 border-t border-border">
                  <p className="text-xs text-muted-foreground mb-1.5">Majorations CCN potentielles</p>
                  <ul className="text-xs text-foreground space-y-0.5 list-disc list-inside">
                    {majorationsCcn.map((m, i) => (
                      <li key={i}>{m}</li>
                    ))}
                  </ul>
                </div>
              )}
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
