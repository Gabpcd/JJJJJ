import React from 'react';
import { useNavigate } from 'react-router-dom';
import { BadgeDistance } from '@/components/BadgeDistance';
import type { CreneauPointage } from '@/lib/disponibilite-pointage';
import { formatParis, instantJolene, memeJourParis } from '@/lib/date-heure-paris';
import { construirePlanningCandidat } from '@/components/planning/planning-candidat';
import { montantFinanceAfficheMission } from '@/lib/missionFinanceDisplay';

interface CarteSerieProps {
  missions: any[];
  role: 'soignant' | 'etablissement';
  soignant?: any;
  onAnnulerSerie?: () => void;
}

function fmt(v: number | null): string {
  if (v == null || v === 0) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export function extraireSerieId(description: string | null): string | null {
  if (!description) return null;
  // Only match valid serie IDs: SERIE_ followed by timestamp and alphanumeric suffix
  const match = description.match(/\[SERIE_ID:(SERIE_\d{10,15}_[a-z0-9]{4,8})\]/);
  return match ? match[1] : null;
}

export function CarteSerie({ missions, role, soignant, onAnnulerSerie }: CarteSerieProps) {
  const navigate = useNavigate();
  const sorted = [...missions].sort((a, b) => instantJolene(a.debut_le).getTime() - instantJolene(b.debut_le).getTime());
  const first = sorted[0];
  const last = sorted[sorted.length - 1];
  const missionCible = sorted.find((mission) => ['OUVERTE', 'ASSIGNEE', 'EN_COURS'].includes(mission.statut)) ?? first;

  const ouvertes = missions.filter(m => m.statut === 'OUVERTE').length;
  const assignees = missions.filter(m => m.statut === 'ASSIGNEE' || m.statut === 'EN_COURS').length;
  const terminees = missions.filter(m => m.statut === 'TERMINEE').length;
  const annulees = missions.filter(m => m.statut === 'ANNULEE_PAR_ETABLISSEMENT' || m.statut === 'ANNULEE_PAR_SOIGNANT').length;

  const plannings = sorted.map((mission) => construirePlanningCandidat({
    ...mission,
    creneaux_planifies: mission.creneaux_planifies ?? mission.creneaux ?? [],
  }));
  const planningSerieExact = plannings.every((planning) => planning.exact);
  const creneauxSerie = planningSerieExact
    ? plannings.flatMap((planning, index) => planning.creneaux.flatMap((creneau: CreneauPointage) => (
      creneau.fin ? [{ ...creneau, missionId: sorted[index].id }] : []
    )))
    : [];
  const apercuCreneaux = creneauxSerie.slice(0, 3);
  const tauxUniques = new Set(missions.map((mission) => Number(mission.taux_horaire_base)).filter(Number.isFinite));

  const montantsParNature = missions.reduce((totaux, mission) => {
    const finance = montantFinanceAfficheMission(mission);
    if (finance) totaux[finance.nature] += finance.montant;
    return totaux;
  }, { HONORAIRES_LIBERAUX: 0, NET_SALARIE_ESTIME: 0, BRUT_INDICATIF: 0 });
  const aUnMontant = Object.values(montantsParNature).some(montant => montant > 0);
  const resumeMontants = [
    montantsParNature.HONORAIRES_LIBERAUX > 0 ? `${fmt(montantsParNature.HONORAIRES_LIBERAUX)} honoraires` : null,
    montantsParNature.NET_SALARIE_ESTIME > 0 ? `~${fmt(montantsParNature.NET_SALARIE_ESTIME)} net salarié*` : null,
    montantsParNature.BRUT_INDICATIF > 0 ? `~${fmt(montantsParNature.BRUT_INDICATIF)} brut indicatif` : null,
  ].filter(Boolean).join(' · ');

  const serieId = extraireSerieId(first.description);

  const handleClick = () => {
    if (role === 'soignant' && serieId) {
      navigate(`/soignant/missions/serie/${encodeURIComponent(serieId)}`);
      return;
    }
    if (role === 'etablissement' && missionCible?.id) {
      navigate(`/etablissement/missions/${missionCible.id}`);
    }
  };

  return (
    <div
      onClick={handleClick}
      className="card-base border-l-4 border-l-primary hover:shadow-md cursor-pointer transition-all"
    >
      <div className="flex items-center gap-2 mb-2">
        <span className="badge-base bg-primary/10 text-primary text-[10px]">🔁 Série</span>
        {first.est_urgente && <span className="badge-base bg-destructive text-destructive-foreground text-[10px]">🔥 URGENT</span>}
      </div>

      <h3 className="font-semibold text-sm text-foreground mb-1">{first.intitule}</h3>

      {role === 'soignant' && first.etablissements && (
        <>
          <p className="text-xs text-muted-foreground mb-1">
            🏥 {first.etablissements.nom} · {first.etablissements.adresse_ville}
          </p>
          {first.distance_km !== undefined && <BadgeDistance distanceKm={first.distance_km} />}
        </>
      )}

      <p className="text-xs text-muted-foreground mt-1">
        📅 Du {formatParis(first.debut_le, 'd MMM')} au {formatParis(last.fin_le, 'd MMM yyyy')}
      </p>

      {creneauxSerie.length > 0 ? (
        <div className="mt-1 text-xs text-muted-foreground">
          <p>{creneauxSerie.length} créneau{creneauxSerie.length > 1 ? 'x' : ''} planifié{creneauxSerie.length > 1 ? 's' : ''}</p>
          <ul className="mt-1 space-y-0.5" aria-label="Aperçu des créneaux de la série">
            {apercuCreneaux.map((creneau) => (
              <li key={`${creneau.missionId}:${creneau.id ?? creneau.debut}`}>
                {formatParis(creneau.debut, 'EEE d MMM · HH:mm')} → {memeJourParis(creneau.debut, creneau.fin!)
                  ? formatParis(creneau.fin!, 'HH:mm')
                  : formatParis(creneau.fin!, 'EEE d MMM · HH:mm')}
              </li>
            ))}
          </ul>
          {creneauxSerie.length > apercuCreneaux.length && (
            <p className="mt-1 text-primary">+ {creneauxSerie.length - apercuCreneaux.length} autre{creneauxSerie.length - apercuCreneaux.length > 1 ? 's' : ''}</p>
          )}
        </div>
      ) : (
        <p className="mt-1 text-xs font-medium text-warning">Planning détaillé à confirmer.</p>
      )}

      {role === 'etablissement' && (
        <p className="text-xs text-muted-foreground mt-1">
          Ouvertes: {ouvertes} · Assignées: {assignees} · Terminées: {terminees}
          {annulees > 0 && ` · Annulées: ${annulees}`}
        </p>
      )}

      <div className="mt-2 flex items-center justify-between">
        <span className="text-primary font-bold text-sm">
          💰 {role === 'etablissement' && tauxUniques.size > 1
            ? 'Tarifs variables'
            : `${first.taux_horaire_base?.toFixed(2)} €/h`}
        </span>
        {role === 'soignant' && aUnMontant && (
          <span className="text-xs text-muted-foreground">
            {resumeMontants}
          </span>
        )}
      </div>

      {role === 'soignant' && (
        <div className="mt-2 text-right">
          <button
            type="button"
            onClick={(event) => { event.stopPropagation(); handleClick(); }}
            className="text-xs text-primary font-medium"
          >
            Voir le détail du pack →
          </button>
        </div>
      )}

      {role === 'etablissement' && (
        <div className="mt-2 text-right">
          <button
            type="button"
            onClick={(event) => { event.stopPropagation(); handleClick(); }}
            className="text-xs font-medium text-primary"
            aria-label={`Ouvrir une mission de la série ${first.intitule}`}
          >
            Ouvrir le détail d’une mission →
          </button>
        </div>
      )}

      {role === 'etablissement' && onAnnulerSerie && ouvertes > 0 && (
        <div className="mt-3 flex gap-2" onClick={e => e.stopPropagation()}>
          <button
            onClick={onAnnulerSerie}
            className="text-xs font-medium text-destructive hover:underline"
          >
            Annuler toute la série ({ouvertes} ouvertes)
          </button>
        </div>
      )}

      {(role === 'soignant' && aUnMontant) && (
        <p className="text-[10px] text-muted-foreground/60 italic mt-1">
          Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
        </p>
      )}
    </div>
  );
}
