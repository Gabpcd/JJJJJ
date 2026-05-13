import React from 'react';
import { X, Loader2 } from 'lucide-react';

export interface RecapMissionData {
  intitule: string;
  description?: string | null;
  profession: string;
  service?: string | null;
  debutLe: string;
  finLe: string;
  dureeHeures: number;
  heuresNuit: number;
  tauxHoraire: number;
  contratPreference: 'TOUS' | 'SALARIE' | 'LIBERAL';
  modeAttribution: 'PREMIER_ARRIVE' | 'CANDIDATURE';
  estUrgente: boolean;
  niveauUrgence: number;
  tauxCommission: number; // pourcentage Jolene (ex: 12 ou 15)
  toleranceGpsMetres: number | null;
  qrAutoGenere: boolean;
  etablissementType: string | null;
  liberalRestreint: boolean;
}

interface ModalRecapMissionProps {
  ouvert: boolean;
  data: RecapMissionData;
  onModifier: () => void;
  onConfirmer: () => void;
  loading?: boolean;
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
}: ModalRecapMissionProps) {
  if (!ouvert) return null;

  const {
    intitule,
    description,
    profession,
    service,
    debutLe,
    finLe,
    dureeHeures,
    heuresNuit,
    tauxHoraire,
    contratPreference,
    modeAttribution,
    estUrgente,
    niveauUrgence,
    tauxCommission,
    toleranceGpsMetres,
    qrAutoGenere,
    etablissementType,
    liberalRestreint,
  } = data;

  const brutSoignant = tauxHoraire * dureeHeures;
  const commissionMontant = brutSoignant * (tauxCommission / 100);
  const totalHT = brutSoignant + commissionMontant;

  const formaterDateHeure = (iso: string) => {
    if (!iso) return '—';
    try {
      const d = new Date(iso);
      return d.toLocaleString('fr-FR', {
        weekday: 'short',
        day: '2-digit',
        month: 'short',
        hour: '2-digit',
        minute: '2-digit',
      });
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
    <div
      className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-end md:items-center justify-center p-0 md:p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-recap-titre"
    >
      <div className="bg-card w-full md:max-w-2xl md:rounded-2xl rounded-t-2xl shadow-xl max-h-[92vh] overflow-y-auto">
        {/* Header */}
        <div className="sticky top-0 bg-card border-b border-border px-5 py-4 flex items-center justify-between z-10">
          <div>
            <h2 id="modal-recap-titre" className="text-lg font-bold text-foreground">
              📋 Récapitulatif avant publication
            </h2>
            <p className="text-xs text-muted-foreground mt-0.5">
              Vérifiez les informations avant de publier la mission.
            </p>
          </div>
          <button
            type="button"
            onClick={onModifier}
            aria-label="Fermer"
            className="p-2 rounded-lg hover:bg-muted transition-colors"
          >
            <X className="h-4 w-4 text-muted-foreground" />
          </button>
        </div>

        <div className="p-5 space-y-5">
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
              <div className="flex justify-between">
                <span className="text-muted-foreground">
                  Brut soignant ({tauxHoraire.toFixed(2)} €/h × {dureeHeures.toFixed(1)}h)
                </span>
                <span className="font-medium text-foreground">{brutSoignant.toFixed(2)} €</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">
                  Commission Jolene ({tauxCommission}%)
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
            </div>
          </section>

          {/* Section 3 — Restrictions */}
          {liberalRestreint && (
            <section className="space-y-2">
              <h3 className="text-sm font-bold text-foreground uppercase tracking-wide">
                3. Restrictions réglementaires
              </h3>
              <div className="bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 rounded-xl p-4 text-sm">
                <p className="font-semibold text-amber-900 dark:text-amber-200">
                  ⚠️ Mode libéral non autorisé
                </p>
                <p className="text-xs text-amber-800 dark:text-amber-300 mt-1">
                  Pour <strong>{profession}</strong> en <strong>{etablissementType}</strong>, la
                  réglementation interdit le mode libéral (cas de salariat déguisé — Conseil
                  d'État 11/02/2025 arrêt Mediflash). La mission sera publiée uniquement en CDD
                  salarié.
                </p>
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
        </div>

        {/* Footer actions */}
        <div className="sticky bottom-0 bg-card border-t border-border px-5 py-4 flex flex-col-reverse sm:flex-row gap-2 sm:gap-3">
          <button
            type="button"
            onClick={onModifier}
            disabled={loading}
            className="btn-secondary flex-1 disabled:opacity-50"
          >
            ← Modifier
          </button>
          <button
            type="button"
            onClick={onConfirmer}
            disabled={loading}
            className="btn-primary flex-1 flex items-center justify-center gap-2 disabled:opacity-50"
          >
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            📤 Publier
          </button>
        </div>
      </div>
    </div>
  );
}
