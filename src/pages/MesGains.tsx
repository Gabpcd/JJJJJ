import { useState, useEffect, useMemo } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Banknote, Clock, Download, TrendingUp } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide, IllustrationTirelire } from '@/components/EtatVide';
import { GraphiqueGains6Mois } from '@/components/GraphiqueGains6Mois';
import { ModalAttestation } from '@/components/ModalAttestation';
import { ModalCotisations } from '@/components/ModalCotisations';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Button } from '@/components/ui/button';
import { format, startOfMonth, endOfMonth } from 'date-fns';
import { fr } from 'date-fns/locale';

function fmt(v: number) {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export default function MesGains() {
  usePageTitle('Mes gains');
  const { user } = useAuth();
  const [allMissions, setAllMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [moisFiltre, setMoisFiltre] = useState('CE_MOIS');
  const [modalAttestation, setModalAttestation] = useState(false);
  const [cotisationsMissionId, setCotisationsMissionId] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const { data: ms } = await supabase
        .from('missions')
        .select(`id, intitule, debut_le, fin_le, duree_heures, taux_horaire_base,
          net_a_payer, net_estime, total_brut, statut, etablissement_id`)
        .eq('soignant_assigne_id', user.id)
        .eq('statut', 'TERMINEE')
        .order('debut_le', { ascending: false })
        .limit(1000);
      const enriched = ms ? await enrichirEtablissements(ms as any) : [];
      setAllMissions(enriched as any[]);
      setLoading(false);

      supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
        p_action: 'DONNEES_PERSO_CONSULTATION',
        p_type_ressource: 'soignant', p_id_ressource: user.id,
        p_cle_s3: null, p_details: { page: 'mes_gains' },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
    };
    load();
  }, [user]);

  const moisDisponibles = useMemo(() => {
    const set = new Set<string>();
    allMissions.forEach(m => set.add(m.debut_le.substring(0, 7)));
    return Array.from(set).sort().reverse();
  }, [allMissions]);

  const missions = useMemo(() => {
    if (moisFiltre === 'TOUS') return allMissions;
    if (moisFiltre === 'CE_MOIS') {
      const prefix = new Date().toISOString().substring(0, 7);
      return allMissions.filter(m => m.debut_le.startsWith(prefix));
    }
    return allMissions.filter(m => m.debut_le.startsWith(moisFiltre));
  }, [allMissions, moisFiltre]);

  const totalToutTemps = useMemo(() =>
    allMissions.reduce((s, m) => s + (m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0)), 0),
  [allMissions]);

  const totalFiltre = useMemo(() =>
    missions.reduce((s, m) => s + (m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0)), 0),
  [missions]);

  const totalHeures = useMemo(() =>
    missions.reduce((s, m) => s + (m.duree_heures || 0), 0),
  [missions]);

  const exporterCSV = () => {
    const header = 'Date,Mission,Établissement,Heures,Net estimé\n';
    const rows = missions.map(m => {
      const net = m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0);
      return `${format(new Date(m.debut_le), 'dd/MM/yyyy')},${m.intitule},${m.etablissements?.nom || ''},${m.duree_heures || 0},${net.toFixed(2)}`;
    }).join('\n');
    const blob = new Blob([header + rows], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = `gains-jolene-${new Date().toISOString().slice(0, 10)}.csv`; a.click();
    URL.revokeObjectURL(url);
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">💰 Mes gains</h1>
        <p className="text-sm text-muted-foreground mt-1">Visualisez vos revenus en un coup d'œil</p>
      </div>

      {/* KPIs en haut */}
      <div className="grid grid-cols-2 gap-3 mb-6">
        <CarteKPI icone={Banknote} valeur={fmt(totalFiltre)} label="Ce mois (net estimé*)" couleurIcone="text-primary" couleurFond="bg-primary/10" />
        <CarteKPI icone={TrendingUp} valeur={fmt(totalToutTemps)} label="Total tout temps" couleurIcone="text-success" couleurFond="bg-success/10" />
      </div>

      {/* Graphique barres 6 mois */}
      <GraphiqueGains6Mois missions={allMissions.map(m => ({ debut_le: m.debut_le, net_a_payer: m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0) }))} />

      {/* Filtre + Export */}
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <Select value={moisFiltre} onValueChange={setMoisFiltre}>
          <SelectTrigger className="w-52"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="CE_MOIS">Ce mois</SelectItem>
            <SelectItem value="TOUS">Tous les mois</SelectItem>
            {moisDisponibles.map(m => (
              <SelectItem key={m} value={m}>{format(new Date(m + '-01'), 'MMMM yyyy', { locale: fr })}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Button variant="outline" size="sm" onClick={exporterCSV} className="gap-1.5">
          <Download className="h-4 w-4" /> Exporter CSV
        </Button>
        <Button variant="outline" size="sm" onClick={() => setModalAttestation(true)} className="gap-1.5">
          📜 Attestation d'heures
        </Button>
      </div>

      <p className="text-xs text-muted-foreground italic mb-4">
        * Estimation après cotisations salariales (~22%). Seuls les montants calculés par le moteur de paie font foi.
      </p>

      {/* Liste simplifiée des missions payées */}
      {missions.length > 0 ? (
        <div className="space-y-2">
          {missions.map(m => {
            const net = m.net_estime || (m.net_a_payer ? m.net_a_payer * 0.78 : 0);
            return (
              <div key={m.id} className="flex items-center justify-between py-3 px-4 rounded-xl border border-border hover:bg-muted/30 transition-colors">
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium text-foreground truncate">{m.intitule}</p>
                  <p className="text-xs text-muted-foreground">
                    {format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr })} · {m.etablissements?.nom || '—'} · {m.duree_heures}h
                  </p>
                </div>
                <span className="font-bold text-primary text-sm shrink-0 ml-3 cursor-pointer hover:underline" onClick={(e) => { e.stopPropagation(); setCotisationsMissionId(m.id); }}>{fmt(net)}</span>
              </div>
            );
          })}
        </div>
      ) : (
        <EtatVide illustration={<IllustrationTirelire />} titre="Pas encore de gains" sousTitre="Vos gains apparaîtront ici après votre première mission terminée." />
      )}

      <ModalAttestation open={modalAttestation} onClose={() => setModalAttestation(false)} />
      <ModalCotisations missionId={cotisationsMissionId} open={!!cotisationsMissionId} onClose={() => setCotisationsMissionId(null)} />
    </LayoutApp>
  );
}
