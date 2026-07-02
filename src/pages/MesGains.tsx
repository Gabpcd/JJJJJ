import { useState, useEffect, useMemo, Suspense } from 'react';
import { lazyRetry as lazy } from '@/lib/lazyRetry';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAffacturageActif } from '@/hooks/useAffacturageActif';
import { Banknote, Clock, Download, TrendingUp, ChevronRight, FileText, Search, CheckCircle, AlertTriangle, Scale, Receipt, Zap, Calculator } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MesFacturesHonorairesContent } from './MesFacturesHonoraires';
import { BulletinsPaieContent } from './BulletinsPaie';
import { MesAvancesContent } from './MesAvances';
import { RappelsFiscaux } from '@/components/RappelsFiscaux';
import { NoteNetEstime } from '@/components/NoteNetEstime';
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
  const [facturesMap, setFacturesMap] = useState<Record<string, any>>({});
  const [recherche, setRecherche] = useState('');

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const [{ data: ms }, { data: sg }, { data: paiements }, { data: facts }] = await Promise.all([
        supabase
          .from('missions')
          .select('id, intitule, debut_le, fin_le, duree_heures, taux_horaire_base, net_a_payer, net_estime, total_brut, statut, etablissement_id, service, type_contrat_applique')
          .eq('soignant_assigne_id', user.id)
          .eq('statut', 'TERMINEE')
          .order('debut_le', { ascending: false })
          .range(0, (page + 1) * PAGE_SIZE - 1),
        supabase.from('soignants').select('type_exercice, statut_liberal, regime_fiscal, regime_fiscal_confirme' as any).eq('id', user.id).maybeSingle(),
        supabase.from('paiements_soignant' as any)
          .select('mission_id, statut, montant_net, methode, reference_virement, date_paiement')
          .eq('soignant_id', user.id) as any,
        // 6d.1 : MÊME source que l'onglet Factures — l'Aperçu et Factures ne
        // peuvent plus diverger (l'écart « 234 € en attente » vs « 0 € »).
        supabase.rpc('fn_mes_factures_honoraires' as any),
      ]);
      const enriched = ms ? await enrichirEtablissements(ms as any) : [];
      if (page === 0) setAllMissions(enriched as any[]);
      else setAllMissions(prev => [...prev, ...enriched as any[]]);
      setSoignant(sg);

      // Index paiements by mission_id
      const map: Record<string, any> = {};
      (paiements || []).forEach((p: any) => { if (p.mission_id) map[p.mission_id] = p; });
      setPaiementsMap(map);

      const fmap: Record<string, any> = {};
      ((facts || []) as any[]).forEach((f: any) => { if (f.mission_id) fmap[f.mission_id] = f; });
      setFacturesMap(fmap);

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
  // D3 : profil 100 % salarié — le net exact vient du bulletin de paie de
  // l'établissement employeur, et Jolene ne verse RIEN (placement, pas payeur).
  // On ne montre donc ni estimation ~22 % ni promesse de versement Jolene.
  const isSalariePur = !isLiberal && soignant?.type_exercice !== 'MIXTE';

  // Régime PAR MISSION (jamais par soignant). Un Mixte ne mélange pas honoraires
  // libéraux (charges URSSAF/CARPIMKO annualisées, PAS prélevées à la transaction)
  // et net salarié (~−22 % cotisations). type_contrat_applique NULL = non déterminé.
  const libMissions = useMemo(() => missions.filter(m => m.type_contrat_applique === 'LIBERAL'), [missions]);
  const salMissions = useMemo(() => missions.filter(m => m.type_contrat_applique === 'SALARIE'), [missions]);
  const indetCount = useMemo(() => missions.filter(m => !m.type_contrat_applique).length, [missions]);
  // Libéral : honoraires réellement encaissés (après commission Jolene), PAS ×0,78.
  const honorairesLib = useMemo(() => libMissions.reduce((s, m) => s + (m.net_estime ?? m.net_a_payer ?? Number(m.total_brut) ?? 0), 0), [libMissions]);
  // Salarié : net estimé après cotisations salariales (~22 %).
  const netSal = useMemo(() => salMissions.reduce((s, m) => s + (netEstime(m) ?? 0), 0), [salMissions]);

  // 6d.1 — Pipeline UNIQUE « À valider → En attente de paiement → Payé ».
  // Mêmes sources que l'onglet Factures (fn_mes_factures_honoraires) + paiements :
  // « facture émise » = présences validées côté flux de facturation. La confiance
  // paiement est LE facteur de conversion — plus jamais deux chiffres divergents.
  const pipeline = useMemo(() => {
    const etapes = {
      aValider: { montant: 0, nb: 0 },
      enAttente: { montant: 0, nb: 0 },
      paye: { montant: 0, nb: 0 },
    };
    allMissions.forEach(m => {
      const p = paiementsMap[m.id];
      const f = facturesMap[m.id];
      // Facture remboursée (litige/avoir) : sortie du pipeline, ni due ni payée.
      if (f && f.statut === 'REMBOURSE') return;
      const montantDefaut = isSalariePur ? (Number(m.total_brut) || 0) : (netEstime(m) ?? 0);
      const paye = (p && (p.statut === 'CONFIRME' || p.statut === 'RESOLU'))
        || (f && (f.statut === 'PAYEE' || f.statut === 'FACTORISEE'));
      if (paye) {
        etapes.paye.montant += f ? Number(f.montant_ttc) || montantDefaut : montantDefaut;
        etapes.paye.nb += 1;
        return;
      }
      // Facture émise (= présences validées, en attente de règlement) OU
      // paiement déclaré non confirmé → « En attente de paiement ».
      if ((f && (f.statut === 'EMISE' || f.statut === 'EN_RETARD')) || p) {
        etapes.enAttente.montant += f ? Number(f.montant_ttc) || montantDefaut : montantDefaut;
        etapes.enAttente.nb += 1;
        return;
      }
      // Mission terminée, pas de facture, pas de paiement → validation des
      // présences par l'établissement encore en cours.
      etapes.aValider.montant += montantDefaut;
      etapes.aValider.nb += 1;
    });
    return etapes;
  }, [allMissions, paiementsMap, facturesMap, isSalariePur]);

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

      {/* 6d.1 — Pipeline unique : la SEULE histoire d'argent de l'Aperçu.
          Chaque étape a un montant ; « En attente » lit exactement les factures
          de l'onglet Factures (montants TTC identiques, plus de divergence). */}
      {(pipeline.aValider.nb + pipeline.enAttente.nb + pipeline.paye.nb) > 0 && (
        <div className="rounded-2xl border border-jolene-rose-200/60 bg-gradient-soft p-4 mb-6">
          <div className="flex items-center gap-2 mb-3">
            <Clock className="h-4 w-4 text-primary" />
            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              {isSalariePur ? 'Ta rémunération, étape par étape' : 'Ton paiement, étape par étape'}
            </p>
          </div>
          <div className="grid grid-cols-3 gap-2">
            {[
              {
                label: 'À valider',
                detail: 'présences côté étab',
                etape: pipeline.aValider,
                onClick: () => navigate('/soignant/presences'),
              },
              {
                label: 'En attente de paiement',
                detail: isSalariePur ? 'sur ta paie établissement' : 'facture émise',
                etape: pipeline.enAttente,
                onClick: () => navigate(isSalariePur ? '/soignant/mes-gains?tab=bulletins' : '/soignant/mes-gains?tab=factures'),
              },
              {
                label: 'Payé',
                detail: 'règlement confirmé',
                etape: pipeline.paye,
                onClick: () => navigate(isSalariePur ? '/soignant/mes-gains?tab=bulletins' : '/soignant/mes-gains?tab=factures'),
              },
            ].map(({ label, detail, etape, onClick }, i) => (
              <button
                key={label}
                type="button"
                onClick={onClick}
                className={`relative rounded-xl border p-2.5 text-left transition-colors min-h-[44px] ${
                  etape.nb > 0 ? 'border-jolene-rose-200 bg-card hover:border-jolene-rose-300' : 'border-border/60 bg-card/50 opacity-60'
                }`}
              >
                <p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground leading-tight">{label}</p>
                <p className={`text-base font-bold tabular-nums mt-0.5 ${i === 2 ? 'text-success' : 'text-foreground'}`}>
                  {fmt(etape.montant)}
                </p>
                <p className="text-[10px] text-muted-foreground leading-tight">
                  {etape.nb} mission{etape.nb > 1 ? 's' : ''} · {detail}
                </p>
              </button>
            ))}
          </div>
          <p className="text-[10px] text-muted-foreground italic mt-2">
            {isSalariePur
              ? 'Montants bruts. Le versement est effectué par l\'établissement employeur selon son calendrier de paie — Jolene ne verse pas cette somme.'
              : 'Montants nets estimés (TTC facturé pour les étapes facturées). Le règlement intervient après validation des présences par l\'établissement.'}
          </p>
        </div>
      )}

      {/* Rappels fiscaux libéral — remontés ici (Aperçu) depuis l'ancien onglet
          Gains du Dashboard : c'est leur place, près des revenus. */}
      {isLiberal && (
        <div className="mb-6">
          <RappelsFiscaux
            regimeFiscal={soignant?.regime_fiscal ?? 'MICRO_BNC'}
            regimeFiscalConfirme={soignant?.regime_fiscal_confirme === true}
          />
        </div>
      )}

      {/* §7.2 Lot 7a — banner parrainage permanent RETIRÉ de Revenus : cet écran a
          un seul job, la confiance paiement. Le parrainage vit dans Compte (entrée
          dédiée), en bas d'Accueil (carte discrète) et aux pics d'émotion (§5). */}

      {/* KPIs — séparés par régime (jamais de sous-bloc à zéro). Honoraires libéraux
          et net salarié ne sont pas le même concept : on ne les fusionne pas. */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
        {libMissions.length > 0 && (
          <CarteKPIY2K
            icone={<Banknote className="h-4 w-4" />}
            valeur={fmt(honorairesLib)}
            label={`Honoraires encaissés · ${labelPeriode}`}
            variant="holographic"
            onClick={() => navigate('/soignant/mes-gains?tab=factures')}
          />
        )}
        {/* D3 : salarié pur → PAS d'estimation ~22 % (le net exact vient du
            bulletin de paie de l'établissement) ; le Brut devient le KPI primaire. */}
        {!isSalariePur && salMissions.length > 0 && (
          <CarteKPIY2K
            icone={<Banknote className="h-4 w-4" />}
            valeur={fmt(netSal)}
            label={`Net salarié* · ${labelPeriode}`}
            variant={libMissions.length > 0 ? 'default' : 'holographic'}
            onClick={() => navigate('/soignant/mes-gains?tab=bulletins')}
          />
        )}
        {!isSalariePur && libMissions.length === 0 && salMissions.length === 0 && (
          <CarteKPIY2K
            icone={<Banknote className="h-4 w-4" />}
            valeur={fmt(totalNetFiltre)}
            label={`Net estimé* · ${labelPeriode}`}
            variant="holographic"
            onClick={() => navigate('/soignant/mes-gains?tab=factures')}
          />
        )}
        <CarteKPIY2K
          icone={<TrendingUp className="h-4 w-4" />}
          valeur={fmt(totalBrutFiltre)}
          label={`Brut · ${labelPeriode}`}
          variant={isSalariePur ? 'holographic' : 'default'}
          onClick={() => navigate(isSalariePur ? '/soignant/mes-gains?tab=bulletins' : '/soignant/mes-gains?tab=factures')}
        />
        <CarteKPIY2K
          icone={<Clock className="h-4 w-4" />}
          valeur={`${totalHeures}h`}
          label={`${missions.length} mission${missions.length > 1 ? 's' : ''}`}
          variant="default"
          onClick={() => navigate('/soignant/historique-missions')}
        />
        {/* 6d.1 : « Total tout temps » retiré de la grille (redondant avec le
            pipeline « Payé » et le graphique) — grille 2×2 compacte. */}
      </div>
      {isSalariePur ? (
        <p className="text-[11px] text-muted-foreground mb-6">
          💼 Montants bruts. Ton net exact figure sur ton <strong>bulletin de paie, fourni par
          l'établissement employeur</strong> — le versement suit son calendrier de paie.
        </p>
      ) : (
        <NoteNetEstime className="mb-6" />
      )}
      {indetCount > 0 && (
        <p className="text-xs text-muted-foreground mb-6">
          {indetCount} mission{indetCount > 1 ? 's' : ''} en cours de qualification de régime — non comptée{indetCount > 1 ? 's' : ''} ci-dessus.
        </p>
      )}
      {libMissions.length > 0 && (
        <p className="text-[11px] text-muted-foreground mb-6">
          👜 Honoraires libéraux = ce qui est encaissé. Les charges URSSAF/CARPIMKO sont <strong>annualisées</strong> (provisionnées, pas prélevées à chaque mission) — voir <button onClick={() => navigate('/soignant/charges')} className="text-primary hover:underline">Mes charges</button>.
        </p>
      )}

      {/* 6d.1 : graphique seulement à partir de 2 mois de données — une barre
          seule = du bruit, pas une tendance. */}
      {moisDisponibles.length >= 2 && (
        <Suspense fallback={<div className="h-64 animate-pulse bg-muted rounded-lg" />}>
          <GraphiqueGains6Mois missions={allMissions.map(m => ({ debut_le: m.debut_le, net_a_payer: netEstime(m) }))} />
        </Suspense>
      )}

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
        {/* Charges sociales = INFO (charges du libéral) → sa place est ici, dans Revenus,
            nommée explicitement (retirée de Compte). Compte de paiement / Mandat restent
            en config dans Compte (source unique). */}
        {isLiberal && (
          <BoutonY2K variant="secondary" size="sm" onClick={() => navigate('/soignant/charges')} className="gap-1.5">
            <Calculator className="h-4 w-4" /> Mes charges
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
            {/* D3/§7.3 : salarié pur → pas d'estimation de prélèvements (le net
                exact vient du bulletin de l'employeur) ; on affiche le brut total. */}
            {isSalariePur ? (
              <div>
                <span className="text-muted-foreground">Brut total</span>
                <p className="font-bold text-foreground">{fmt(totalBrutFiltre)}</p>
              </div>
            ) : (
              <div>
                <span className="text-muted-foreground">Prélèvements estimés</span>
                <p className="font-bold text-foreground">~{fmt(totalBrutFiltre - totalNetFiltre)}</p>
              </div>
            )}
          </div>
        </div>
      )}

      <p className="text-[10px] text-muted-foreground italic mb-3">
        {salMissions.length > 0 && '* Net salarié estimé après cotisations salariales (~22 %). '}
        {libMissions.length > 0 && '* Honoraires libéraux hors charges URSSAF/CARPIMKO (annualisées). '}
        {libMissions.length === 0 && salMissions.length === 0 && '* Estimation après cotisations (~22 %). '}
        Seuls les montants calculés par le moteur de paie / la facture font foi.
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
      ) : allMissions.length === 0 ? (
        <EmptyState illustration={<IllustrationTirelire />} titre="Pas encore de gains" description="Tes gains apparaîtront ici après ta première mission terminée." cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }} />
      ) : (
        /* 6d.1 : historique existant mais période vide → message scopé, pas un
           grand état vide sous un pipeline/graphique qui montrent des gains. */
        <div className="card-base text-center py-6">
          <p className="text-sm font-medium text-foreground">
            Pas encore de gains {moisFiltre === 'CE_MOIS' ? 'ce mois-ci' : `sur ${labelPeriode}`}
          </p>
          <button
            onClick={() => setMoisFiltre('TOUS')}
            className="text-xs text-primary hover:underline mt-1"
          >
            Voir tout l'historique ({allMissions.length} mission{allMissions.length > 1 ? 's' : ''})
          </button>
        </div>
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
