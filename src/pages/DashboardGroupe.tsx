import { usePageTitle } from '@/hooks/usePageTitle';
import React, { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { Briefcase, PlayCircle, CheckCircle, Building2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { SelecteurEtablissement } from '@/components/SelecteurEtablissement';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { getLabelTypeEtablissement } from '@/lib/constantes';

export default function DashboardGroupe() {
  usePageTitle('Dashboard Groupe');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [etabSelectionne, setEtabSelectionne] = useState('tous');
  const [etablissements, setEtablissements] = useState<any[]>([]);
  const [groupeNom, setGroupeNom] = useState('Mon Groupe');
  const [loading, setLoading] = useState(true);
  const [filtreDepartement, setFiltreDepartement] = useState('');
  const [filtreType, setFiltreType] = useState('');
  const [kpi, setKpi] = useState({ ouvertes: 0, enCours: 0, terminees: 0, actifs: 0 });
  const [perfParEtab, setPerfParEtab] = useState<any[]>([]);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const { data: adminData } = await supabase
        .from('admins_groupe_sante')
        .select('groupe_id, groupes_sante(nom)')
        .eq('utilisateur_id', user.id)
        .limit(1)
        .single();

      if (!adminData) { setLoading(false); return; }
      const groupeId = adminData.groupe_id;
      setGroupeNom((adminData as any).groupes_sante?.nom || 'Mon Groupe');

      const { data: etabs } = await supabase
        .from('etablissements')
        .select('id, nom, adresse_ville, adresse_departement, type')
        .eq('groupe_sante_id', groupeId)
        .is('supprime_le', null)
        .order('nom');

      if (etabs) setEtablissements(etabs);
      setLoading(false);
    };
    load();
  }, [user]);

  // Compute filtered etabs
  const etabsFiltres = useMemo(() => etablissements.filter(e => {
    if (filtreDepartement && e.adresse_departement !== filtreDepartement) return false;
    if (filtreType && e.type !== filtreType) return false;
    return true;
  }), [etablissements, filtreDepartement, filtreType]);

  const etabIds = useMemo(() => etabSelectionne === 'tous'
    ? etabsFiltres.map(e => e.id)
    : etabsFiltres.filter(e => e.id === etabSelectionne).map(e => e.id),
  [etabSelectionne, etabsFiltres]);

  useEffect(() => {
    if (etabIds.length === 0) {
      setKpi({ ouvertes: 0, enCours: 0, terminees: 0, actifs: 0 });
      setPerfParEtab([]);
      return;
    }
    const loadKpi = async () => {
      const debutMois = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString();
      const [{ count: o }, { count: ec }, { count: t }] = await Promise.all([
        supabase.from('missions').select('id', { count: 'exact', head: true }).in('etablissement_id', etabIds).eq('statut', 'OUVERTE'),
        supabase.from('missions').select('id', { count: 'exact', head: true }).in('etablissement_id', etabIds).eq('statut', 'EN_COURS'),
        supabase.from('missions').select('id', { count: 'exact', head: true }).in('etablissement_id', etabIds).eq('statut', 'TERMINEE').gte('modifie_le', debutMois),
      ]);
      setKpi({ ouvertes: o ?? 0, enCours: ec ?? 0, terminees: t ?? 0, actifs: etabsFiltres.length });

      // Performance par établissement — batch query (1 query instead of 4N)
      const { data: allMissions } = await supabase
        .from('missions')
        .select('etablissement_id, statut')
        .in('etablissement_id', etabIds);
      const missionsByEtab: Record<string, any[]> = {};
      for (const m of allMissions || []) {
        (missionsByEtab[m.etablissement_id] ??= []).push(m);
      }
      const perfs = etabsFiltres.map((e) => {
        const ms = missionsByEtab[e.id] || [];
        const ouv = ms.filter(m => m.statut === 'OUVERTE').length;
        const ass = ms.filter(m => m.statut === 'ASSIGNEE').length;
        const term = ms.filter(m => m.statut === 'TERMINEE').length;
        const totalN = ms.length;
        const assigned = ass + term;
        return {
          ...e,
          ouvertes: ouv,
          assignees: ass,
          terminees: term,
          taux: totalN > 0 ? Math.round((assigned / totalN) * 100) : 0,
        };
      });
      setPerfParEtab(perfs);
    };
    loadKpi();
  }, [etabIds, etabsFiltres]);

  if (loading) return <LayoutApp role="ADMIN_GROUPE"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_GROUPE">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">Tableau de bord — <span className="text-primary">{groupeNom}</span></h1>
        <p className="text-sm text-muted-foreground mt-1">Vue consolidée de vos établissements</p>
      </div>

      <div className="mb-6">
        <SelecteurEtablissement
          etablissements={etablissements}
          valeur={etabSelectionne}
          onChange={setEtabSelectionne}
          avecFiltres
          filtreDepartement={filtreDepartement}
          onChangeDepartement={setFiltreDepartement}
          filtreType={filtreType}
          onChangeType={setFiltreType}
        />
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <CarteKPIY2K
          icone={<Briefcase className="h-4 w-4" />}
          valeur={kpi.ouvertes}
          label="Missions ouvertes"
          variant="holographic"
          onClick={() => navigate('/groupe/etablissements')}
        />
        <CarteKPIY2K
          icone={<PlayCircle className="h-4 w-4" />}
          valeur={kpi.enCours}
          label="En cours"
          variant="default"
          onClick={() => navigate('/groupe/etablissements')}
        />
        <CarteKPIY2K
          icone={<CheckCircle className="h-4 w-4" />}
          valeur={kpi.terminees}
          label="Terminées ce mois"
          variant="default"
          onClick={() => navigate('/groupe/etablissements')}
        />
        <CarteKPIY2K
          icone={<Building2 className="h-4 w-4" />}
          valeur={kpi.actifs}
          label="Établissements actifs"
          variant="default"
        />
      </div>

      {/* Tableau de performance */}
      <h2 className="text-lg font-bold text-foreground mb-3">Performance par établissement</h2>
      <div className="card-base overflow-x-auto p-0">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border bg-muted/30">
              <th className="text-left px-4 py-3 font-medium text-muted-foreground">Établissement</th>
              <th className="text-center px-4 py-3 font-medium text-muted-foreground">Ouvertes</th>
              <th className="text-center px-4 py-3 font-medium text-muted-foreground">Assignées</th>
              <th className="text-center px-4 py-3 font-medium text-muted-foreground">Terminées</th>
              <th className="text-center px-4 py-3 font-medium text-muted-foreground">Taux</th>
            </tr>
          </thead>
          <tbody>
            {perfParEtab.map(e => (
              <tr
                key={e.id}
                onClick={() => setEtabSelectionne(e.id)}
                className="border-b border-border last:border-0 hover:bg-muted/20 transition-colors cursor-pointer"
              >
                <td className="px-4 py-3">
                  <p className="font-medium text-foreground">{e.nom}</p>
                  <p className="text-xs text-muted-foreground">{e.adresse_ville}</p>
                </td>
                <td className="px-4 py-3 text-center">{e.ouvertes}</td>
                <td className="px-4 py-3 text-center">{e.assignees}</td>
                <td className="px-4 py-3 text-center">{e.terminees}</td>
                <td className={`px-4 py-3 text-center font-semibold ${e.taux >= 70 ? 'text-success' : e.taux >= 40 ? 'text-warning' : 'text-destructive'}`}>
                  {e.taux}%
                </td>
              </tr>
            ))}
            {perfParEtab.length === 0 && (
              <tr><td colSpan={5} className="px-4 py-8 text-center text-muted-foreground">Aucun établissement trouvé</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </LayoutApp>
  );
}
