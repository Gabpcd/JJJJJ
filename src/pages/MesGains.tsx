import { useState, useEffect, useMemo, lazy, Suspense } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Banknote, Clock, Download, TrendingUp, ChevronRight, Calculator, FileText, Search, CheckCircle, AlertTriangle, Scale } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { CarteKPI } from '@/components/CarteKPI';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState, IllustrationTirelire } from '@/components/ui/EmptyState';
const GraphiqueGains6Mois = lazy(() =>
  import('@/components/GraphiqueGains6Mois').then(m => ({ default: m.GraphiqueGains6Mois }))
);
import { ModalAttestation } from '@/components/ModalAttestation';
import { ModalCotisations } from '@/components/ModalCotisations';
import { useAuth } from '@/contexts/AuthContext';
import { BandeauPaiementDeclare } from '@/components/BandeauPaiementDeclare';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { handleErrorSilent } from '@/lib/handleError';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Button } from '@/components/ui/button';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

function fmt(v: number | null | undefined) {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

function netEstime(m: any): number | null {
  return m.net_estime ?? (m.net_a_payer != null ? m.net_a_payer * 0.78 : (m.total_brut != null ? m.total_brut * 0.78 : null));
}

export default function MesGains() {
  usePageTitle('Mes gains');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [allMissions, setAllMissions] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(0);
  const PAGE_SIZE = 50;
  const [moisFiltre, setMoisFiltre] = useState('CE_MOIS');
  const [modalAttestation, setModalAttestation] = useState(false);
  const [cotisationsMissionId, setCotisationsMissionId] = useState<string | null>(null);
  const [soignant, setSoignant] = useState<any>(null);
  const [paiementsMap, setPaiementsMap] = useState<Record<string, any>>({});
  const [recherche, setRecherche] = useState('');

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const [{ data: ms }, { data: sg }, { data: paiements }] = await Promise.all([
        supabase
          .from('missions')
          .select('id, intitule, debut_le, fin_le, duree_heures, taux_horaire_base, net_a_payer, net_estime, total_brut, statut, etablissement_id, service')
          .eq('soignant_assigne_id', user.id)
          .eq('statut', 'TERMINEE')
          .order('debut_le', { ascending: false })
          .range(0, (page + 1) * PAGE_SIZE - 1),
        supabase.from('soignants').select('type_exercice, statut_liberal').eq('id', user.id).maybeSingle(),
        supabase.from('paiements_soignant' as any)
          .select('mission_id, statut, montant_net, methode, reference_virement, date_paiement')
          .eq('soignant_id', user.id) as any,
      ]);
      const enriched = ms ? await enrichirEtablissements(ms as any) : [];
      if (page === 0) setAllMissions(enriched as any[]);
      else setAllMissions(prev => [...prev, ...enriched as any[]]);
      setSoignant(sg);

      // Index paiements by mission_id
      const map: Record<string, any> = {};
      (paiements || []).forEach((p: any) => { if (p.mission_id) map[p.mission_id] = p; });
      setPaiementsMap(map);

      setLoading(false);

      supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
        p_action: 'DONNEES_PERSO_CONSULTATION',
        p_type_ressource: 'soignant', p_id_ressource: user.id,
        p_cle_s3: null, p_details: { page: 'mes_gains' },
        p_ip: null, p_navigateur: navigator.userAgent,
      }).then(undefined, (err) => handleErrorSilent(err, 'MesGains.audit'));
    };
    load();
  }, [user, page]);

  const moisDisponibles = useMemo(() => {
    const set = new Set<string>();
    allMissions.forEach(m => {
      if (typeof m.debut_le === 'string' && m.debut_le.length >= 7) {
        set.add(m.debut_le.substring(0, 7));
      }
    });
    return Array.from(set).sort().reverse();
  }, [allMissions]);

  const missions = useMemo(() => {
    if (moisFiltre === 'TOUS') return allMissions;
    if (moisFiltre === 'CE_MOIS') {
      const prefix = new Date().toISOString().substring(0, 7);
      return allMissions.filter(m => typeof m.debut_le === 'string' && m.debut_le.startsWith(prefix));
    }
    return allMissions.filter(m => typeof m.debut_le === 'string' && m.debut_le.startsWith(moisFiltre));
  }, [allMissions, moisFiltre]);

  const totalNetFiltre = useMemo(() => missions.reduce((s, m) => s + (netEstime(m) ?? 0), 0), [missions]);
  const totalBrutFiltre = useMemo(() => missions.reduce((s, m) => s + (Number(m.total_brut) || 0), 0), [missions]);
  const totalNetToutTemps = useMemo(() => allMissions.reduce((s, m) => s + (netEstime(m) ?? 0), 0), [allMissions]);
  const totalHeures = useMemo(() => missions.reduce((s, m) => s + (Number(m.duree_heures) || 0), 0), [missions]);
  const tauxMoyen = useMemo(() => {
    if (totalHeures === 0) return 0;
    return totalBrutFiltre / totalHeures;
  }, [totalBrutFiltre, totalHeures]);

  const labelPeriode = moisFiltre === 'CE_MOIS'
    ? format(new Date(), 'MMMM yyyy', { locale: fr })
    : moisFiltre === 'TOUS'
      ? 'Tout temps'
      : format(new Date(moisFiltre + '-01'), 'MMMM yyyy', { locale: fr });

  const isLiberal = soignant?.type_exercice === 'LIBERAL' || soignant?.statut_liberal === 'ACTIF';

  const exporterCSV = () => {
    const header = 'Date,Mission,Service,Établissement,Heures,Taux horaire,Brut,Net estimé\n';
    const rows = missions.map(m => {
      const net = netEstime(m) ?? 0;
      const dateStr = m.debut_le ? format(new Date(m.debut_le), 'dd/MM/yyyy') : '—';
      const brut = Number(m.total_brut) || 0;
      return `${dateStr},"${(m.intitule || '').replace(/"/g, '""')}","${(m.service || '').replace(/"/g, '""')}","${(m.etablissements?.nom || '').replace(/"/g, '""')}",${Number(m.duree_heures) || 0},${Number(m.taux_horaire_base) || 0},${brut.toFixed(2)},${net.toFixed(2)}`;
    }).join('\n');
    const blob = new Blob([header + rows], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = `gains-jolene-${moisFiltre === 'CE_MOIS' ? new Date().toISOString().slice(0, 7) : moisFiltre}-${new Date().toISOString().slice(0, 10)}.csv`; a.click();
    URL.revokeObjectURL(url);
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground">💰 Mes gains</h1>
        <p className="text-sm text-muted-foreground mt-1">Visualisez vos revenus en un coup d'œil</p>
      </div>

      <BandeauPaiementDeclare />

      {/* KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <CarteKPI icone={Banknote} valeur={fmt(totalNetFiltre)} label={`Net estimé* · ${labelPeriode}`} couleurIcone="text-primary" couleurFond="bg-primary/10" lien="/soignant/mes-factures-honoraires" />
        <CarteKPI icone={TrendingUp} valeur={fmt(totalBrutFiltre)} label={`Brut · ${labelPeriode}`} couleurIcone="text-foreground" couleurFond="bg-muted" lien="/soignant/mes-factures-honoraires" />
        <CarteKPI icone={Clock} valeur={`${totalHeures}h`} label={`${missions.length} mission${missions.length > 1 ? 's' : ''}`} couleurIcone="text-info" couleurFond="bg-info/10" lien="/soignant/historique-missions" />
        <CarteKPI icone={TrendingUp} valeur={fmt(totalNetToutTemps)} label="Total tout temps" couleurIcone="text-success" couleurFond="bg-success/10" lien="/soignant/mes-factures-honoraires" />
      </div>

      {/* Graphique 6 mois */}
      <Suspense fallback={<div className="h-64 animate-pulse bg-muted rounded-lg" />}>
        <GraphiqueGains6Mois missions={allMissions.map(m => ({ debut_le: m.debut_le, net_a_payer: netEstime(m) }))} />
      </Suspense>

      {/* Filtre + Actions */}
      <div className="flex items-center gap-2 mb-4 flex-wrap">
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
          <Download className="h-4 w-4" /> CSV
        </Button>
        <Button variant="outline" size="sm" onClick={() => setModalAttestation(true)} className="gap-1.5">
          <FileText className="h-4 w-4" /> Attestation
        </Button>
        {isLiberal && (
          <Button variant="outline" size="sm" onClick={() => navigate('/soignant/charges')} className="gap-1.5">
            <Calculator className="h-4 w-4" /> Mes charges
          </Button>
        )}
      </div>

      {/* Récap période */}
      {missions.length > 0 && (
        <div className="rounded-xl border border-primary/20 bg-primary/5 p-4 mb-4">
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Récapitulatif · <strong className="text-foreground">{labelPeriode}</strong></span>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mt-3 text-xs">
            <div>
              <span className="text-muted-foreground">Missions</span>
              <p className="font-bold text-foreground">{missions.length}</p>
            </div>
            <div>
              <span className="text-muted-foreground">Heures</span>
              <p className="font-bold text-foreground">{totalHeures}h</p>
            </div>
            <div>
              <span className="text-muted-foreground">Taux moyen</span>
              <p className="font-bold text-foreground">{tauxMoyen.toFixed(2)} €/h</p>
            </div>
            <div>
              <span className="text-muted-foreground">Cotisations estimées</span>
              <p className="font-bold text-foreground">~{fmt(totalBrutFiltre - totalNetFiltre)}</p>
            </div>
          </div>
        </div>
      )}

      <p className="text-[10px] text-muted-foreground italic mb-3">
        * Estimation après cotisations salariales (~22%). Seuls les montants calculés par le moteur de paie font foi.
      </p>

      {/* Recherche */}
      {allMissions.length > 5 && (
        <div className="relative mb-3">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <input
            type="text"
            value={recherche}
            onChange={e => setRecherche(e.target.value)}
            placeholder="Rechercher une mission, un établissement..."
            className="input-base pl-9 text-sm py-2"
          />
        </div>
      )}

      {/* Liste missions */}
      {missions.length > 0 ? (
        <div className="space-y-2">
          {missions.filter(m => {
            if (!recherche.trim()) return true;
            const q = recherche.toLowerCase();
            return (m.intitule || '').toLowerCase().includes(q)
              || (m.etablissements?.nom || '').toLowerCase().includes(q)
              || (m.service || '').toLowerCase().includes(q);
          }).map(m => {
            const net = netEstime(m);
            const duree = m.duree_heures ?? ((new Date(m.fin_le).getTime() - new Date(m.debut_le).getTime()) / 3600000);
            return (
              <div
                key={m.id}
                role="button"
                tabIndex={0}
                aria-label={`Voir mission ${m.intitule || ''}`}
                className="rounded-xl border border-border hover:border-primary/30 hover:bg-muted/20 transition-all cursor-pointer overflow-hidden focus:outline-none focus:ring-2 focus:ring-primary"
                onClick={() => navigate(`/soignant/presences/mission/${m.id}`)}
                onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); navigate(`/soignant/presences/mission/${m.id}`); } }}
              >
                <div className="flex items-center gap-3 py-3 px-4">
                  {/* Date compact */}
                  <div className="flex flex-col items-center justify-center rounded-lg bg-muted/50 px-2.5 py-1 min-w-[44px]">
                    <span className="text-[10px] font-semibold text-muted-foreground uppercase">{format(new Date(m.debut_le), 'EEE', { locale: fr })}</span>
                    <span className="text-base font-bold text-foreground leading-tight">{format(new Date(m.debut_le), 'd')}</span>
                    <span className="text-[10px] text-muted-foreground">{format(new Date(m.debut_le), 'MMM', { locale: fr })}</span>
                  </div>
                  {/* Mission info */}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground truncate">{m.intitule}</p>
                    <p className="text-xs text-muted-foreground">
                      🏥 {m.etablissements?.nom || '—'}
                      {m.service && ` · ${m.service}`}
                    </p>
                    <div className="flex items-center gap-3 mt-0.5 text-[11px] text-muted-foreground">
                      <span>{format(new Date(m.debut_le), "HH'h'mm", { locale: fr })} → {format(new Date(m.fin_le), "HH'h'mm", { locale: fr })}</span>
                      <span>{Math.round(duree * 10) / 10}h</span>
                      <span>{m.taux_horaire_base} €/h</span>
                    </div>
                  </div>
                  {/* Net amount + payment status */}
                  <div className="text-right shrink-0 ml-2">
                    <button
                      className="text-primary font-bold text-sm hover:underline"
                      onClick={(e) => { e.stopPropagation(); setCotisationsMissionId(m.id); }}
                      aria-label="Voir le détail des cotisations"
                    >
                      {fmt(net)}
                    </button>
                    {m.total_brut != null && (
                      <p className="text-[10px] text-muted-foreground">brut : {fmt(m.total_brut)}</p>
                    )}
                    {(() => {
                      const p = paiementsMap[m.id];
                      if (!p) return <p className="text-[10px] text-muted-foreground/50">En attente</p>;
                      if (p.statut === 'CONFIRME') return <p className="text-[10px] text-success flex items-center justify-end gap-0.5"><CheckCircle className="h-3 w-3" />Payé</p>;
                      if (p.statut === 'DECLARE') return <p className="text-[10px] text-warning flex items-center justify-end gap-0.5"><AlertTriangle className="h-3 w-3" />À confirmer</p>;
                      if (p.statut === 'CONTESTE') return <p className="text-[10px] text-destructive flex items-center justify-end gap-0.5"><AlertTriangle className="h-3 w-3" />Contesté</p>;
                      if (p.statut === 'RESOLU') return <p className="text-[10px] text-muted-foreground flex items-center justify-end gap-0.5"><Scale className="h-3 w-3" />Litige résolu</p>;
                      return <p className="text-[10px] text-muted-foreground">{p.statut}</p>;
                    })()}
                  </div>
                </div>
              </div>
            );
          })}
          {allMissions.length === (page + 1) * PAGE_SIZE && (
            <button onClick={() => setPage(p => p + 1)} className="btn-secondary w-full mt-4">Charger plus de missions</button>
          )}
        </div>
      ) : (
        <EmptyState illustration={<IllustrationTirelire />} titre="Pas encore de gains" description="Vos gains apparaîtront ici après votre première mission terminée." />
      )}

      <ModalAttestation open={modalAttestation} onClose={() => setModalAttestation(false)} />
      <ModalCotisations missionId={cotisationsMissionId} open={!!cotisationsMissionId} onClose={() => setCotisationsMissionId(null)} />
    </LayoutApp>
  );
}
