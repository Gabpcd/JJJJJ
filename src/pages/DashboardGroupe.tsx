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
import { avecDelai } from '@/lib/avecDelai';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

export default function DashboardGroupe() {
  usePageTitle('Dashboard Groupe');
  const navigate = useNavigate();
  const { user } = useAuth();
  const userId = user?.id;
  const [etabSelectionne, setEtabSelectionne] = useState('tous');
  const [etablissements, setEtablissements] = useState<any[]>([]);
  const [groupeNom, setGroupeNom] = useState('Mon Groupe');
  const [loading, setLoading] = useState(true);
  const [filtreDepartement, setFiltreDepartement] = useState('');
  const [filtreType, setFiltreType] = useState('');
  const [kpi, setKpi] = useState({ ouvertes: 0, enCours: 0, terminees: 0, actifs: 0 });
  const [perfParEtab, setPerfParEtab] = useState<any[]>([]);
  const [erreur, setErreur] = useState(false);
  const [erreurStats, setErreurStats] = useState(false);
  const [loadingStats, setLoadingStats] = useState(true);
  const [tentative, setTentative] = useState(0);
  const [tentativeStats, setTentativeStats] = useState(0);

  useEffect(() => {
    let actif = true;
    setLoading(true);
    setErreur(false);
    if (!userId) return () => { actif = false; };
    void (async () => {
      try {
        const { data: adminData, error } = await avecDelai(supabase.from('admins_groupe_sante')
          .select('groupe_id, groupes_sante(nom)').eq('utilisateur_id', userId).limit(1).single(), 15_000);
        if (error || !adminData?.groupe_id) throw error || new Error('Groupe indisponible');
        const resultat = await avecDelai(supabase.from('etablissements')
          .select('id, nom, adresse_ville, adresse_departement, type')
          .eq('groupe_sante_id', adminData.groupe_id).is('supprime_le', null).order('nom'), 15_000);
        if (resultat.error || !Array.isArray(resultat.data)) throw resultat.error || new Error('Liste indisponible');
        if (!actif) return;
        setGroupeNom((adminData as any).groupes_sante?.nom || 'Mon Groupe');
        setEtablissements(resultat.data);
      } catch {
        if (actif) setErreur(true);
      } finally {
        if (actif) setLoading(false);
      }
    })();
    return () => { actif = false; };
  }, [userId, tentative]);

  // Compute filtered etabs
  const etabsFiltres = useMemo(() => etablissements.filter(e => {
    if (filtreDepartement && e.adresse_departement !== filtreDepartement) return false;
    if (filtreType && e.type !== filtreType) return false;
    return true;
  }), [etablissements, filtreDepartement, filtreType]);

  const etabsSelectionnes = useMemo(() => etabSelectionne === 'tous'
    ? etabsFiltres : etabsFiltres.filter(e => e.id === etabSelectionne), [etabSelectionne, etabsFiltres]);

  useEffect(() => {
    let actif = true;
    setErreurStats(false);
    setLoadingStats(true);
    if (loading || erreur) return () => { actif = false; };
    const etabIds = etabsSelectionnes.map(e => e.id);
    if (!etabIds.length) {
      setKpi({ ouvertes: 0, enCours: 0, terminees: 0, actifs: 0 });
      setPerfParEtab([]);
      setLoadingStats(false);
      return () => { actif = false; };
    }
    void (async () => {
      try {
        const debutMois = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString();
        const comptes = await avecDelai(Promise.all([
          supabase.from('missions').select('id', { count: 'exact', head: true }).in('etablissement_id', etabIds).eq('statut', 'OUVERTE'),
          supabase.from('missions').select('id', { count: 'exact', head: true }).in('etablissement_id', etabIds).eq('statut', 'EN_COURS'),
          supabase.from('missions').select('id', { count: 'exact', head: true }).in('etablissement_id', etabIds).eq('statut', 'TERMINEE').gte('modifie_le', debutMois),
        ]), 15_000);
        if (comptes.some(r => r.error || r.count === null)) throw new Error('Statistiques indisponibles');
        // Paginer pour ne pas tronquer la performance au plafond PostgREST.
        const missions: { etablissement_id: string; statut: string }[] = [];
        for (let debut = 0; ; debut += 1000) {
          const resultat = await avecDelai(supabase.from('missions').select('etablissement_id, statut')
            .in('etablissement_id', etabIds).order('id').range(debut, debut + 999), 15_000);
          if (!actif) return;
          if (resultat.error || !Array.isArray(resultat.data)) throw resultat.error || new Error('Performance indisponible');
          missions.push(...resultat.data);
          if (resultat.data.length < 1000) break;
        }
        if (!actif) return;
        setKpi({ ouvertes: comptes[0].count!, enCours: comptes[1].count!, terminees: comptes[2].count!, actifs: etabsSelectionnes.length });
        setPerfParEtab(etabsSelectionnes.map(e => {
          const ms = missions.filter(m => m.etablissement_id === e.id);
          const ouvertes = ms.filter(m => m.statut === 'OUVERTE').length;
          const assignees = ms.filter(m => m.statut === 'ASSIGNEE').length;
          const terminees = ms.filter(m => m.statut === 'TERMINEE').length;
          return { ...e, ouvertes, assignees, terminees, taux: ms.length ? Math.round((assignees + terminees) / ms.length * 100) : 0 };
        }));
      } catch {
        if (actif) setErreurStats(true);
      } finally {
        if (actif) setLoadingStats(false);
      }
    })();
    return () => { actif = false; };
  }, [etabsSelectionnes, loading, erreur, tentativeStats]);

  if (loading) return <LayoutApp role="ADMIN_GROUPE"><ChargementPage /></LayoutApp>;

  if (erreur) return <LayoutApp role="ADMIN_GROUPE"><div className="card-base space-y-3" role="alert">
    <h1 className="text-xl font-bold">Tableau de bord du groupe</h1>
    <p>Impossible de charger les établissements du groupe.</p>
    <BoutonY2K onClick={() => setTentative(t => t + 1)}>Réessayer</BoutonY2K>
  </div></LayoutApp>;

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

      {loadingStats ? <ChargementPage /> : erreurStats ? <div className="card-base space-y-3" role="alert">
        <p>Impossible de charger les statistiques du groupe.</p>
        <BoutonY2K onClick={() => setTentativeStats(t => t + 1)}>Réessayer</BoutonY2K>
      </div> : <>
      <div className="grid grid-cols-2 xl:grid-cols-4 gap-3 mb-6">
        <CarteKPIY2K className="w-full min-w-0 h-full"
          icone={<Briefcase className="h-4 w-4" />}
          valeur={kpi.ouvertes}
          label="Missions ouvertes"
          variant="holographic"
          onClick={() => navigate('/groupe/etablissements')}
        />
        <CarteKPIY2K className="w-full min-w-0 h-full"
          icone={<PlayCircle className="h-4 w-4" />}
          valeur={kpi.enCours}
          label="En cours"
          variant="default"
          onClick={() => navigate('/groupe/etablissements')}
        />
        <CarteKPIY2K className="w-full min-w-0 h-full"
          icone={<CheckCircle className="h-4 w-4" />}
          valeur={kpi.terminees}
          label="Terminées ce mois"
          variant="default"
          onClick={() => navigate('/groupe/etablissements')}
        />
        <CarteKPIY2K className="w-full min-w-0 h-full"
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
      </>}
    </LayoutApp>
  );
}
