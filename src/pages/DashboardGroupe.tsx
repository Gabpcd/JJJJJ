import React, { useState, useEffect } from 'react';
import { Briefcase, PlayCircle, CheckCircle, TrendingUp } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { BadgeStatut } from '@/components/BadgeStatut';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

export default function DashboardGroupe() {
  const { user } = useAuth();
  const [etabSelectionne, setEtabSelectionne] = useState<string>('tous');
  const [etablissements, setEtablissements] = useState<any[]>([]);
  const [missions, setMissions] = useState<any[]>([]);
  const [groupeNom, setGroupeNom] = useState('Mon Groupe');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      // Get group id from admin table
      const { data: adminData } = await supabase.from('admins_groupe_sante').select('groupe_id, groupes_sante(nom)').eq('utilisateur_id', user.id).limit(1).single();

      if (!adminData) { setLoading(false); return; }
      const groupeId = adminData.groupe_id;
      setGroupeNom((adminData as any).groupes_sante?.nom || 'Mon Groupe');

      const { data: etabs } = await supabase.from('etablissements').select('id, nom, adresse_ville').eq('groupe_sante_id', groupeId);
      if (etabs) setEtablissements(etabs);

      const etabIds = etabs?.map(e => e.id) || [];
      if (etabIds.length > 0) {
        const { data: ms } = await supabase.from('missions').select('id, intitule, service, debut_le, statut, soignant_assigne_id, etablissement_id, soignants(prenom, nom)').in('etablissement_id', etabIds).order('cree_le', { ascending: false }).limit(20);
        if (ms) setMissions(ms);
      }
      setLoading(false);
    };
    load();
  }, [user]);

  if (loading) return <LayoutApp role="ADMIN_GROUPE"><ChargementPage /></LayoutApp>;

  const missionsFiltrees = etabSelectionne === 'tous' ? missions : missions.filter(m => m.etablissement_id === etabSelectionne);
  const ouvertes = missionsFiltrees.filter(m => m.statut === 'OUVERTE').length;
  const enCours = missionsFiltrees.filter(m => m.statut === 'EN_COURS').length;
  const terminees = missionsFiltrees.filter(m => m.statut === 'TERMINEE').length;
  const total = missionsFiltrees.length;
  const assignees = missionsFiltrees.filter(m => m.soignant_assigne_id).length;
  const taux = total > 0 ? Math.round((assignees / total) * 100) : 0;

  return (
    <LayoutApp role="ADMIN_GROUPE">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">Tableau de bord — <span className="text-primary">{groupeNom}</span></h1>
        <p className="text-sm text-muted-foreground mt-1">Vue consolidée de vos établissements</p>
      </div>

      <div className="mb-6 overflow-x-auto">
        <div className="flex gap-2 pb-2">
          <button onClick={() => setEtabSelectionne('tous')} className={`badge-base whitespace-nowrap transition-colors ${etabSelectionne === 'tous' ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/80'}`}>Tous les établissements</button>
          {etablissements.map(e => (
            <button key={e.id} onClick={() => setEtabSelectionne(e.id)} className={`badge-base whitespace-nowrap transition-colors ${etabSelectionne === e.id ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-muted/80'}`}>
              {e.nom} — {e.adresse_ville}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <CarteKPI icone={Briefcase} valeur={ouvertes} label="Missions ouvertes" couleurIcone="text-primary" couleurFond="bg-primary/10" />
        <CarteKPI icone={PlayCircle} valeur={enCours} label="En cours" couleurIcone="text-warning" couleurFond="bg-warning/10" />
        <CarteKPI icone={CheckCircle} valeur={terminees} label="Terminées" couleurIcone="text-success" couleurFond="bg-success/10" />
        <CarteKPI icone={TrendingUp} valeur={`${taux}%`} label="Taux d'occupation" couleurIcone={taux > 70 ? 'text-success' : 'text-warning'} couleurFond={taux > 70 ? 'bg-success/10' : 'bg-warning/10'} />
      </div>

      <h2 className="text-lg font-bold text-foreground mb-3">Missions récentes</h2>
      <div className="space-y-3">
        {missionsFiltrees.length > 0 ? missionsFiltrees.slice(0, 10).map(m => (
          <div key={m.id} className="card-base">
            <div className="flex items-start justify-between mb-2">
              <h3 className="font-semibold text-sm text-foreground">{m.intitule}</h3>
              <BadgeStatut statut={m.statut} />
            </div>
            <p className="text-xs text-muted-foreground">{m.service && `${m.service} · `}{format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr })}</p>
            <p className="text-xs text-muted-foreground mt-1">Soignant : {m.soignants ? `${m.soignants.prenom} ${m.soignants.nom}` : '—'}</p>
          </div>
        )) : (
          <p className="text-sm text-muted-foreground text-center py-8">Aucune mission pour cette sélection.</p>
        )}
      </div>
    </LayoutApp>
  );
}
