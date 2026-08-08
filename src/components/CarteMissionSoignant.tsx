import React from 'react';
import { formatDistanceToNow } from 'date-fns';
import { fr } from 'date-fns/locale';
import { BadgeDistance } from '@/components/BadgeDistance';
import { BadgeStatut } from '@/components/BadgeStatut';
import { BoutonSauvegarderMission } from '@/components/BoutonSauvegarderMission';
import { getLabelProfession, getLabelTypeEtablissement, extraireContratPreference, getContratBadge, getTypeContratRechercheBadge } from '@/lib/constantes';
import { getMissionMatchInfo } from '@/lib/profession-hierarchy';
import { montantFinanceAfficheMission } from '@/lib/missionFinanceDisplay';
import { PlanningMissionCandidat } from '@/components/planning/PlanningMissionCandidat';

interface CarteMissionSoignantProps {
  mission: any;
  soignant: any;
  onClick: () => void;
}

function getBadgeUrgence(niveau: number) {
  if (niveau >= 3) return { icone: '🚨', label: 'URGENT Critique', classes: 'bg-destructive text-destructive-foreground' };
  if (niveau >= 2) return { icone: '🔥', label: 'URGENT', classes: 'bg-destructive text-destructive-foreground' };
  return { icone: '⚡', label: 'Urgent', classes: 'bg-destructive/80 text-destructive-foreground' };
}

function getTempsEcoule(cree_le: string) {
  const diff = Date.now() - new Date(cree_le).getTime();
  const heures = diff / (1000 * 60 * 60);
  let couleur = 'text-success';
  if (heures > 24) couleur = 'text-destructive';
  else if (heures > 1) couleur = 'text-warning';
  return { texte: formatDistanceToNow(new Date(cree_le), { addSuffix: true, locale: fr }), couleur };
}

