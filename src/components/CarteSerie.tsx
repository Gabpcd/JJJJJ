import React from 'react';
import { useNavigate } from 'react-router-dom';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { BadgeDistance } from '@/components/BadgeDistance';

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
  const match = description.match(/\[SERIE_ID:([^\]]+)\]/);
  return match ? match[1] : null;
}

export function CarteSerie({ missions, role, soignant, onAnnulerSerie }: CarteSerieProps) {
  const navigate = useNavigate();
  const sorted = [...missions].sort((a, b) => new Date(a.debut_le).getTime() - new Date(b.debut_le).getTime());
  const first = sorted[0];
  const last = sorted[sorted.length - 1];

  const ouvertes = missions.filter(m => m.statut === 'OUVERTE').length;
  const assignees = missions.filter(m => m.statut === 'ASSIGNEE' || m.statut === 'EN_COURS').length;
  const terminees = missions.filter(m => m.statut === 'TERMINEE').length;
  const annulees = missions.filter(m => m.statut === 'ANNULEE_PAR_ETABLISSEMENT' || m.statut === 'ANNULEE_PAR_SOIGNANT').length;

  const debutH = format(new Date(first.debut_le), "HH'h'mm", { locale: fr });
  const finH = format(new Date(first.fin_le), "HH'h'mm", { locale: fr });

  const netTotal = missions.reduce((t: number, m: any) => t + (m.net_a_payer || 0), 0);

  const serieId = extraireSerieId(first.description);

  const handleClick = () => {
    if (role === 'soignant' && serieId) {
      navigate(`/soignant/missions/serie/${encodeURIComponent(serieId)}`);
    }
  };

  return (
    <div
      onClick={role === 'soignant' ? handleClick : undefined}
      className={`card-base border-l-4 border-l-primary ${role === 'soignant' ? 'hover:shadow-md cursor-pointer transition-all' : ''}`}
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
        📅 Du {format(new Date(first.debut_le), 'd MMM', { locale: fr })} au {format(new Date(last.debut_le), 'd MMM yyyy', { locale: fr })}
      </p>
      <p className="text-xs text-muted-foreground">
        🕐 {debutH} → {finH} · {missions.length} créneau{missions.length > 1 ? 'x' : ''}
      </p>

      {role === 'etablissement' && (
        <p className="text-xs text-muted-foreground mt-1">
          Ouvertes: {ouvertes} · Assignées: {assignees} · Terminées: {terminees}
          {annulees > 0 && ` · Annulées: ${annulees}`}
        </p>
      )}

      <div className="mt-2 flex items-center justify-between">
        <span className="text-primary font-bold text-sm">💰 {first.taux_horaire_base?.toFixed(2)} €/h</span>
        {role === 'soignant' && netTotal > 0 && (
          <span className="text-xs text-muted-foreground">
            Net estimé total : ~{fmt(netTotal)}
          </span>
        )}
      </div>

      {role === 'soignant' && (
        <div className="mt-2 text-right">
          <span className="text-xs text-primary font-medium">Voir le détail du pack →</span>
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

      {(role === 'soignant' && netTotal > 0) && (
        <p className="text-[10px] text-muted-foreground/60 italic mt-1">
          Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
        </p>
      )}
    </div>
  );
}
