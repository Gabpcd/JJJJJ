import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Calendar, Clock, Banknote, User, Copy, XCircle, RotateCcw } from 'lucide-react';
import { BadgeStatut } from '@/components/BadgeStatut';
import { getLabelProfession } from '@/lib/constantes';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface CarteMissionProps {
  mission: any;
  afficherEtablissement?: boolean;
  onDupliquer?: (mission: any) => void;
  onAnnuler?: (mission: any) => void;
  onRepublier?: (mission: any) => void;
}

function formatMontant(v: number | null | undefined): string {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

function tempsDepuis(dateStr: string): { texte: string; couleur: string } {
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 60) return { texte: `Il y a ${minutes} min`, couleur: 'text-success' };
  const heures = Math.floor(minutes / 60);
  if (heures < 24) return { texte: `Il y a ${heures}h`, couleur: 'text-warning' };
  const jours = Math.floor(heures / 24);
  return { texte: `Il y a ${jours} jour${jours > 1 ? 's' : ''}`, couleur: 'text-destructive' };
}

function scoreColor(score: number): string {
  if (score >= 70) return 'text-success';
  if (score >= 40) return 'text-warning';
  return 'text-destructive';
}

export function CarteMission({ mission, afficherEtablissement, onDupliquer, onAnnuler, onRepublier }: CarteMissionProps) {
  const navigate = useNavigate();
  const m = mission;
  const debut = new Date(m.debut_le);
  const fin = new Date(m.fin_le);
  const duree = m.duree_heures ?? ((fin.getTime() - debut.getTime()) / 3600000);
  const heureDebut = format(debut, 'HH:mm');
  const heureFin = format(fin, 'HH:mm');
  const dateFormatee = format(debut, 'EEEE d MMMM yyyy', { locale: fr });
  const tempsInfo = m.statut === 'OUVERTE' ? tempsDepuis(m.cree_le) : null;
  const estAnnulee = m.statut === 'ANNULEE_PAR_ETABLISSEMENT' || m.statut === 'ANNULEE_PAR_SOIGNANT';

  return (
    <div
      className="card-base hover:shadow-md transition-shadow cursor-pointer"
      onClick={() => navigate(`/etablissement/missions/${m.id}`)}
    >
      <div className="flex items-start justify-between mb-2">
        <div className="flex items-center gap-2 flex-wrap">
          {m.est_urgente && (
            <span className="badge-base bg-destructive/10 text-destructive text-[10px]">
              {m.niveau_urgence === 3 ? '🚨 URGENT Critique' : m.niveau_urgence === 2 ? '🔥 URGENT Élevé' : '⚡ URGENT'}
            </span>
          )}
          <BadgeStatut statut={m.statut} />
          {tempsInfo && (
            <span className={`text-[10px] font-medium ${tempsInfo.couleur}`}>{tempsInfo.texte}</span>
          )}
        </div>
      </div>

      <h3 className="font-semibold text-sm text-foreground mb-1">{m.intitule}</h3>
      <p className="text-xs text-muted-foreground mb-2">
        {m.service && `${m.service} · `}{getLabelProfession(m.profession_requise)}
      </p>

      <div className="flex items-center gap-4 text-xs text-muted-foreground mb-2">
        <span className="flex items-center gap-1"><Calendar className="h-3.5 w-3.5" />{dateFormatee}</span>
      </div>
      <div className="flex items-center gap-4 text-xs text-muted-foreground mb-3">
        <span className="flex items-center gap-1">
          <Clock className="h-3.5 w-3.5" />{heureDebut} → {heureFin} ({Math.round(duree * 10) / 10}h)
        </span>
      </div>

      <div className="flex items-center gap-2 text-xs mb-2">
        <Banknote className="h-3.5 w-3.5 text-primary" />
        <span className="text-foreground font-medium">{m.taux_horaire_base?.toFixed(2)} €/h</span>
        {m.net_a_payer > 0 && (
          <span className="text-muted-foreground">→ Net estimé : <strong className="text-primary">{formatMontant(m.net_a_payer)}</strong></span>
        )}
      </div>
      {m.rist_plafond_applique && (
        <p className="text-[10px] text-warning font-medium mb-2">⚠️ Taux plafonné Loi Rist</p>
      )}

      <div className="flex items-center gap-2 text-xs text-muted-foreground mb-3">
        <User className="h-3.5 w-3.5" />
        {m.soignants ? (
          <span>
            {m.soignants.prenom} {m.soignants.nom}
            {m.soignants.score_fiabilite != null && (
              <span className={`ml-1 font-semibold ${scoreColor(m.soignants.score_fiabilite)}`}>
                (⭐ {m.soignants.score_fiabilite}/100)
              </span>
            )}
          </span>
        ) : (
          <span className="italic">— En attente d'un soignant</span>
        )}
      </div>

      <div className="flex gap-2 mt-2" onClick={(e) => e.stopPropagation()}>
        <button
          onClick={() => navigate(`/etablissement/missions/${m.id}`)}
          className="text-xs font-medium text-primary hover:underline"
        >
          Voir détail
        </button>
        {onDupliquer && (
          <button onClick={() => onDupliquer(m)} className="text-xs font-medium text-muted-foreground hover:text-foreground flex items-center gap-1">
            <Copy className="h-3 w-3" /> Dupliquer
          </button>
        )}
        {onAnnuler && (m.statut === 'OUVERTE' || m.statut === 'ASSIGNEE') && (
          <button onClick={() => onAnnuler(m)} className="text-xs font-medium text-destructive hover:underline flex items-center gap-1">
            <XCircle className="h-3 w-3" /> Annuler
          </button>
        )}
        {onRepublier && estAnnulee && (
          <button onClick={() => onRepublier(m)} className="text-xs font-medium text-primary hover:underline flex items-center gap-1">
            <RotateCcw className="h-3 w-3" /> Republier
          </button>
        )}
      </div>
    </div>
  );
}
