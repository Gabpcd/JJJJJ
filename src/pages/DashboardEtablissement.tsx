import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Briefcase, PlayCircle, CheckCircle, TrendingUp, ClipboardList } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { BadgeStatut } from '@/components/BadgeStatut';
import { EtatVide } from '@/components/EtatVide';
import { MOCK_ETABLISSEMENT, MOCK_MISSIONS_ETAB } from '@/lib/mock-data';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

export default function DashboardEtablissement() {
  const navigate = useNavigate();
  const etab = MOCK_ETABLISSEMENT;
  const missions = MOCK_MISSIONS_ETAB;

  const missionsOuvertes = missions.filter(m => m.statut === 'OUVERTE').length;
  const missionsEnCours = missions.filter(m => m.statut === 'EN_COURS').length;
  const missionsTerminees = missions.filter(m => m.statut === 'TERMINEE').length;
  const total = missions.length;
  const assignees = missions.filter(m => m.soignant_assigne_id).length;
  const tauxOccupation = total > 0 ? Math.round((assignees / total) * 100) : 0;

  return (
    <LayoutApp role="ETABLISSEMENT">
      {/* Bannière */}
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">Bienvenue, <span className="text-primary">{etab.nom}</span></h1>
        {etab.groupes_sante && (
          <div className="flex items-center gap-2 mt-1">
            <span className="text-sm text-muted-foreground">Groupe</span>
            <span className="badge-base bg-primary/10 text-primary">{etab.groupes_sante.nom}</span>
          </div>
        )}
      </div>

      {/* KPI Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <CarteKPI icone={Briefcase} valeur={missionsOuvertes} label="Missions ouvertes" couleurIcone="text-primary" couleurFond="bg-primary/10" />
        <CarteKPI icone={PlayCircle} valeur={missionsEnCours} label="En cours" couleurIcone="text-warning" couleurFond="bg-warning/10" />
        <CarteKPI icone={CheckCircle} valeur={missionsTerminees} label="Terminées ce mois" couleurIcone="text-success" couleurFond="bg-success/10" />
        <CarteKPI icone={TrendingUp} valeur={`${tauxOccupation}%`} label="Taux d'occupation" couleurIcone={tauxOccupation > 70 ? 'text-success' : 'text-warning'} couleurFond={tauxOccupation > 70 ? 'bg-success/10' : 'bg-warning/10'} />
      </div>

      {/* Dernières missions */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-bold text-foreground">Dernières missions</h2>
          <button onClick={() => navigate('/etablissement/missions')} className="text-sm text-primary font-medium hover:underline">
            Voir tout →
          </button>
        </div>

        {missions.length > 0 ? (
          <>
            {/* Desktop table */}
            <div className="hidden md:block card-base overflow-hidden p-0">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border bg-muted/30">
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Intitulé</th>
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Service</th>
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Date</th>
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Statut</th>
                    <th className="text-left px-4 py-3 font-medium text-muted-foreground">Soignant</th>
                  </tr>
                </thead>
                <tbody>
                  {missions.map(m => (
                    <tr key={m.id} className="border-b border-border last:border-0 hover:bg-muted/20 transition-colors">
                      <td className="px-4 py-3 font-medium text-foreground">{m.intitule}</td>
                      <td className="px-4 py-3 text-muted-foreground">{m.service || '—'}</td>
                      <td className="px-4 py-3 text-muted-foreground">{format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr })}</td>
                      <td className="px-4 py-3"><BadgeStatut statut={m.statut} /></td>
                      <td className="px-4 py-3 text-muted-foreground">
                        {m.soignants ? `${m.soignants.prenom} ${m.soignants.nom}` : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Mobile cards */}
            <div className="md:hidden space-y-3">
              {missions.map(m => (
                <div key={m.id} className="card-base">
                  <div className="flex items-start justify-between mb-2">
                    <h3 className="font-semibold text-sm text-foreground">{m.intitule}</h3>
                    <BadgeStatut statut={m.statut} />
                  </div>
                  <p className="text-xs text-muted-foreground">{m.service && `${m.service} · `}{format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr })}</p>
                  <p className="text-xs text-muted-foreground mt-1">
                    Soignant : {m.soignants ? `${m.soignants.prenom} ${m.soignants.nom}` : '—'}
                  </p>
                </div>
              ))}
            </div>
          </>
        ) : (
          <EtatVide
            icone={ClipboardList}
            titre="Publiez votre première mission"
            sousTitre="Les soignants qualifiés de votre zone seront notifiés immédiatement"
            boutonLabel="Publier une mission"
            boutonRoute="/etablissement/missions/creer"
          />
        )}
      </div>
    </LayoutApp>
  );
}
