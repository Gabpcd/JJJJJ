import { useState, useEffect, useMemo, Suspense } from 'react';
import { lazyRetry as lazy } from '@/lib/lazyRetry';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAffacturageActif } from '@/hooks/useAffacturageActif';
import { Banknote, Clock, Download, TrendingUp, ChevronRight, FileText, Search, CheckCircle, AlertTriangle, Scale, Receipt, Zap, Calculator, Landmark } from 'lucide-react';
import PaiementsEscrowAVenir from '@/components/gains/PaiementsEscrowAVenir';
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
import { promptParrainage } from '@/lib/prompt-parrainage';
import { montantFinanceAfficheMission } from '@/lib/missionFinanceDisplay';
import {
  enrichirFacturesHonoraires,
  factureEstAvoir,
  regrouperFacturesParMission,
  resumerFacturesMission,
} from '@/lib/factureHonorairesUi';
import { indexerDernierPaiementParMission } from '@/lib/paiementSoignantUi';
import { cleJourParis, cleMoisParis, formatParis } from '@/lib/date-heure-paris';
import { chargerCreneauxMissionsPagines, type CreneauMissionCharge } from '@/lib/mission-creneaux-pagines';
import { construireExportPaiePeriode } from '@/lib/export-paie-planning';

function fmt(v: number | null | undefined) {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export function MesGainsApercuContent() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [allMissions, setAllMissions] = useState<any[]>([]);
  const [creneauxMissions, setCreneauxMissions] = useState<CreneauMissionCharge[]>([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(0);
  const PAGE_SIZE = 50;
  const [moisFiltre, setMoisFiltre] = useState('CE_MOIS');
  const [modalAttestation, setModalAttestation] = useState(false);
  const [cotisationsMissionId, setCotisationsMissionId] = useState<string | null>(null);
  const [soignant, setSoignant] = useState<any>(null);
  const [paiementsMap, setPaiementsMap] = useState<Record<string, any>>({});
  const [facturesMap, setFacturesMap] = useState<Record<string, any[]>>({});
  const [recherche, setRecherche] = useState('');
  const [hasMore, setHasMore] = useState(false);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    if (!user) return;
    let actif = true;
    const load = async () => {
      setErreurChargement(null);
      setLoading(true);
      try {
        const [missionsResult, soignantResult, paiementsResult, facturesResult, metadonneesFacturesResult] = await Promise.all([
          supabase
            .from('missions')
            .select('id, intitule, debut_le, fin_le, duree_heures, nb_creneaux, taux_horaire_base, net_a_payer, net_estime, total_brut, statut, etablissement_id, service, type_contrat_applique, type_contrat_recherche, presences(valide_par_etablissement, valide_auto_72h_le, valide_le)')
            .eq('soignant_assigne_id', user.id)
            .eq('statut', 'TERMINEE')
            .order('debut_le', { ascending: false })
            .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1),
          supabase.from('soignants').select('type_exercice, statut_liberal, regime_fiscal, regime_fiscal_confirme' as any).eq('id', user.id).maybeSingle(),
          supabase.from('paiements_soignant' as any)
            .select('id, mission_id, facture_honoraire_id, statut, montant_net, methode, reference_virement, date_paiement, modifie_le, cree_le')
            .eq('soignant_id', user.id)
            .order('modifie_le', { ascending: false, nullsFirst: false })
            .order('cree_le', { ascending: false, nullsFirst: false })
            .order('date_paiement', { ascending: false, nullsFirst: false })
            .order('id', { ascending: false }) as any,
          // MÊME source que l'onglet Factures pour éviter les états divergents.
          supabase.rpc('fn_mes_factures_honoraires' as any),
          // Le RPC historique n'expose pas le type_document. Cette lecture RLS
          // empêche qu'un AVOIR `EMISE` soit interprété comme un revenu attendu.
          supabase
            .from('factures_honoraires')
            .select('id, type_document, montant_signe, cree_le, template_version, numero_semaine_iso, periode_debut, periode_fin, facture_precedente_id, date_remboursement')
            .eq('soignant_id', user.id),
        ]);
        if (missionsResult.error) throw missionsResult.error;
        if (soignantResult.error) throw soignantResult.error;
        if (paiementsResult.error) throw paiementsResult.error;
        if (facturesResult.error) throw facturesResult.error;
        if (metadonneesFacturesResult.error) throw metadonneesFacturesResult.error;

        const pageMissions = (missionsResult.data ?? []) as any[];
        const [enriched, creneauxPage] = await Promise.all([
          enrichirEtablissements(pageMissions as any),
          chargerCreneauxMissionsPagines(pageMissions.map((mission) => mission.id)),
        ]);
        if (!actif) return;
        setHasMore(pageMissions.length === PAGE_SIZE);
        if (page === 0) {
          setAllMissions(enriched as any[]);
          setCreneauxMissions(creneauxPage);
        } else {
          setAllMissions(prev => {
            const parId = new Map(prev.map(mission => [mission.id, mission]));
            (enriched as any[]).forEach(mission => parId.set(mission.id, mission));
            return Array.from(parId.values());
          });
          setCreneauxMissions(prev => {
            const parId = new Map(prev.map(creneau => [creneau.id, creneau]));
            creneauxPage.forEach(creneau => parId.set(creneau.id, creneau));
            return Array.from(parId.values());
          });
        }
        setSoignant(soignantResult.data);

        setPaiementsMap(indexerDernierPaiementParMission(
          (paiementsResult.data || []) as any[],
        ));

        const facturesEnrichies = enrichirFacturesHonoraires(
          (facturesResult.data || []) as any[],
          (metadonneesFacturesResult.data || []) as any[],
        );
        setFacturesMap(regrouperFacturesParMission(facturesEnrichies));

        supabase.rpc('fn_ecrire_audit_safe', {
          p_acteur_id: user.id, p_type_acteur: 'SOIGNANT',
          p_action: 'DONNEES_PERSO_CONSULTATION',
          p_type_ressource: 'soignant', p_id_ressource: user.id,
          p_cle_s3: null, p_details: { page: 'mes_gains' },
          p_ip: null, p_navigateur: navigator.userAgent,
        }).then(undefined, (err) => handleErrorSilent(err, 'MesGains.audit'));
      } catch (error: any) {
        if (!actif) return;
        setErreurChargement(error?.message || 'Impossible de charger les revenus.');
      } finally {
        if (actif) setLoading(false);
      }
    };
    void load();
    return () => { actif = false; };
  }, [user, page, reloadKey]);

  const moisDisponibles = useMemo(() => {
    const set = new Set<string>();
    const missionsAvecCreneaux = new Set(creneauxMissions.map(creneau => creneau.mission_id));
    creneauxMissions.forEach(creneau => {
      if (creneau.est_pause || !creneau.fin) return;
      set.add(cleMoisParis(creneau.debut));
      set.add(cleMoisParis(new Date(new Date(creneau.fin).getTime() - 1)));
    });
    allMissions.forEach(mission => {
      if (!missionsAvecCreneaux.has(mission.id) && mission.debut_le) {
        set.add(cleMoisParis(mission.debut_le));
      }
    });
    return Array.from(set).sort().reverse();
  }, [allMissions, creneauxMissions]);

  const missionsGraphique = useMemo(() => {
    try {
      return moisDisponibles.flatMap((cleMois) => {
        const [annee, mois] = cleMois.split('-').map(Number);
        return construireExportPaiePeriode(allMissions, creneauxMissions, annee, mois)
          .map((mission) => ({
            debut_le: `${cleMois}-15T12:00:00`,
            net_a_payer: montantFinanceAfficheMission(mission)?.montant ?? null,
          }));
      });
    } catch {
      // Un historique mensuel incomplet ne doit jamais produire une barre
      // financière approximative. Les pipelines facture/paiement restent
      // disponibles car ils reposent sur leurs propres périodes et statuts.
      return [];
    }
  }, [allMissions, creneauxMissions, moisDisponibles]);

  const periodeMissions = useMemo(() => {
    if (moisFiltre === 'TOUS') return { missions: allMissions, erreur: null as string | null };
    const cleMois = moisFiltre === 'CE_MOIS' ? cleMoisParis(new Date()) : moisFiltre;
    const [annee, mois] = cleMois.split('-').map(Number);
    try {
      return {
        missions: construireExportPaiePeriode(allMissions, creneauxMissions, annee, mois),
        erreur: null as string | null,
      };
    } catch (error: any) {
      return {
        missions: [] as any[],
        erreur: error?.message || 'Le planning exact de cette période ne peut pas être vérifié.',
      };
    }
  }, [allMissions, creneauxMissions, moisFiltre]);
  const missions = periodeMissions.missions;
  const erreurAffichee = erreurChargement ?? periodeMissions.erreur;

  const totalBrutFiltre = useMemo(() => missions.reduce((s, m) => s + (Number(m.total_brut) || 0), 0), [missions]);
  const totalHeures = useMemo(() => missions.reduce((s, m) => s + (Number(m.duree_heures) || 0), 0), [missions]);
  const tauxMoyen = useMemo(() => {
    if (totalHeures === 0) return 0;
    return totalBrutFiltre / totalHeures;
  }, [totalBrutFiltre, totalHeures]);

  const labelPeriode = moisFiltre === 'CE_MOIS'
      ? format(new Date(), 'MMMM yyyy', { locale: fr })
      : moisFiltre === 'TOUS'
        ? 'Tout temps'
        : formatParis(`${moisFiltre}-01T12:00:00`, 'MMMM yyyy');

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
  // Libéral : honoraires bruts dus au soignant, sans retenue de commission Jolene, PAS ×0,78.
  const honorairesLib = useMemo(() => libMissions.reduce((s, m) => s + (montantFinanceAfficheMission(m)?.montant ?? 0), 0), [libMissions]);
  // Salarié : net estimé après cotisations salariales (~22 %).
  const netSal = useMemo(() => salMissions.reduce((s, m) => s + (montantFinanceAfficheMission(m)?.montant ?? 0), 0), [salMissions]);

  // 6d.1 — Pipeline UNIQUE « À valider → En attente de paiement → Payé ».
  // Mêmes sources que l'onglet Factures (fn_mes_factures_honoraires) + paiements :
  // « facture émise » = présences validées côté flux de facturation. La confiance
  // paiement est LE facteur de conversion — plus jamais deux chiffres divergents.
  const pipeline = useMemo(() => {
    const etapes = {
      // 9.1 — aValider.ids : liste des missions comptées (pour la règle singleton
      // du deep link : 1 seule → détail mission direct).
      aValider: { montant: 0, nb: 0, ids: [] as string[] },
      enAttente: { montant: 0, nb: 0 },
      paye: { montant: 0, nb: 0, nbFactures: 0, nbPaiements: 0 },
    };

    // Les factures hebdomadaires peuvent exister avant que la mission longue
    // passe à TERMINEE. On part donc de toutes les factures du RPC, pas seulement
    // des missions terminées actuellement chargées/paginées.
    Object.values(facturesMap).forEach((documents) => {
      const resume = resumerFacturesMission(documents);
      etapes.paye.montant += resume.montantPaye;
      etapes.paye.nb += resume.nbPayees;
      etapes.paye.nbFactures += resume.nbPayees;
      etapes.enAttente.montant += resume.montantEnAttente;
      etapes.enAttente.nb += resume.nbEnAttente;
    });

    allMissions.forEach(m => {
      const p = paiementsMap[m.id];
      const documents = facturesMap[m.id] ?? [];
      const resumeFactures = resumerFacturesMission(documents);
      const finance = montantFinanceAfficheMission(m);
      const montantDefaut = finance?.montant ?? 0;
      const montantPaiement = Number(p?.montant_net) || montantDefaut;

      // Déjà agrégé ci-dessus facture par facture (y compris mission longue
      // encore en cours) : ne jamais recompter via le paiement de mission.
      if (resumeFactures.nbFacturesValides > 0) return;

      const paye = p && (p.statut === 'CONFIRME' || p.statut === 'RESOLU');
      if (paye) {
        etapes.paye.montant += montantPaiement;
        etapes.paye.nb += 1;
        etapes.paye.nbPaiements += 1;
        return;
      }
      // Paiement déclaré non confirmé → « En attente de paiement ».
      if (p) {
        etapes.enAttente.montant += montantPaiement;
        etapes.enAttente.nb += 1;
        return;
      }
      // Un document financier non comptabilisable (notamment un AVOIR ou une
      // erreur de génération) ne redevient pas artificiellement une paie à valider.
      if (documents.length > 0) return;
      // Mission terminée, pas de facture, pas de paiement → validation des
      // présences par l'établissement encore en cours.
      etapes.aValider.montant += montantDefaut;
      etapes.aValider.nb += 1;
      etapes.aValider.ids.push(m.id);
    });
    return etapes;
  }, [allMissions, paiementsMap, facturesMap]);

  const regimesHistorique = useMemo(() => ({
    salarie: allMissions.some(mission => mission.type_contrat_applique === 'SALARIE'),
    liberal: allMissions.some(mission => mission.type_contrat_applique === 'LIBERAL'),
  }), [allMissions]);
  const destinationPaiements = regimesHistorique.salarie && regimesHistorique.liberal
    ? '/soignant/mes-gains?tab=apercu'
    : regimesHistorique.salarie
      ? '/soignant/mes-gains?tab=bulletins'
      : '/soignant/mes-gains?tab=factures';

  // 7f (§5) : pic d'émotion — le PREMIER paiement reçu est le meilleur moment
  // pour suggérer le parrainage (une seule fois, throttle 30 j global).
  useEffect(() => {
    if (loading || pipeline.paye.nb < 1) return;
    if (localStorage.getItem('jolene_prompt_parrainage_1er_paiement')) return;
    localStorage.setItem('jolene_prompt_parrainage_1er_paiement', '1');
    promptParrainage('Premier paiement reçu — félicitations ! Fais découvrir Jolene à un(e) collègue : une prime pour chacun.');
  }, [loading, pipeline.paye.nb]);

  const exporterCSV = () => {
    if (erreurAffichee) return;
    const header = 'Début,Fin,Mission,Service,Établissement,Heures,Taux horaire,Brut,Montant affiché,Nature\n';
    const rows = missions.flatMap(m => {
      const finance = montantFinanceAfficheMission(m);
      const creneaux = Array.isArray(m.creneaux_export) && m.creneaux_export.length > 0
        ? m.creneaux_export
        : [{ debut: m.debut_le, fin: m.fin_le, duree_heures: Number(m.duree_heures) || 0 }];
      return creneaux.map((creneau: any, index: number) => (
        `${formatParis(creneau.debut, 'dd/MM/yyyy HH:mm')},${formatParis(creneau.fin, 'dd/MM/yyyy HH:mm')},"${(m.intitule || '').replace(/"/g, '""')}","${(m.service || '').replace(/"/g, '""')}","${(m.etablissements?.nom || '').replace(/"/g, '""')}",${Number(creneau.duree_heures) || 0},${Number(m.taux_horaire_base) || 0},${index === 0 ? (Number(m.total_brut) || 0).toFixed(2) : ''},${index === 0 ? (finance?.montant ?? 0).toFixed(2) : ''},"${finance?.libelle ?? 'Indisponible'}"`
      ));
    }).join('\n');
    const nom = `gains-jolene-${moisFiltre === 'CE_MOIS' ? cleMoisParis(new Date()) : moisFiltre}-${cleJourParis(new Date())}.csv`;
    void telechargerOuPartager(header + rows, nom, 'text/csv');
  };

  if (loading && allMissions.length === 0) return <ChargementPage />;

  return (
    <>
      {erreurAffichee && (
        <div className="mb-5 rounded-xl border border-destructive/30 bg-destructive/5 p-4" role="alert">
          <p className="font-semibold text-destructive">Impossible de charger tous les revenus</p>
          <p className="mt-1 text-sm text-muted-foreground">{erreurAffichee}</p>
          <BoutonY2K size="sm" variant="secondary" className="mt-3" onClick={() => setReloadKey(key => key + 1)}>
            Réessayer
          </BoutonY2K>
        </div>
      )}
      <BandeauPaiementDeclare />

      {/* Paiement rapide ⚡ (escrow) — bloc « À venir » en tête. Masqué si aucun
          paiement escrow (cf. PaiementsEscrowAVenir + spec §4). */}
      <PaiementsEscrowAVenir />

      {/* 6d.1 — Pipeline unique : la SEULE histoire d'argent de l'Aperçu.
          Chaque étape a un montant ; « En attente » lit exactement les factures
          de l'onglet Factures (montants TTC identiques, plus de divergence). */}
      {(pipeline.aValider.nb + pipeline.enAttente.nb + pipeline.paye.nb) > 0 && (
        <div className="rounded-2xl border border-jolene-rose-200/60 bg-gradient-soft p-4 mb-6">
          <div className="flex items-center gap-2 mb-3">
            <Clock className="h-4 w-4 text-primary" />
            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              Tes rémunérations, étape par étape
            </p>
          </div>
          <div className="grid grid-cols-3 gap-2">
            {[
              {
                label: 'Validation établissement',
                detail: 'en attente côté établissement',
                etape: pipeline.aValider,
                // 9.1 — deep link ciblé : singleton → détail mission direct
                // (bloc statut + relance) ; sinon onglet Historique filtré sur
                // les présences en attente de validation étab (miroir gate 7b-B).
                onClick: () => navigate(
                  pipeline.aValider.ids.length === 1
                    ? `/soignant/presences/mission/${pipeline.aValider.ids[0]}`
                    : '/soignant/presences?tab=historique&filtre=a_valider',
                ),
              },
              {
                label: 'En attente de paiement',
                detail: 'facture ou paie en cours',
                etape: pipeline.enAttente,
                onClick: () => navigate(destinationPaiements),
              },
              {
                label: 'Payé',
                detail: 'règlement confirmé',
                etape: pipeline.paye,
                onClick: () => navigate(
                  pipeline.paye.nbFactures > 0
                    ? '/soignant/mes-gains?tab=factures'
                    : destinationPaiements,
                ),
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
                  {etape.nb} rémunération{etape.nb > 1 ? 's' : ''} · {detail}
                </p>
              </button>
            ))}
          </div>
          <p className="text-[10px] text-muted-foreground italic mt-2">
            Honoraires libéraux et nets salariés estimés restent séparés dans le détail. Le versement salarié est effectué par l'établissement employeur.
          </p>
        </div>
      )}

      {/* §7.2 Lot 7a — banner parrainage permanent RETIRÉ de Revenus : cet écran a
          un seul job, la confiance paiement. Le parrainage vit dans Compte (entrée
          dédiée), en bas d'Accueil (carte discrète) et aux pics d'émotion (§5). */}

      {/* KPIs — séparés par régime (jamais de sous-bloc à zéro). Honoraires libéraux
          et net salarié ne sont pas le même concept : on ne les fusionne pas. */}
      {!periodeMissions.erreur && <>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
        {libMissions.length > 0 && (
          <CarteKPIY2K
            icone={<Banknote className="h-4 w-4" />}
            valeur={fmt(honorairesLib)}
            label={`Honoraires · missions terminées · ${labelPeriode}`}
            variant="holographic"
            onClick={() => navigate('/soignant/mes-gains?tab=factures')}
          />
        )}
        {/* D3 : salarié pur → PAS d'estimation ~22 % (le net exact vient du
            bulletin de paie de l'établissement) ; le Brut devient le KPI primaire. */}
        {salMissions.length > 0 && (
          <CarteKPIY2K
            icone={<Banknote className="h-4 w-4" />}
            valeur={fmt(netSal)}
            label={`Net salarié* · ${labelPeriode}`}
            variant={libMissions.length > 0 ? 'default' : 'holographic'}
            onClick={() => navigate('/soignant/mes-gains?tab=bulletins')}
          />
        )}
        <CarteKPIY2K
          icone={<TrendingUp className="h-4 w-4" />}
          valeur={fmt(totalBrutFiltre)}
          label={`Brut · ${labelPeriode}`}
          variant={isSalariePur ? 'holographic' : 'default'}
          onClick={() => navigate(destinationPaiements)}
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
        {isSalariePur && salMissions.length === 0 ? (
          <p className="text-[11px] text-muted-foreground mb-6">
            💼 Le net exact figure sur le <strong>bulletin de paie fourni par l'établissement employeur</strong>.
          </p>
        ) : salMissions.length > 0 ? (
          <NoteNetEstime className="mb-6" />
        ) : null}
        {indetCount > 0 && (
          <p className="text-xs text-muted-foreground mb-6">
            {indetCount} mission{indetCount > 1 ? 's' : ''} en cours de qualification de régime — non comptée{indetCount > 1 ? 's' : ''} ci-dessus.
          </p>
        )}
        {libMissions.length > 0 && (
          <p className="text-[11px] text-muted-foreground mb-6">
            👜 Honoraires libéraux bruts dus pour les missions terminées — ce montant ne signifie pas nécessairement qu'il est déjà encaissé. Les charges URSSAF/CARPIMKO sont <strong>annualisées</strong> (provisionnées, pas prélevées à chaque mission) — voir <button onClick={() => navigate('/soignant/charges')} className="text-primary hover:underline">Mes charges</button>.
          </p>
        )}
      </>}

      {/* 6d.1 : graphique seulement à partir de 2 mois de données — une barre
          seule = du bruit, pas une tendance. */}
      {moisDisponibles.length >= 2 && (
        <Suspense fallback={<div className="h-64 animate-pulse bg-muted rounded-lg" />}>
          <GraphiqueGains6Mois missions={missionsGraphique} />
        </Suspense>
      )}

      {/* 9.3 — échéances fiscales : descendues sous les KPIs/gains (hiérarchie
          pipeline → KPIs → gains → échéances), juste au-dessus des exports pour
          que la promotion J-7 pointe vers eux. */}
      {isLiberal && (
        <div className="mb-6">
          <RappelsFiscaux
            regimeFiscal={soignant?.regime_fiscal ?? 'MICRO_BNC'}
            regimeFiscalConfirme={soignant?.regime_fiscal_confirme === true}
          />
        </div>
      )}

      {/* Filtre + Actions */}
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        <Select value={moisFiltre} onValueChange={setMoisFiltre}>
          <SelectTrigger className="w-52"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="CE_MOIS">Ce mois</SelectItem>
            <SelectItem value="TOUS">Tous les mois</SelectItem>
            {moisDisponibles.map(m => (
              <SelectItem key={m} value={m}>{formatParis(`${m}-01T12:00:00`, 'MMMM yyyy')}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        <BoutonY2K variant="secondary" size="sm" onClick={exporterCSV} disabled={Boolean(erreurAffichee) || missions.length === 0} className="gap-1.5">
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
            <div>
              <span className="text-muted-foreground">Montants par régime</span>
              <p className="font-bold text-foreground">
                {[
                  honorairesLib > 0 ? `${fmt(honorairesLib)} honoraires` : null,
                  netSal > 0 ? `${fmt(netSal)} net salarié*` : null,
                ].filter(Boolean).join(' + ') || '—'}
              </p>
            </div>
          </div>
        </div>
      )}

      <p className="text-[10px] text-muted-foreground italic mb-3">
        {salMissions.length > 0 && '* Net salarié estimé après cotisations salariales (~22 %). '}
        {libMissions.length > 0 && '* Honoraires libéraux hors charges URSSAF/CARPIMKO (annualisées). '}
        {libMissions.length === 0 && salMissions.length === 0 && '* Aucun montant net n’est inventé tant que le régime n’est pas qualifié. '}
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
            const finance = montantFinanceAfficheMission(m);
            const duree = m.duree_heures ?? ((new Date(m.fin_le).getTime() - new Date(m.debut_le).getTime()) / 3600000);
            const creneauxPeriode = Array.isArray(m.creneaux_export) ? m.creneaux_export : [];
            const debutAffiche = creneauxPeriode[0]?.debut ?? m.debut_le;
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
                    <span className="text-[10px] font-semibold text-muted-foreground uppercase">{formatParis(debutAffiche, 'EEE')}</span>
                    <span className="text-base font-bold text-foreground leading-tight">{formatParis(debutAffiche, 'd')}</span>
                    <span className="text-[10px] text-muted-foreground">{formatParis(debutAffiche, 'MMM')}</span>
                  </div>
                  {/* Mission info */}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground truncate" title={m.intitule}>{m.intitule}</p>
                    <p className="text-xs text-muted-foreground">
                      🏥 {m.etablissements?.nom || '—'}
                      {m.service && ` · ${m.service}`}
                    </p>
                    <div className="flex items-center gap-3 mt-0.5 text-[11px] text-muted-foreground">
                      {creneauxPeriode.length > 0 ? (
                        <span>
                          {creneauxPeriode.map((creneau: any) => (
                            `${formatParis(creneau.debut, "d MMM HH'h'mm")}→${formatParis(creneau.fin, "HH'h'mm")}`
                          )).join(' · ')}
                        </span>
                      ) : (
                        <span>{formatParis(m.debut_le, "HH'h'mm")} → {formatParis(m.fin_le, "HH'h'mm")}</span>
                      )}
                      <span>{Math.round(duree * 10) / 10}h</span>
                      <span>{m.taux_horaire_base} €/h</span>
                    </div>
                  </div>
                  {/* Net amount + payment status */}
                  <div className="text-right shrink-0 ml-2">
                    {finance?.nature === 'NET_SALARIE_ESTIME' ? (
                      <button
                        className="text-primary font-bold text-sm hover:underline"
                        onClick={(e) => { e.stopPropagation(); setCotisationsMissionId(m.id); }}
                        aria-label="Voir le détail de l'estimation salariale"
                      >
                        ~{fmt(finance.montant)}
                      </button>
                    ) : (
                      <p className="text-primary font-bold text-sm">
                        {finance ? `${finance.approximatif ? '~' : ''}${fmt(finance.montant)}` : '—'}
                      </p>
                    )}
                    {finance && <p className="text-[10px] text-muted-foreground">{finance.libelle}</p>}
                    {m.total_brut != null && (
                      <p className="text-[10px] text-muted-foreground">brut : {fmt(m.total_brut)}</p>
                    )}
                    {(() => {
                      const resume = resumerFacturesMission(facturesMap[m.id] ?? []);
                      if (resume.nbEnAttente > 0) {
                        return (
                          <p className="text-[10px] text-warning flex items-center justify-end gap-0.5">
                            <AlertTriangle className="h-3 w-3" />
                            {resume.nbPayees > 0 && `${resume.nbPayees} payée${resume.nbPayees > 1 ? 's' : ''} · `}
                            {resume.nbEnRetard > 0
                              ? `${resume.nbEnRetard} en retard`
                              : `${resume.nbEnAttente} en attente`}
                          </p>
                        );
                      }
                      if (resume.nbPayees > 0) {
                        return <p className="text-[10px] text-success flex items-center justify-end gap-0.5"><CheckCircle className="h-3 w-3" />{resume.nbPayees} facture{resume.nbPayees > 1 ? 's' : ''} payée{resume.nbPayees > 1 ? 's' : ''}</p>;
                      }
                      if ((facturesMap[m.id] ?? []).some(factureEstAvoir)) {
                        return <p className="text-[10px] text-muted-foreground">Avoir enregistré</p>;
                      }
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
          {hasMore && (
            <button disabled={loading} onClick={() => setPage(p => p + 1)} className="btn-secondary w-full mt-4">
              {loading ? 'Chargement…' : 'Charger plus de missions'}
            </button>
          )}
        </div>
      ) : erreurAffichee ? null : allMissions.length === 0 ? (
        <EmptyState illustration={<IllustrationTirelire />} titre="Pas encore de gains" description="Tes gains apparaîtront ici après ta première mission terminée." cta={{ label: 'Trouver une mission', onClick: () => navigate('/soignant/recherche-missions') }} compact />
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
  const [aDesBulletins, setADesBulletins] = useState(false);
  const [aDesFacturesHonoraires, setADesFacturesHonoraires] = useState(false);
  const [erreurMetaFinances, setErreurMetaFinances] = useState<string | null>(null);
  // Affacturage Defacto pas en prod → onglet « Avances » masqué tant que le flag
  // affacturage_actif est off (défaut). Flippable à chaud côté param système.
  const affacturageActif = useAffacturageActif();

  useEffect(() => {
    if (!user) return;
    let actif = true;
    void (async () => {
      const [profilResult, bulletinsResult, facturesResult] = await Promise.all([
        supabase.from('soignants').select('type_exercice, statut_liberal').eq('id', user.id).maybeSingle(),
        supabase.rpc('fn_mes_bulletins_paie' as any),
        supabase.rpc('fn_mes_factures_honoraires' as any),
      ]);
      if (!actif) return;
      if (profilResult.error || bulletinsResult.error || facturesResult.error) {
        setErreurMetaFinances(
          profilResult.error?.message
          || bulletinsResult.error?.message
          || facturesResult.error?.message
          || 'Impossible de vérifier tout l’historique financier.',
        );
      } else {
        setErreurMetaFinances(null);
      }
      const data = profilResult.data;
      setADesBulletins(Array.isArray(bulletinsResult.data) && bulletinsResult.data.length > 0);
      setADesFacturesHonoraires(Array.isArray(facturesResult.data) && facturesResult.data.length > 0);
      setExercice({
        type: (data as any)?.type_exercice ?? null,
        liberalActif: (data as any)?.statut_liberal === 'ACTIF',
      });
    })();
    return () => { actif = false; };
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
  const showFactures = aDesFacturesHonoraires || estLiberal || (exercice == null);
  const showBulletins = aDesBulletins || estSalarie || (type == null && exercice != null) || (exercice == null);
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
        <p className="text-sm text-muted-foreground mt-1">{affacturageActif ? 'Tes gains, factures, simulations de paie et avance de trésorerie au même endroit' : 'Tes gains, factures et simulations de paie au même endroit'}</p>
      </div>

      {erreurMetaFinances && (
        <div className="mb-4 rounded-xl border border-warning/30 bg-warning/5 p-3" role="alert">
          <p className="text-sm font-medium text-warning">Historique financier partiellement indisponible</p>
          <p className="mt-1 text-xs text-muted-foreground">{erreurMetaFinances}</p>
        </div>
      )}

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
              <span>Simulations</span>
            </TabsTrigger>
          )}
          {showAvances && (
            /* ⚡ Zap = réservé au paiement rapide escrow. L'affacturage Defacto
               a son vocabulaire propre : « Avance de trésorerie » + icône Landmark. */
            <TabsTrigger value="avances" className="flex items-center gap-1.5 text-xs sm:text-sm">
              <Landmark className="h-3.5 w-3.5 sm:h-4 sm:w-4" />
              <span>Avance de trésorerie</span>
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
