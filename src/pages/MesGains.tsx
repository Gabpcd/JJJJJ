import { useState, useEffect, useMemo, Suspense } from 'react';
import { lazyRetry as lazy } from '@/lib/lazyRetry';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAffacturageActif } from '@/hooks/useAffacturageActif';
import { Banknote, Clock, Download, TrendingUp, ChevronRight, Calculator, FileText, Search, CheckCircle, AlertTriangle, Scale, Receipt, Zap, CreditCard } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MesFacturesHonorairesContent } from './MesFacturesHonoraires';
import { BulletinsPaieContent } from './BulletinsPaie';
import { MesAvancesContent } from './MesAvances';
import { RappelsFiscaux } from '@/components/RappelsFiscaux';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
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
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { telechargerOuPartager } from '@/lib/telechargement';

function fmt(v: number | null | undefined) {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

function netEstime(m: any): number | null {
  return m.net_estime ?? (m.net_a_payer != null ? m.net_a_payer * 0.78 : (m.total_brut != null ? m.total_brut * 0.78 : null));
}

export function MesGainsApercuContent() {
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

  // Prochain paiement attendu : missions terminées non encore confirmées payées.
  // Dérivé des données existantes (allMissions + paiementsMap) — aucune requête en plus.
  const prochainPaiement = useMemo(() => {
    const enAttente = allMissions.filter(m => {
      const p = paiementsMap[m.id];
      // Pas encore payé/confirmé → en attente de règlement
      return !p || (p.statut !== 'CONFIRME' && p.statut !== 'RESOLU');
    });
    if (enAttente.length === 0) return null;
    const montant = enAttente.reduce((s, m) => s + (netEstime(m) ?? 0), 0);
    if (montant <= 0) return null;
    // Date de la mission la plus ancienne en attente (point de départ du règlement)
    const dates = enAttente
      .map(m => (typeof m.fin_le === 'string' ? new Date(m.fin_le) : null))
      .filter((d): d is Date => d != null && !isNaN(d.getTime()))
      .sort((a, b) => a.getTime() - b.getTime());
    return { montant, nbMissions: enAttente.length, prochaineDate: dates[0] ?? null };
  }, [allMissions, paiementsMap]);

  const exporterCSV = () => {
    const header = 'Date,Mission,Service,Établissement,Heures,Taux horaire,Brut,Net estimé\n';
    const rows = missions.map(m => {
      const net = netEstime(m) ?? 0;
      const dateStr = m.debut_le ? format(new Date(m.debut_le), 'dd/MM/yyyy') : '—';
      const brut = Number(m.total_brut) || 0;
      return `${dateStr},"${(m.intitule || '').replace(/"/g, '""')}","${(m.service || '').replace(/"/g, '""')}","${(m.etablissements?.nom || '').replace(/"/g, '""')}",${Number(m.duree_heures) || 0},${Number(m.taux_horaire_base) || 0},${brut.toFixed(2)},${net.toFixed(2)}`;
    }).join('\n');
    const nom = `gains-jolene-${moisFiltre === 'CE_MOIS' ? new Date().toISOString().slice(0, 7) : moisFiltre}-${new Date().toISOString().slice(0, 10)}.csv`;
    void telechargerOuPartager(header + rows, nom, 'text/csv');
  };

  if (loading) return <ChargementPage />;

  return (
    <>
      <BandeauPaiementDeclare />

      {/* Prochain paiement attendu — synthèse en tête (Session G2) */}
      {prochainPaiement && (
        <div className="rounded-2xl border border-jolene-rose-200/60 bg-gradient-soft p-4 mb-6">
          <div className="flex items-center gap-2 mb-1">
            <Clock className="h-4 w-4 text-primary" />
            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Prochain paiement attendu</p>
          </div>
          <p className="text-2xl font-bold text-foreground">{fmt(prochainPaiement.montant)}</p>
          <p className="text-sm text-muted-foreground mt-0.5">
            {prochainPaiement.nbMissions} mission{prochainPaiement.nbMissions > 1 ? 's' : ''} en attente de règlement
            {prochainPaiement.prochaineDate && ` · à partir du ${format(prochainPaiement.prochaineDate, 'd MMMM yyyy', { locale: fr })}`}
          </p>
          <p className="text-[10px] text-muted-foreground italic mt-1">
            Montant net estimé. Le règlement intervient après validation des présences par l'établissement.
          </p>
        </div>
      )}

      {/* Rappels fiscaux libéral — remontés ici (Aperçu) depuis l'ancien onglet
          Gains du Dashboard : c'est leur place, près des revenus. */}
      {isLiberal && (
        <div className="mb-6">
          <RappelsFiscaux />
        </div>
      )}

      {/* Parrainage au moment de la satisfaction (gains affichés) — levier viral */}
      <button
        onClick={() => { window.location.href = '/soignant/parrainage'; }}
        className="w-full mb-6 rounded-2xl border border-jolene-rose-200/60 bg-gradient-soft p-4 text-left hover:shadow-md transition-shadow"
      >
        <p className="font-semibold text-foreground">🎁 Tu aimes Jolene ? Parraine un collègue</p>
        <p className="text-sm text-muted-foreground mt-0.5">
          Une prime pour toi, une prime pour lui dès sa première mission terminée. Ton lien est prêt — partage-le en 1 clic.
        </p>
      </button>

      {/* KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <CarteKPIY2K
          icone={<Banknote className="h-4 w-4" />}
          valeur={fmt(totalNetFiltre)}
          label={`Net estimé* · ${labelPeriode}`}
          variant="holographic"
          onClick={() => navigate('/soignant/mes-gains?tab=factures')}
        />
        <CarteKPIY2K
          icone={<TrendingUp className="h-4 w-4" />}
          valeur={fmt(totalBrutFiltre)}
          label={`Brut · ${labelPeriode}`}
          variant="default"
          onClick={() => navigate('/soignant/mes-gains?tab=factures')}
        />
        <CarteKPIY2K
          icone={<Clock className="h-4 w-4" />}
          valeur={`${totalHeures}h`}
          label={`${missions.length} mission${missions.length > 1 ? 's' : ''}`}
          variant="default"
          onClick={() => navigate('/soignant/historique-missions')}
        />
        <CarteKPIY2K
          icone={<TrendingUp className="h-4 w-4" />}
          valeur={fmt(totalNetToutTemps)}
          label="Total tout temps"
          variant="soft"
          onClick={() => navigate('/soignant/mes-gains?tab=factures')}
        />
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
        <BoutonY2K variant="secondary" size="sm" onClick={exporterCSV} className="gap-1.5">
          <Download className="h-4 w-4" /> CSV
        </BoutonY2K>
        <BoutonY2K variant="secondary" size="sm" onClick={() => setModalAttestation(true)} className="gap-1.5">
          <FileText className="h-4 w-4" /> Attestation
        </BoutonY2K>
        {isLiberal && (
          <BoutonY2K variant="secondary" size="sm" onClick={() => navigate('/soignant/charges')} className="gap-1.5">
            <Calculator className="h-4 w-4" /> Mes charges
          </BoutonY2K>
        )}
        {/* Liens de confort vers les pages setup paiement (sinon seulement dans la nav). */}
        {soignant?.type_exercice !== 'SALARIE' && (
          <BoutonY2K variant="secondary" size="sm" onClick={() => navigate('/soignant/stripe-connect')} className="gap-1.5">
            <CreditCard className="h-4 w-4" /> Compte de paiement
          </BoutonY2K>
        )}
        {(soignant?.type_exercice === 'LIBERAL' || soignant?.type_exercice === 'MIXTE') && (
          <BoutonY2K variant="secondary" size="sm" onClick={() => navigate('/soignant/mandat-facturation')} className="gap-1.5">
            <FileText className="h-4 w-4" /> Mandat de facturation
          </BoutonY2K>
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
            aria-label="Rechercher une mission ou un établissement"
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
                    <p className="text-sm font-medium text-foreground truncate" title={m.intitule}>{m.intitule}</p>
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
        <EmptyState illustration={<IllustrationTirelire />} titre="Pas encore de gains" description="Tes gains apparaîtront ici après ta première mission terminée." cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }} />
      )}

      <ModalAttestation open={modalAttestation} onClose={() => setModalAttestation(false)} />
      <ModalCotisations missionId={cotisationsMissionId} open={!!cotisationsMissionId} onClose={() => setCotisationsMissionId(null)} />
    </>
  );
}