function fmt(v: number | null): string {
  if (v == null || v === 0) return '';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export const CarteMissionSoignant = React.memo(function CarteMissionSoignant({ mission, soignant, onClick }: CarteMissionSoignantProps) {
  const m = mission;
  const financeAffichee = montantFinanceAfficheMission(m);
  const temps = getTempsEcoule(m.cree_le);
  const profilComplet = soignant?.tous_documents_valides;
  const contratBadge = m.type_contrat_recherche
    ? getTypeContratRechercheBadge(m.type_contrat_recherche)
    : getContratBadge(extraireContratPreference(m.description));
  const tauxMin = soignant?.taux_horaire_minimum;
  const sousMinimum = tauxMin && m.taux_horaire_base && m.taux_horaire_base < tauxMin;
  const matchInfo = getMissionMatchInfo(
    soignant?.profession,
    soignant?.specialite_medicale,
    m.profession_requise,
    m.specialite_medicale_requise,
    m.accepte_non_specialises,
  );

  const couleurTheme = m.etablissements?.couleur_theme;

  return (
    <div onClick={onClick} className={`card-base hover:shadow-md transition-all cursor-pointer active:scale-[0.99] overflow-hidden ${m.est_urgente ? 'ring-2 ring-destructive/50' : ''} ${sousMinimum ? 'opacity-50 grayscale-[30%]' : ''}`}>
      {sousMinimum && (
        <div className="mb-2">
          <span className="badge-base bg-muted text-muted-foreground text-[10px]">💸 Sous ton minimum ({tauxMin} €/h)</span>
        </div>
      )}
      {m.est_urgente && (
        <div className="h-1.5 -mt-4 md:-mt-6 -mx-4 md:-mx-6 mb-3 bg-destructive animate-pulse" />
      )}
      {couleurTheme && !m.est_urgente && <div className="h-1 -mt-4 md:-mt-6 -mx-4 md:-mx-6 mb-3" style={{ backgroundColor: couleurTheme }} />}
      <div className="flex items-start justify-between mb-2">
        <div className="flex items-center gap-2 flex-wrap">
          {m.est_urgente && (() => {
            const badge = getBadgeUrgence(m.niveau_urgence || 1);
            const debutDate = new Date(m.debut_le);
            const heuresAvant = Math.max(0, Math.round((debutDate.getTime() - Date.now()) / 3600000));
            return (
              <span className={`badge-base text-[10px] ${badge.classes} animate-pulse`}>
                {badge.icone} URGENT — Début dans {heuresAvant}h
              </span>
            );
          })()}
          {(m as any).boostee_le && (
            <span className="badge-base text-[10px] bg-primary/10 text-primary">🚀 Mise en avant</span>
          )}
        </div>
        <span className={`text-[10px] ${temps.couleur}`}>{temps.texte}</span>
      </div>

      <div className="flex items-start justify-between gap-2 mb-0.5">
        <h3 className="font-semibold text-sm text-foreground">{m.intitule}</h3>
        {/* Étoile = sauvegarder la MISSION (même sémantique que le ⭐ du swipe, D1). */}
        <BoutonSauvegarderMission missionId={m.id} />
      </div>
      {m.service && <p className="text-[10px] text-muted-foreground mb-1">Service : {m.service}</p>}
      <div className="flex items-center gap-2 mb-1">
        {m.etablissements?.logo_url && (
          <img src={m.etablissements.logo_url} alt="" className="h-5 w-5 rounded object-cover shrink-0" />
        )}
        <p className="text-xs text-muted-foreground">
          🏥 {m.etablissements?.nom || 'Établissement'}
          {m.etablissements?.adresse_ville && ` · ${m.etablissements.adresse_ville}`}
          {m.etablissements?.adresse_departement && ` (${m.etablissements.adresse_departement})`}
        </p>
      </div>
      <BadgeDistance distanceKm={m.distance_km} />
      <span className={`badge-base text-[10px] ${contratBadge.classes}`}>{contratBadge.label}</span>
      {/* 7c : ⚡ Paiement rapide — mission LIBERAL + étab éligible (flag serveur
          via fn_etablissements_safe ; éteint tant que l'escrow n'est pas livré). */}
      {m.type_contrat_recherche === 'LIBERAL' && m.etablissements?.paiement_rapide && (
        <span
          className="badge-base text-[10px] bg-success/10 text-success ml-1"
          title="Instruction de versement normalement lancée sous 24 à 72 h après validation"
        >
          ⚡ Paiement rapide
        </span>
      )}
      {/* §2.2 prévisibilité salariée : la date de paie est celle de l'employeur. */}
      {m.type_contrat_recherche === 'SALARIE' && m.etablissements?.jour_paie_habituel != null && (
        <p className="text-[10px] text-muted-foreground mt-1">
          💶 Salaire versé vers le {m.etablissements.jour_paie_habituel} du mois par l'établissement
        </p>
      )}

      <PlanningMissionCandidat mission={m} compact limite={3} className="mt-2" />

      <div className="mt-2 flex items-center justify-between">
        {(m as any).mode_remuneration === 'RETROCESSION' ? (
          <span className="text-primary font-bold text-sm">🤝 Rétrocession {(m as any).retrocession_pct ?? '—'}% des honoraires</span>
        ) : (() => {
          const tauxBase = Number(m.taux_horaire_base ?? 0);
          const majorationsServeurBrutes: Array<[string, number]> = [
            ['nuit', Number(m.montant_majoration_nuit ?? 0)],
            ['dimanche', Number(m.montant_majoration_dimanche ?? 0)],
            ['jour férié', Number(m.montant_majoration_ferie ?? 0)],
          ];
          const majorationsServeur = majorationsServeurBrutes
            .filter(([, montant]) => montant > 0);
          const tooltip = majorationsServeur.length > 0
            ? `Majorations calculées sur les créneaux exacts :\n${majorationsServeur
                .map(([libelle, montant]) => `${libelle} : ${fmt(montant)}`)
                .join('\n')}`
            : undefined;
          return (
            <span
              className="text-primary font-bold text-sm inline-flex items-center gap-1"
              title={tooltip}
              aria-label={tooltip ? `Taux horaire et majorations : ${tooltip}` : undefined}
            >
              💰 {tauxBase.toFixed(2)} €/h
              {majorationsServeur.length > 0 && (
                <span className="text-[10px] font-semibold text-warning bg-warning/10 px-1.5 py-0.5 rounded-full" aria-hidden="true">
                  majorations calculées
                </span>
              )}
            </span>
          );
        })()}
        {(m as any).mode_remuneration === 'RETROCESSION' ? (
          <span className="text-xs text-muted-foreground">Remplacement de cabinet</span>
        ) : financeAffichee && financeAffichee.montant > 0 ? (
          <span className="text-xs text-muted-foreground">
            {financeAffichee.libelle} : {financeAffichee.approximatif ? '~' : ''}{fmt(financeAffichee.montant)}
          </span>
        ) : (
          <span className="text-xs text-muted-foreground/50">Calculé après assignation</span>
        )}
      </div>
      {/* §7.1 Lot 7a — côté soignant, le plafond Rist est de la CONFORMITÉ, pas un
          problème : le taux affiché est le taux réellement payé, conforme au décret. */}
      {m.rist_plafond_applique && (
        <p className="text-[10px] text-success font-medium mt-1">✓ Taux conforme Loi Rist</p>
      )}

      <div className="mt-2 flex flex-wrap gap-1.5">
        {matchInfo && (
          <span className={`badge-base text-[10px] ${matchInfo.badgeClasses}`} title={matchInfo.tooltip}>
            {matchInfo.badgeLabel}
          </span>
        )}
        {profilComplet ? (
          <span className="badge-base bg-success/10 text-success text-[10px]">✅ Dossier complet</span>
        ) : soignant && !soignant.tous_documents_valides ? (
          <span className="badge-base bg-warning/10 text-warning text-[10px]">📄 Pièces vérifiées selon le contrat</span>
        ) : (
          <span className="badge-base bg-warning/10 text-warning text-[10px]">⚠️ Profil incomplet</span>
        )}
      </div>

      <div className="mt-3 text-right">
        <span className="text-xs text-primary font-medium">Voir le détail et postuler →</span>
      </div>
    </div>
  );
});
