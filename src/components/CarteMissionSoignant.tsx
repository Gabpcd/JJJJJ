import React from 'react';
import { format, formatDistanceToNow } from 'date-fns';
import { fr } from 'date-fns/locale';
import { BadgeDistance } from '@/components/BadgeDistance';
import { BadgeStatut } from '@/components/BadgeStatut';
import { getLabelProfession, getLabelTypeEtablissement, extraireContratPreference, getContratBadge, getTypeContratRechercheBadge } from '@/lib/constantes';
import { getMissionMatchInfo } from '@/lib/profession-hierarchy';

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
  const temps = getTempsEcoule(m.cree_le);
  const profilComplet = soignant?.tous_documents_valides;
  const duree = m.duree_heures ?? ((new Date(m.fin_le).getTime() - new Date(m.debut_le).getTime()) / 3600000);
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
          <span className="badge-base bg-muted text-muted-foreground text-[10px]">💸 Sous votre minimum ({tauxMin} €/h)</span>
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
        </div>
        <span className={`text-[10px] ${temps.couleur}`}>{temps.texte}</span>
      </div>

      <h3 className="font-semibold text-sm text-foreground mb-0.5">{m.intitule}</h3>
      {m.service && <p className="text-[10px] text-muted-foreground mb-1">Service : {m.service}</p>}
      <div className="flex items-center gap-2 mb-1">
        {m.etablissements?.logo_url && (
          <img src={m.etablissements.logo_url} alt="" className="h-5 w-5 rounded object-cover shrink-0" />
        )}
        <p className="text-xs text-muted-foreground">
          🏥 {m.etablissements?.nom} · {m.etablissements?.adresse_ville}
          {m.etablissements?.adresse_departement && ` (${m.etablissements.adresse_departement})`}
        </p>
      </div>
      <BadgeDistance distanceKm={m.distance_km} />
      <span className={`badge-base text-[10px] ${contratBadge.classes}`}>{contratBadge.label}</span>

      <div className="mt-2 text-xs text-muted-foreground">
        <p>📅 {format(new Date(m.debut_le), 'EEEE d MMMM yyyy', { locale: fr })}</p>
        <p>🕐 {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })} ({Math.round(duree)}h)</p>
      </div>

      <div className="mt-2 flex items-center justify-between">
        <span className="text-primary font-bold text-sm">💰 {m.taux_horaire_base?.toFixed(2)} €/h</span>
        {(m.net_estime ?? m.net_a_payer ?? 0) > 0 ? (
          <span className="text-xs text-muted-foreground">Net estimé* : ~{fmt(m.net_estime ?? (m.net_a_payer != null ? m.net_a_payer * 0.78 : null))}</span>
        ) : (
          <span className="text-xs text-muted-foreground/50">Calculé après assignation</span>
        )}
      </div>
      {m.rist_plafond_applique && (
        <p className="text-[10px] text-warning font-medium mt-1">⚠️ Taux plafonné Loi Rist</p>
      )}

      <div className="mt-2 flex flex-wrap gap-1.5">
        {matchInfo && (
          <span className={`badge-base text-[10px] ${matchInfo.badgeClasses}`} title={matchInfo.tooltip}>
            {matchInfo.badgeLabel}
          </span>
        )}
        {profilComplet ? (
          <span className="badge-base bg-success/10 text-success text-[10px]">✅ Compatible</span>
        ) : soignant && !soignant.tous_documents_valides ? (
          <span className="badge-base bg-destructive/10 text-destructive text-[10px]">📄 Documents manquants</span>
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
