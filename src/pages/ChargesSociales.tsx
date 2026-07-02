import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Calculator, Calendar, Shield, Building2, PieChart, Banknote, ChevronRight, Download, ExternalLink, ArrowLeft } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { ouvrirLienExterne } from '@/lib/platform';
import { format, differenceInDays } from 'date-fns';
import { telechargerOuPartager } from '@/lib/telechargement';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { PieChart as RechartsPie, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts';

const TAUX_URSSAF = 0.212;
const CARPIMKO_FORFAIT = 1800;
const CARPIMKO_PROPORTIONNEL_TAUX = 0.016;

function fmt(v: number | null | undefined) {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

function getProchainTrimestreURSSAF(): Date {
  const now = new Date();
  const y = now.getFullYear();
  const echeances = [
    new Date(y, 0, 5), new Date(y, 3, 5), new Date(y, 6, 5), new Date(y, 9, 5),
  ];
  return echeances.find(d => d > now) || new Date(y + 1, 0, 5);
}

function getEcheanceCARPIMKO(): Date {
  const now = new Date();
  const avrilCette = new Date(now.getFullYear(), 3, 1);
  return avrilCette > now ? avrilCette : new Date(now.getFullYear() + 1, 3, 1);
}

function getEcheanceCFE(): Date {
  const now = new Date();
  const decCette = new Date(now.getFullYear(), 11, 15);
  return decCette > now ? decCette : new Date(now.getFullYear() + 1, 11, 15);
}

/** Déclaration contrôlée : dépôt de la 2035 — 15 mai suivant l'année des revenus.
 *  Micro-BNC : la 2042-C-PRO part avec la déclaration de revenus (≈ fin mai). */
function getEcheanceImpot(microBnc: boolean): Date {
  const now = new Date();
  const d = microBnc ? new Date(now.getFullYear(), 4, 31) : new Date(now.getFullYear(), 4, 15);
  return d > now ? d : (microBnc ? new Date(now.getFullYear() + 1, 4, 31) : new Date(now.getFullYear() + 1, 4, 15));
}

function Countdown({ date }: { date: Date }) {
  const jours = differenceInDays(date, new Date());
  const color = jours <= 14 ? 'text-destructive' : jours <= 30 ? 'text-warning' : 'text-muted-foreground';
  return (
    <span className={`text-xs font-medium ${color}`}>
      {jours <= 0 ? 'Échue' : `dans ${jours}j`}
    </span>
  );
}

const PIE_COLORS = ['#1BA8C4', '#D4607E', '#F06060', '#2CC8A0'];

export default function ChargesSociales() {
  usePageTitle('Mes charges');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [caCumule, setCaCumule] = useState(0);
  const [rcpExpiration, setRcpExpiration] = useState<string | null>(null);
  const [soignant, setSoignant] = useState<any>(null);
  const [missions, setMissions] = useState<any[]>([]);
  const [showMissions, setShowMissions] = useState(false);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const annee = new Date().getFullYear();
      const debutAnnee = new Date(annee, 0, 1).toISOString();

      const [{ data: missionData }, { data: docs }, { data: sg }] = await Promise.all([
        supabase
          .from('missions')
          .select('id, intitule, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, etablissement_id, service')
          .eq('soignant_assigne_id', user.id)
          .eq('statut', 'TERMINEE')
          // Charges sociales = libéral uniquement. On ne compte QUE les missions
          // dont le régime appliqué est LIBERAL (un soignant Mixte ne voit pas ses
          // missions salariées gonfler son CA/charges). NULL = non déterminé → exclu.
          .eq('type_contrat_applique', 'LIBERAL')
          .gte('fin_le', debutAnnee)
          .order('debut_le', { ascending: false }),
        supabase
          .from('documents_soignants')
          .select('valide_jusqua')
          .eq('soignant_id', user.id)
          .eq('type_document', 'RCP_ASSURANCE')
          .eq('statut_verification', 'VERIFIE')
          .is('supprime_le', null)
          .order('valide_jusqua', { ascending: false })
          .limit(1),
        supabase.from('soignants').select('prenom, nom, profession, statut_liberal, assujetti_tva, regime_fiscal, regime_fiscal_confirme' as any).eq('id', user.id).maybeSingle(),
      ]);

      const enriched = missionData ? await enrichirEtablissements(missionData as any) : [];
      setMissions(enriched as any[]);
      const ca = (enriched as any[]).reduce((s: number, m: any) => s + (m.total_brut || 0), 0);
      setCaCumule(ca);
      if (docs && docs.length > 0) setRcpExpiration(docs[0].valide_jusqua);
      setSoignant(sg);
      setLoading(false);
    };
    load();
  }, [user]);

  // §7.7 Lot 7a — régime fiscal : défaut micro-BNC « à confirmer » tant que la
  // question n'a pas été posée. La sélection est immédiate (1 tap) et pilote
  // l'échéance impôt (2042-C-PRO en micro-BNC, 2035 en déclaration contrôlée).
  const microBnc = (soignant?.regime_fiscal ?? 'MICRO_BNC') === 'MICRO_BNC';
  const regimeConfirme = soignant?.regime_fiscal_confirme === true;
  const [savingRegime, setSavingRegime] = useState(false);

  const choisirRegime = async (regime: 'MICRO_BNC' | 'DECLARATION_CONTROLEE') => {
    if (!user || savingRegime) return;
    setSavingRegime(true);
    const { error } = await supabase
      .from('soignants')
      .update({ regime_fiscal: regime, regime_fiscal_confirme: true } as any)
      .eq('id', user.id);
    setSavingRegime(false);
    if (error) {
      toast.error('Impossible d\'enregistrer ton régime fiscal — réessaie.');
      return;
    }
    setSoignant((s: any) => ({ ...s, regime_fiscal: regime, regime_fiscal_confirme: true }));
    toast.success(regime === 'MICRO_BNC' ? 'Régime micro-BNC enregistré' : 'Régime déclaration contrôlée enregistré');
  };

  const carteRegimeFiscal = (
    <div className="card-base mb-6">
      <div className="flex items-center justify-between gap-2 mb-1">
        <h2 className="font-semibold text-foreground">Ton régime fiscal</h2>
        {!regimeConfirme && (
          <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-warning/10 text-warning shrink-0">à confirmer</span>
        )}
      </div>
      <p className="text-xs text-muted-foreground mb-3">
        Il détermine ta déclaration d'impôt. En cas de doute, demande à ton comptable — tu peux le changer ici à tout moment.
      </p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
        <button
          type="button"
          disabled={savingRegime}
          onClick={() => choisirRegime('MICRO_BNC')}
          aria-pressed={microBnc}
          className={`rounded-xl border p-3 text-left transition-colors min-h-[44px] ${
            microBnc ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/40'
          }`}
        >
          <p className="text-sm font-semibold text-foreground">Micro-BNC {microBnc && '✓'}</p>
          <p className="text-[11px] text-muted-foreground mt-0.5">
            Abattement forfaitaire de 34 %, pas de comptabilité complète. Tu déclares avec ta déclaration de revenus (formulaire 2042-C-PRO).
          </p>
        </button>
        <button
          type="button"
          disabled={savingRegime}
          onClick={() => choisirRegime('DECLARATION_CONTROLEE')}
          aria-pressed={!microBnc}
          className={`rounded-xl border p-3 text-left transition-colors min-h-[44px] ${
            !microBnc ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/40'
          }`}
        >
          <p className="text-sm font-semibold text-foreground">Déclaration contrôlée {!microBnc && '✓'}</p>
          <p className="text-[11px] text-muted-foreground mt-0.5">
            Déduction des frais réels, comptabilité tenue. Tu déposes une déclaration dédiée (formulaire 2035) chaque 15 mai.
          </p>
        </button>
      </div>
    </div>
  );

  const urssaf = useMemo(() => caCumule * TAUX_URSSAF, [caCumule]);
  const carpimkoProportionnel = useMemo(() => caCumule * CARPIMKO_PROPORTIONNEL_TAUX, [caCumule]);
  const carpimkoTotal = useMemo(() => CARPIMKO_FORFAIT + carpimkoProportionnel, [carpimkoProportionnel]);
  const rcpEstime = 400;
  const totalCharges = urssaf + carpimkoTotal + rcpEstime;
  const revenuNet = caCumule - totalCharges;
  const totalHeures = useMemo(() => missions.reduce((s, m) => s + (m.duree_heures || 0), 0), [missions]);

  const pieData = useMemo(() => [
    { name: 'URSSAF', value: Math.round(urssaf) },
    { name: 'CARPIMKO', value: Math.round(carpimkoTotal) },
    { name: 'RCP', value: rcpEstime },
    { name: 'Revenu net', value: Math.max(0, Math.round(revenuNet)) },
  ], [urssaf, carpimkoTotal, revenuNet]);

  const prochainURSSAF = getProchainTrimestreURSSAF();
  const echeanceCARPIMKO = getEcheanceCARPIMKO();
  const echeanceCFE = getEcheanceCFE();

  const exporterCSV = () => {
    const header = 'Poste,Montant annuel estimé,Échéance\n';
    const rows = [
      `URSSAF (21.2%),${urssaf.toFixed(2)},${format(prochainURSSAF, 'dd/MM/yyyy')}`,
      `CARPIMKO forfait,${CARPIMKO_FORFAIT},${format(echeanceCARPIMKO, 'dd/MM/yyyy')}`,
      `CARPIMKO proportionnel (1.6%),${carpimkoProportionnel.toFixed(2)},`,
      `RCP (estimé),${rcpEstime},`,
      `Total charges,${totalCharges.toFixed(2)},`,
      `CA cumulé,${caCumule.toFixed(2)},`,
      `Revenu net estimé,${revenuNet.toFixed(2)},`,
    ].join('\n');
    void telechargerOuPartager(header + rows, `charges-jolene-${new Date().getFullYear()}.csv`, 'text/csv');
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  if (!soignant || (soignant.statut_liberal !== 'ACTIF' && soignant.statut_liberal !== 'EN_COURS')) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="card-base text-center py-12">
          <p className="text-lg font-bold text-foreground mb-2">Charges sociales libérales</p>
          <p className="text-sm text-muted-foreground max-w-md mx-auto">
            Cette page est réservée aux soignants en exercice libéral ou mixte.
          </p>
          <button onClick={() => navigate('/soignant/tableau-de-bord')} className="btn-primary mt-4 text-sm">
            Retour au dashboard
          </button>
        </div>
      </LayoutApp>
    );
  }

  // État vide assumé : libéral sans aucune mission libérale terminée cette année.
  // On affiche un message clair plutôt qu'un échéancier à 0 € qui ferait croire à un bug.
  if (missions.length === 0) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="mb-6">
          <button onClick={() => navigate('/soignant/mes-gains')} className="flex items-center gap-1 text-sm text-primary hover:underline mb-2">
            <ArrowLeft className="h-4 w-4" /> Retour aux gains
          </button>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <Calculator className="h-6 w-6 text-primary" /> Mes charges sociales
          </h1>
        </div>
        {/* La question du régime fiscal se pose même sans mission (le tag
            « à confirmer » des échéances fiscales mène ici). */}
        {carteRegimeFiscal}
        <div className="card-base text-center py-12">
          <Calculator className="h-10 w-10 text-primary/40 mx-auto mb-3" />
          <p className="text-lg font-bold text-foreground mb-2">Tes charges apparaîtront ici</p>
          <p className="text-sm text-muted-foreground max-w-md mx-auto">
            On les estime automatiquement (URSSAF, CARPIMKO, RCP) après ta première mission
            libérale terminée. Tu n'as pas encore de mission libérale finalisée cette année.
          </p>
          <BoutonY2K onClick={() => navigate('/soignant/recherche-missions')} className="mt-5">
            Trouver une mission
          </BoutonY2K>
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="SOIGNANT">
      {/* Header with back link */}
      <div className="mb-6">
        <button onClick={() => navigate('/soignant/mes-gains')} className="flex items-center gap-1 text-sm text-primary hover:underline mb-2">
          <ArrowLeft className="h-4 w-4" /> Retour aux gains
        </button>
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Calculator className="h-6 w-6 text-primary" /> Mes charges sociales
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Estimations basées sur ton CA libéral {new Date().getFullYear()}</p>
      </div>

      {carteRegimeFiscal}

      {/* CA banner — clickable to show missions */}
      <div
        className="card-base mb-6 cursor-pointer hover:border-primary/30 transition-colors"
        role="button"
        tabIndex={0}
        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setShowMissions(!showMissions); } }}
        onClick={() => setShowMissions(!showMissions)}
      >
        <div className="text-center">
          <p className="text-sm text-muted-foreground">Chiffre d'affaires libéral cumulé {new Date().getFullYear()}</p>
          <p className="text-xl sm:text-3xl font-bold text-primary mt-1">{fmt(caCumule)}</p>
          <div className="flex justify-center gap-4 mt-2 text-xs text-muted-foreground">
            <span>{missions.length} mission{missions.length > 1 ? 's' : ''}</span>
            <span>{totalHeures}h travaillées</span>
          </div>
        </div>
        <p className="text-[10px] text-primary text-center mt-2">
          {showMissions ? '▲ Masquer le détail' : '▼ Voir le détail des missions'}
        </p>
      </div>

      {/* Mission breakdown */}
      {showMissions && missions.length > 0 && (
        <div className="space-y-1.5 mb-6">
          {missions.map(m => (
            <div
              key={m.id}
              onClick={() => navigate(`/soignant/presences/mission/${m.id}`)}
              className="flex items-center justify-between py-2 px-3 rounded-lg border border-border hover:bg-muted/20 cursor-pointer transition-colors text-xs"
            >
              <div className="min-w-0 flex-1">
                <p className="font-medium text-foreground truncate">{m.intitule}</p>
                <p className="text-muted-foreground">
                  {format(new Date(m.debut_le), 'd MMM', { locale: fr })} · {m.etablissements?.nom} · {m.duree_heures}h
                </p>
              </div>
              <div className="flex items-center gap-1.5 shrink-0 ml-2">
                <span className="font-bold text-foreground">{fmt(m.total_brut)}</span>
                <ChevronRight className="h-3.5 w-3.5 text-muted-foreground" />
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Échéancier compact */}
      <div className="card-base mb-6">
        <h2 className="font-semibold text-foreground mb-3 flex items-center gap-2">
          <Calendar className="h-4.5 w-4.5 text-primary" /> Prochaines échéances
        </h2>
        <div className="space-y-2">
          {[
            { nom: 'URSSAF trimestriel', date: prochainURSSAF, montant: urssaf / 4, lien: 'https://www.autoentrepreneur.urssaf.fr' },
            { nom: 'CARPIMKO annuel', date: echeanceCARPIMKO, montant: carpimkoTotal, lien: 'https://www.carpimko.com' },
            // §7.7 : action en clair + année des revenus + formulaire entre
            // parenthèses — jamais « 2035 » seul à côté d'une date.
            {
              nom: `Déclaration de tes revenus ${getEcheanceImpot(microBnc).getFullYear() - 1} (formulaire ${microBnc ? '2042-C-PRO' : '2035'})`,
              date: getEcheanceImpot(microBnc),
              montant: null,
              lien: 'https://www.impots.gouv.fr/particulier',
            },
            { nom: 'CFE', date: echeanceCFE, montant: null, lien: 'https://www.impots.gouv.fr/professionnel' },
          ].map(e => (
            <div key={e.nom} className="flex items-center justify-between py-2 px-3 bg-muted/30 rounded-lg">
              <div className="flex items-center gap-2">
                <div className="min-w-0">
                  <p className="text-sm font-medium text-foreground">{e.nom}</p>
                  <p className="text-[10px] text-muted-foreground">{format(e.date, 'd MMMM yyyy', { locale: fr })}</p>
                </div>
              </div>
              <div className="flex items-center gap-3 shrink-0">
                {e.montant != null && <span className="text-sm font-bold text-foreground">~{fmt(e.montant)}</span>}
                <Countdown date={e.date} />
                <button
                  onClick={() => ouvrirLienExterne(e.lien)}
                  className="text-primary hover:underline"
                  title={`Ouvrir ${e.nom}`}
                >
                  <ExternalLink className="h-3.5 w-3.5" />
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Charges cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        {/* URSSAF */}
        <div className="card-base cursor-pointer hover:border-primary/30 transition-colors" onClick={() => ouvrirLienExterne('https://www.autoentrepreneur.urssaf.fr')}>
          <div className="flex items-center gap-2 mb-3">
            <div className="rounded-xl p-2 bg-primary/10"><Building2 className="h-5 w-5 text-primary" /></div>
            <div className="flex-1">
              <h3 className="font-semibold text-foreground">URSSAF</h3>
              <p className="text-xs text-muted-foreground">Cotisations sociales · 21,2%</p>
            </div>
            <ExternalLink className="h-4 w-4 text-muted-foreground" />
          </div>
          <div className="space-y-1.5 text-sm">
            <div className="flex justify-between"><span className="text-muted-foreground">Estimation annuelle</span><span className="font-bold text-foreground">{fmt(urssaf)}</span></div>
            <div className="flex justify-between"><span className="text-muted-foreground">Par trimestre</span><span className="font-medium text-foreground">~{fmt(urssaf / 4)}</span></div>
          </div>
        </div>

        {/* CARPIMKO */}
        <div className="card-base cursor-pointer hover:border-primary/30 transition-colors" onClick={() => ouvrirLienExterne('https://www.carpimko.com')}>
          <div className="flex items-center gap-2 mb-3">
            <div className="rounded-xl p-2 bg-accent/10"><Shield className="h-5 w-5 text-accent-foreground" /></div>
            <div className="flex-1">
              <h3 className="font-semibold text-foreground">CARPIMKO</h3>
              <p className="text-xs text-muted-foreground">Retraite complémentaire</p>
            </div>
            <ExternalLink className="h-4 w-4 text-muted-foreground" />
          </div>
          <div className="space-y-1.5 text-sm">
            <div className="flex justify-between"><span className="text-muted-foreground">Forfait annuel</span><span className="font-medium text-foreground">{fmt(CARPIMKO_FORFAIT)}</span></div>
            <div className="flex justify-between"><span className="text-muted-foreground">Part proportionnelle (1,6%)</span><span className="font-medium text-foreground">{fmt(carpimkoProportionnel)}</span></div>
            <div className="flex justify-between"><span className="text-muted-foreground">Total estimé</span><span className="font-bold text-foreground">{fmt(carpimkoTotal)}</span></div>
          </div>
        </div>

        {/* RCP */}
        <div className="card-base cursor-pointer hover:border-primary/30 transition-colors" onClick={() => navigate('/soignant/documents')}>
          <div className="flex items-center gap-2 mb-3">
            <div className="rounded-xl p-2 bg-destructive/10"><Shield className="h-5 w-5 text-destructive" /></div>
            <div className="flex-1">
              <h3 className="font-semibold text-foreground">Assurance RCP</h3>
              <p className="text-xs text-muted-foreground">Responsabilité civile pro.</p>
            </div>
            <ChevronRight className="h-4 w-4 text-muted-foreground" />
          </div>
          {rcpExpiration ? (
            <div className="space-y-1.5 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Expiration</span>
                <span className="font-medium text-foreground">{format(new Date(rcpExpiration), 'd MMM yyyy', { locale: fr })}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Statut</span>
                {new Date(rcpExpiration) > new Date() ? (
                  <span className="text-xs font-medium text-success">✅ Valide</span>
                ) : (
                  <span className="text-xs font-medium text-destructive">❌ Expirée</span>
                )}
              </div>
            </div>
          ) : (
            <p className="text-sm text-destructive">⚠️ Aucune RCP vérifiée. Voir Documents →</p>
          )}
        </div>

        {/* CFE */}
        <div className="card-base cursor-pointer hover:border-primary/30 transition-colors" onClick={() => ouvrirLienExterne('https://www.impots.gouv.fr/professionnel')}>
          <div className="flex items-center gap-2 mb-3">
            <div className="rounded-xl p-2 bg-muted"><Building2 className="h-5 w-5 text-muted-foreground" /></div>
            <div className="flex-1">
              <h3 className="font-semibold text-foreground">CFE</h3>
              <p className="text-xs text-muted-foreground">Cotisation foncière des entreprises</p>
            </div>
            <ExternalLink className="h-4 w-4 text-muted-foreground" />
          </div>
          <p className="text-sm text-muted-foreground">Variable selon commune. Exonérée la 1ère année.</p>
        </div>
      </div>

      {/* Pie chart */}
      {caCumule > 0 && (
        <div className="card-base mb-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-base font-bold text-foreground flex items-center gap-2">
              <PieChart className="h-5 w-5 text-primary" /> Répartition
            </h2>
            <BoutonY2K variant="secondary" size="sm" onClick={exporterCSV} className="gap-1.5 text-xs">
              <Download className="h-3.5 w-3.5" /> Exporter
            </BoutonY2K>
          </div>
          <div className="flex flex-col md:flex-row items-center gap-6">
            <ResponsiveContainer width={200} height={200}>
              <RechartsPie>
                <Pie data={pieData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={45} outerRadius={85} paddingAngle={2}>
                  {pieData.map((_, i) => <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
                </Pie>
                <Tooltip formatter={(value: number) => [`${value} €`]} />
              </RechartsPie>
            </ResponsiveContainer>
            <div className="space-y-2 flex-1 w-full">
              {pieData.map((d, i) => (
                <div key={d.name} className="flex items-center justify-between text-sm">
                  <div className="flex items-center gap-2">
                    <div className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: PIE_COLORS[i] }} />
                    <span className="text-foreground">{d.name}</span>
                  </div>
                  <span className="font-medium text-foreground tabular-nums">{fmt(d.value)} ({caCumule > 0 ? Math.round((d.value / caCumule) * 100) : 0}%)</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Disclaimer + links */}
      <div className="bg-muted/30 border border-border rounded-xl p-4 space-y-3">
        <p className="text-sm text-muted-foreground text-center">
          ⚠️ Estimations indicatives. Consulte ton comptable pour les montants exacts.
        </p>
        <div className="flex flex-wrap gap-2 justify-center">
          <BoutonY2K variant="ghost" size="sm" className="text-xs gap-1" onClick={() => ouvrirLienExterne('https://www.autoentrepreneur.urssaf.fr')}>
            URSSAF <ExternalLink className="h-3 w-3" />
          </BoutonY2K>
          <BoutonY2K variant="ghost" size="sm" className="text-xs gap-1" onClick={() => ouvrirLienExterne('https://www.carpimko.com')}>
            CARPIMKO <ExternalLink className="h-3 w-3" />
          </BoutonY2K>
          <BoutonY2K variant="ghost" size="sm" className="text-xs gap-1" onClick={() => ouvrirLienExterne('https://www.impots.gouv.fr/professionnel')}>
            Impôts.gouv <ExternalLink className="h-3 w-3" />
          </BoutonY2K>
        </div>
      </div>
    </LayoutApp>
  );
}