/* ── Session G2 : hub « Mes finances » ──
   Consolide en un seul écran les 4 anciennes pages argent du soignant :
   Aperçu (gains), Factures d'honoraires (libéral), Bulletins de paie (salarié),
   Avances (paiement rapide, libéral/mixte). Les onglets sont synchronisés via
   ?tab= pour préserver les liens profonds. Aucune logique métier / PDF / RPC
   n'est réécrite : chaque onglet compose le `Content` extrait de l'ancienne page. */
const TABS_FINANCES = ['apercu', 'factures', 'bulletins', 'avances'] as const;
type TabFinance = typeof TABS_FINANCES[number];

export default function MesGains() {
  usePageTitle('Revenus');
  const { user } = useAuth();
  const [searchParams, setSearchParams] = useSearchParams();
  const [exercice, setExercice] = useState<{ type: string | null; liberalActif: boolean } | null>(null);
  // Affacturage Defacto pas en prod → onglet « Avances » masqué tant que le flag
  // affacturage_actif est off (défaut). Flippable à chaud côté param système.
  const affacturageActif = useAffacturageActif();

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants').select('type_exercice, statut_liberal').eq('id', user.id).maybeSingle()
      .then(({ data }) => {
        setExercice({
          type: (data as any)?.type_exercice ?? null,
          liberalActif: (data as any)?.statut_liberal === 'ACTIF',
        });
      }, (err) => { handleErrorSilent(err, 'MesGains.hub.exercice'); setExercice({ type: null, liberalActif: false }); });
  }, [user]);

  // Tant que le statut n'est pas chargé (exercice == null), on reste permissif et
  // on affiche tous les onglets : un lien profond ?tab=factures fonctionne dès le
  // premier rendu. Une fois le type connu, on masque les onglets non pertinents
  // (ex. Bulletins pour un libéral pur, Factures/Avances pour un salarié pur).
  const type = exercice?.type ?? null;
  const estLiberal = type === 'LIBERAL' || type === 'MIXTE' || exercice?.liberalActif === true;
  const estSalarie = type === 'SALARIE' || type === 'MIXTE' || (type == null ? false : !estLiberal);
  // Si le type est inconnu (null) on reste permissif : on garde l'onglet ciblé par
  // ?tab= accessible afin de ne jamais casser un lien profond.
  const showFactures = estLiberal || (exercice == null);
  const showBulletins = estSalarie || (type == null && exercice != null) || (exercice == null);
  // Avances = affacturage Defacto → uniquement si le flag est actif.
  const showAvances = (estLiberal || (exercice == null)) && affacturageActif;

  const tabParam = searchParams.get('tab');
  const wanted = TABS_FINANCES.includes(tabParam as TabFinance) ? (tabParam as TabFinance) : 'apercu';
  // Si l'onglet demandé est masqué pour ce profil, on retombe sur l'Aperçu.
  const visible: Record<TabFinance, boolean> = {
    apercu: true,
    factures: showFactures,
    bulletins: showBulletins,
    avances: showAvances,
  };
  const currentTab: TabFinance = visible[wanted] ? wanted : 'apercu';

  const nbTabs = 1 + Number(showFactures) + Number(showBulletins) + Number(showAvances);
  // Classes statiques (JIT Tailwind ne purge pas une interpolation dynamique).
  const gridColsClass = nbTabs === 4 ? 'grid-cols-4' : nbTabs === 3 ? 'grid-cols-3' : nbTabs === 2 ? 'grid-cols-2' : 'grid-cols-1';

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-4">
        <h1 className="text-xl font-bold text-foreground">💰 Revenus</h1>
        <p className="text-sm text-muted-foreground mt-1">{affacturageActif ? 'Tes gains, factures, bulletins et avances au même endroit' : 'Tes gains, factures et bulletins au même endroit'}</p>
      </div>

      <Tabs value={currentTab} onValueChange={(v) => setSearchParams({ tab: v }, { replace: true })}>
        <TabsList className={`grid w-full mb-4 ${gridColsClass}`}>
          <TabsTrigger value="apercu" className="flex items-center gap-1.5 text-xs sm:text-sm">
            <Banknote className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
            <span>Aperçu</span>
          </TabsTrigger>
          {showFactures && (
            <TabsTrigger value="factures" className="flex items-center gap-1.5 text-xs sm:text-sm">
              <FileText className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
              <span>Factures</span>
            </TabsTrigger>
          )}
          {showBulletins && (
            <TabsTrigger value="bulletins" className="flex items-center gap-1.5 text-xs sm:text-sm">
              <Receipt className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
              <span>Bulletins</span>
            </TabsTrigger>
          )}
          {showAvances && (
            <TabsTrigger value="avances" className="flex items-center gap-1.5 text-xs sm:text-sm">
              <Zap className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
              <span>Avances</span>
            </TabsTrigger>
          )}
        </TabsList>

        <TabsContent value="apercu" className="mt-0">
          <MesGainsApercuContent />
        </TabsContent>

        {showFactures && (
          <TabsContent value="factures" className="mt-0">
            <MesFacturesHonorairesContent />
          </TabsContent>
        )}

        {showBulletins && (
          <TabsContent value="bulletins" className="mt-0">
            <BulletinsPaieContent />
          </TabsContent>
        )}

        {showAvances && (
          <TabsContent value="avances" className="mt-0">
            <MesAvancesContent />
          </TabsContent>
        )}
      </Tabs>
    </LayoutApp>
  );
}
