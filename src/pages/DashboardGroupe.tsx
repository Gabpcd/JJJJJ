import React, { useState } from 'react';
import { Briefcase, PlayCircle, CheckCircle, TrendingUp } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { BadgeStatut } from '@/components/BadgeStatut';
import { MOCK_MISSIONS_ETAB, MOCK_ETABLISSEMENTS_GROUPE } from '@/lib/mock-data';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

export default function DashboardGroupe() {
  const [etabSelectionne, setEtabSelectionne] = useState<string>('tous');
  const etablissements = MOCK_ETABLISSEMENTS_GROUPE;
  const missions = MOCK_MISSIONS_ETAB;

  const missionsFiltrees = etabSelectionne === 'tous'
    ? missions
    : missions.filter(m => m.etablissement_id === etabSelectionne);

  const ouvertes = missionsFiltrees.filter(m => m.statut === 'OUVERTE').length;
  const enCours = missionsFiltrees.filter(m => m.statut === 'EN_COURS').length;
  const terminees = missionsFiltrees.filter(m => m.statut === 'TERMINEE').length;
  const total = missionsFiltrees.length;
  const assignees = missionsFiltrees.filter(m => m.soignant_assigne_id).length;
  const taux = total > 0 ? Math.round((assignees / total) * 100) : 0;

  return (
    <LayoutApp role="ADMIN_GROUPE">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">Tableau de bord — <span className="text-primary">AP-HP</span></h1>
        <p className="text-sm text-muted-foreground mt-1">Vue consolidée de vos établissements</p>
      </div>

      {/* Sélecteur d'établissement */}
      <div className="mb-6 overflow-x-auto">
        <div className="flex gap-2 pb-2">
          <button
            onClick={() => setEtabSelectionne('tous')}
            className={`badge-base whitespace-nowrap transition-colors ${
              etabSelectionne === 'tous' ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/80'
            }`}
          >
            Tous les établissements
          </button>
          {etablissements.map(e => (
            <button
              key={e.id}
              onClick={() => setEtabSelectionne(e.id)}
              className={`badge-base whitespace-nowrap transition-colors ${
                etabSelectionne === e.id ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/80'
              }`}
            >
              {e.nom} — {e.adresse_ville}
            </button>
          ))}
        </div>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <CarteKPI icone={Briefcase} valeur={ouvertes} label="Missions ouvertes" couleurIcone="text-primary" couleurFond="bg-primary/10" />
        <CarteKPI icone={PlayCircle} valeur={enCours} label="En cours" couleurIcone="text-warning" couleurFond="bg-warning/10" />
        <CarteKPI icone={CheckCircle} valeur={terminees} label="Terminées" couleurIcone="text-success" couleurFond="bg-success/10" />
        <CarteKPI icone={TrendingUp} valeur={`${taux}%`} label="Taux d'occupation" couleurIcone={taux > 70 ? 'text-success' : 'text-warning'} couleurFond={taux > 70 ? 'bg-success/10' : 'bg-warning/10'} />
      </div>

      {/* Missions */}
      <h2 className="text-lg font-bold text-foreground mb-3">Missions récentes</h2>
      <div className="space-y-3">
        {missionsFiltrees.map(m => (
          <div key={m.id} className="card-base">
            <div className="flex items-start justify-between mb-2">
              <h3 className="font-semibold text-sm text-foreground">{m.intitule}</h3>
              <BadgeStatut statut={m.statut} />
            </div>
            <p className="text-xs text-muted-foreground">
              {m.service && `${m.service} · `}{format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr })}
            </p>
            <p className="text-xs text-muted-foreground mt-1">
              Soignant : {m.soignants ? `${m.soignants.prenom} ${m.soignants.nom}` : '—'}
            </p>
          </div>
        ))}
      </div>
    </LayoutApp>
  );
}
