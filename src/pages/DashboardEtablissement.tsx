import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Briefcase, PlayCircle, CheckCircle, TrendingUp, ClipboardList } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { BadgeStatut } from '@/components/BadgeStatut';
import { EtatVide } from '@/components/EtatVide';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

export default function DashboardEtablissement() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [etab, setEtab] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [kpi, setKpi] = useState({ ouvertes: 0, enCours: 0, terminees: 0, taux: 0 });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const [{ data: e }, { data: ms }] = await Promise.all([
        supabase.from('etablissements').select('*, groupes_sante(nom)').eq('id', user.id).single(),
        supabase.from('missions').select('id, intitule, service, debut_le, statut, soignant_assigne_id, soignants(prenom, nom)').eq('etablissement_id', user.id).order('cree_le', { ascending: false }).limit(5),
      ]);

      // KPI counts
      const [{ count: o }, { count: ec }, { count: t }, { count: total }, { count: assigned }] = await Promise.all([
        supabase.from('missions').select('*', { count: 'exact', head: true }).eq('etablissement_id', user.id).eq('statut', 'OUVERTE'),
        supabase.from('missions').select('*', { count: 'exact', head: true }).eq('etablissement_id', user.id).eq('statut', 'EN_COURS'),
        supabase.from('missions').select('*', { count: 'exact', head: true }).eq('etablissement_id', user.id).eq('statut', 'TERMINEE').gte('modifie_le', new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString()),
        supabase.from('missions').select('*', { count: 'exact', head: true }).eq('etablissement_id', user.id),
        supabase.from('missions').select('*', { count: 'exact', head: true }).eq('etablissement_id', user.id).not('soignant_assigne_id', 'is', null),
      ]);

      if (e) setEtab(e);
      if (ms) setMissions(ms);
      const totalN = total ?? 0;
      setKpi({
        ouvertes: o ?? 0, enCours: ec ?? 0, terminees: t ?? 0,
        taux: totalN > 0 ? Math.round(((assigned ?? 0) / totalN) * 100) : 0,
      });
      setLoading(false);
    };
    load();
  }, [user]);

  if (loading || !etab) return <LayoutApp role="ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ETABLISSEMENT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">Bienvenue, <span className="text-primary">{etab.nom}</span></h1>
        {etab.groupes_sante && (
          <div className="flex items-center gap-2 mt-1">
            <span className="text-sm text-muted-foreground">Groupe</span>
            <span className="badge-base bg-primary/10 text-primary">{etab.groupes_sante.nom}</span>
          </div>
        )}
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <CarteKPI icone={Briefcase} valeur={kpi.ouvertes} label="Missions ouvertes" couleurIcone="text-primary" couleurFond="bg-primary/10" />
        <CarteKPI icone={PlayCircle} valeur={kpi.enCours} label="En cours" couleurIcone="text-warning" couleurFond="bg-warning/10" />
        <CarteKPI icone={CheckCircle} valeur={kpi.terminees} label="Terminées ce mois" couleurIcone="text-success" couleurFond="bg-success/10" />
        <CarteKPI icone={TrendingUp} valeur={`${kpi.taux}%`} label="Taux d'occupation" couleurIcone={kpi.taux > 70 ? 'text-success' : 'text-warning'} couleurFond={kpi.taux > 70 ? 'bg-success/10' : 'bg-warning/10'} />
      </div>

      <div>
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-bold text-foreground">Dernières missions</h2>
          <button onClick={() => navigate('/etablissement/missions')} className="text-sm text-primary font-medium hover:underline">Voir tout →</button>
        </div>

        {missions.length > 0 ? (
          <>
            <div className="hidden md:block card-base overflow-hidden p-0">
              <table className="w-full text-sm">
                <thead><tr className="border-b border-border bg-muted/30">
                  <th className="text-left px-4 py-3 font-medium text-muted-foreground">Intitulé</th>
                  <th className="text-left px-4 py-3 font-medium text-muted-foreground">Service</th>
                  <th className="text-left px-4 py-3 font-medium text-muted-foreground">Date</th>
                  <th className="text-left px-4 py-3 font-medium text-muted-foreground">Statut</th>
                  <th className="text-left px-4 py-3 font-medium text-muted-foreground">Soignant</th>
                </tr></thead>
                <tbody>{missions.map(m => (
                  <tr key={m.id} className="border-b border-border last:border-0 hover:bg-muted/20 transition-colors">
                    <td className="px-4 py-3 font-medium text-foreground">{m.intitule}</td>
                    <td className="px-4 py-3 text-muted-foreground">{m.service || '—'}</td>
                    <td className="px-4 py-3 text-muted-foreground">{format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr })}</td>
                    <td className="px-4 py-3"><BadgeStatut statut={m.statut} /></td>
                    <td className="px-4 py-3 text-muted-foreground">{m.soignants ? `${m.soignants.prenom} ${m.soignants.nom}` : '—'}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
            <div className="md:hidden space-y-3">{missions.map(m => (
              <div key={m.id} className="card-base">
                <div className="flex items-start justify-between mb-2">
                  <h3 className="font-semibold text-sm text-foreground">{m.intitule}</h3>
                  <BadgeStatut statut={m.statut} />
                </div>
                <p className="text-xs text-muted-foreground">{m.service && `${m.service} · `}{format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr })}</p>
                <p className="text-xs text-muted-foreground mt-1">Soignant : {m.soignants ? `${m.soignants.prenom} ${m.soignants.nom}` : '—'}</p>
              </div>
            ))}</div>
          </>
        ) : (
          <EtatVide icone={ClipboardList} titre="Publiez votre première mission" sousTitre="Les soignants qualifiés de votre zone seront notifiés immédiatement" boutonLabel="Publier une mission" boutonRoute="/etablissement/missions/creer" />
        )}
      </div>
    </LayoutApp>
  );
}
