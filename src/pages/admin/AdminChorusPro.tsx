import { useState, useEffect, useMemo } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { CheckCircle2, ChevronDown, FileStack, History, RefreshCw, Search, Settings, Wifi } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { messageErreurEdgeFn } from '@/lib/erreurs';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { getChorusStatutBadge, type ChorusBadgeConfig } from '@/lib/chorus-helpers';
import { ChorusSubmissionDetailDialog } from '@/components/admin/ChorusSubmissionDetailDialog';
import { ChorusConfigEtabDialog } from '@/components/admin/ChorusConfigEtabDialog';
import { FileDeTravail } from '@/components/admin/FileDeTravail';
import { EmptyState } from '@/components/ui/EmptyState';

interface Stats {
  total_submissions: number;
  par_statut: Record<string, number>;
  erreurs_7j: number;
  derniere_sync: string | null;
  etabs_configures_actifs: number;
  etabs_secteur_public_total: number;
}

interface Submission {
  id: string;
  invoice_id: string;
  piste_request_id: string | null;
  payload_xml: string | null;
  response_raw: any;
  submission_type: string | null;
  type_document: string | null;
  status: string;
  error_code: string | null;
  error_message: string | null;
  submitted_at: string | null;
  last_checked_at: string | null;
  created_at: string;
  avoir_reference_invoice: string | null;
  facture?: {
    numero_facture: string;
    montant_ttc: number;
    soignant?: { prenom: string; nom: string } | null;
    etablissement?: { nom: string } | null;
  } | null;
}

interface Etab {
  id: string;
  nom: string;
  siret: string | null;
  chorus_pro_config: Array<{ numero_structure: string | null; code_service: string | null; identifiant_cpro: string | null; actif: boolean | null }>;
}

function fmtDate(d: string | null | undefined): string {
  if (!d) return '—';
  try { return format(new Date(d), "d MMM 'à' HH:mm", { locale: fr }); } catch { return d; }
}

/** Statuts qui demandent une action admin (pattern « file de travail », Session D). */
const STATUTS_A_TRAITER = ['pending_credentials', 'rejected', 'error'];

function estATraiter(status: string): boolean {
  return STATUTS_A_TRAITER.includes(status);
}

/** Badge statut en français (surcharge locale du libellé anglicisé du helper partagé). */
function badgeStatut(status: string): ChorusBadgeConfig {
  const b = getChorusStatutBadge(status);
  return status === 'pending_credentials' ? { ...b, label: 'Identifiants manquants' } : b;
}

const SELECT_SUBMISSIONS = `*, facture:factures_honoraires!invoice_id(numero_facture, montant_ttc, soignant:soignants(prenom, nom), etablissement:etablissements(nom))`;

export default function AdminChorusPro() {
  usePageTitle('Chorus Pro — Admin');

  const [tab, setTab] = useState('dashboard');
  const [syncing, setSyncing] = useState(false);
  const [testing, setTesting] = useState(false);

  const testPiste = async () => {
    setTesting(true);
    try {
      const { data, error } = await supabase.functions.invoke('test-piste-credentials');
      if (error) throw error;
      const d: any = data;
      if (d.success) {
        toast.success(`Connexion Chorus Pro ${d.env} opérationnelle — 4/4 tests OK (${d.total_duration_ms ?? '—'} ms)`);
      } else {
        const fails = d.diagnostics?.filter((s: any) => s.status === 'FAIL').map((s: any) => s.step).join(', ');
        toast.error(`Connexion Chorus Pro — échecs : ${fails || d.summary}`);
      }
    } catch (err: any) {
      const msg = await messageErreurEdgeFn(err, 'Erreur lors de la vérification de la connexion Chorus Pro.');
      toast.error(`Vérification connexion : ${msg}`);
    }
    setTesting(false);
  };

  const syncNow = async () => {
    setSyncing(true);
    try {
      const { data, error } = await supabase.functions.invoke('sync-chorus-status');
      if (error) throw error;
      const d: any = data;
      if (d.mode === 'simulation') {
        toast.info('Mode simulation : credentials PISTE absents');
      } else {
        toast.success(`Sync OK : ${d.synced ?? 0} vérifiées, ${d.updates ?? 0} mises à jour, ${d.notifs_emitted ?? 0} notifs`);
      }
    } catch (err: any) {
      const msg = await messageErreurEdgeFn(err, 'Erreur lors de la synchronisation Chorus Pro.');
      toast.error(`Erreur sync : ${msg}`);
    }
    setSyncing(false);
  };

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Chorus Pro" />
      <div className="flex items-center justify-between gap-3 mb-6">
        <div className="flex items-center gap-3">
          <FileStack className="h-7 w-7 text-primary" />
          <h1 className="text-2xl font-bold text-foreground">Chorus Pro</h1>
        </div>
        <div className="flex gap-2">
          <BoutonY2K onClick={testPiste} disabled={testing} variant="secondary" size="sm" iconeGauche={<Wifi className={`h-4 w-4 ${testing ? 'animate-pulse' : ''}`} />}>
            {testing ? 'Vérification…' : 'Vérifier connexion'}
          </BoutonY2K>
          <BoutonY2K onClick={syncNow} disabled={syncing} variant="secondary" size="sm" iconeGauche={<RefreshCw className={`h-4 w-4 ${syncing ? 'animate-spin' : ''}`} />}>
            {syncing ? 'Sync…' : 'Sync maintenant'}
          </BoutonY2K>
        </div>
      </div>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="mb-4">
          <TabsTrigger value="dashboard">Tableau de bord</TabsTrigger>
          <TabsTrigger value="submissions">Soumissions</TabsTrigger>
          <TabsTrigger value="config">Config établissements</TabsTrigger>
        </TabsList>

        <TabsContent value="dashboard"><DashboardChorus /></TabsContent>
        <TabsContent value="submissions"><SubmissionsChorus /></TabsContent>
        <TabsContent value="config"><ConfigEtabsChorus /></TabsContent>
      </Tabs>
    </LayoutAdmin>
  );
}

/* ── Liste compacte de soumissions (tableau de bord) ── */
function ListeSubmissionsCompacte({ items, onDetail }: { items: Submission[]; onDetail: (s: Submission) => void }) {
  return (
    <>
      {/* Desktop : table */}
      <div className="hidden md:block card-base overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-muted-foreground border-b">
              <th className="py-2 pr-2">Créée</th>
              <th className="py-2 pr-2">Facture</th>
              <th className="py-2 pr-2">Étab</th>
              <th className="py-2 pr-2">Type</th>
              <th className="py-2 pr-2">Statut</th>
              <th className="py-2">Action</th>
            </tr>
          </thead>
          <tbody>
            {items.map(s => {
              const b = badgeStatut(s.status);
              return (
                <tr key={s.id} className="border-b hover:bg-muted/30">
                  <td className="py-2 pr-2 text-xs text-muted-foreground">{fmtDate(s.created_at)}</td>
                  <td className="py-2 pr-2">{s.facture?.numero_facture ?? s.invoice_id.slice(0, 8)}</td>
                  <td className="py-2 pr-2">{s.facture?.etablissement?.nom ?? '—'}</td>
                  <td className="py-2 pr-2">{s.type_document ?? '—'}</td>
                  <td className="py-2 pr-2"><span className={`badge-base text-[10px] ${b.classes}`}>{b.label}</span></td>
                  <td className="py-2">
                    <BoutonY2K variant="ghost" size="sm" onClick={() => onDetail(s)}>Détail</BoutonY2K>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Mobile : cards */}
      <div className="md:hidden space-y-2">
        {items.map(s => {
          const b = badgeStatut(s.status);
          return (
            <div key={s.id} className="rounded-lg border border-border p-2.5 space-y-1.5">
              <div className="flex items-start justify-between gap-2">
                <p className="text-sm font-medium truncate">{s.facture?.numero_facture ?? s.invoice_id.slice(0, 8)}</p>
                <span className={`badge-base text-[10px] shrink-0 ${b.classes}`}>{b.label}</span>
              </div>
              <p className="text-xs text-foreground truncate">{s.facture?.etablissement?.nom ?? '—'}</p>
              <div className="flex items-center justify-between text-[10px] text-muted-foreground">
                <span>{s.type_document ?? '—'}</span>
                <span>{fmtDate(s.created_at)}</span>
              </div>
              <BoutonY2K variant="secondary" size="sm" className="w-full min-h-[36px]" onClick={() => onDetail(s)}>
                Voir le détail
              </BoutonY2K>
            </div>
          );
        })}
      </div>
    </>
  );
}

/* ── Dashboard ── */
function DashboardChorus() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [recent, setRecent] = useState<Submission[]>([]);
  const [problemes, setProblemes] = useState<Submission[]>([]);
  const [detail, setDetail] = useState<Submission | null>(null);
  const [loading, setLoading] = useState(true);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      supabase.rpc('fn_admin_chorus_stats' as any),
      supabase.from('chorus_submissions' as any)
        .select(SELECT_SUBMISSIONS)
        .order('created_at', { ascending: false })
        .limit(10),
      // À traiter : rejets, erreurs, identifiants manquants — plus anciennes d'abord
      supabase.from('chorus_submissions' as any)
        .select(SELECT_SUBMISSIONS)
        .in('status', STATUTS_A_TRAITER)
        .order('created_at', { ascending: true })
        .limit(20),
    ]).then(([sRes, rRes, pRes]) => {
      if (sRes.error) {
        setErrorMsg(`Erreur RPC fn_admin_chorus_stats : ${sRes.error.message}`);
      } else if (sRes.data && (sRes.data as any).error) {
        setErrorMsg(`Accès refusé — connectez-vous avec un compte ADMIN_PLATEFORME (${(sRes.data as any).error}).`);
      } else if (sRes.data) {
        setStats(sRes.data as Stats);
      }
      if (rRes.data) setRecent(rRes.data as unknown as Submission[]);
      if (pRes.data) setProblemes(pRes.data as unknown as Submission[]);
      setLoading(false);
    }).catch((err) => {
      setErrorMsg(`Erreur chargement : ${err?.message || 'inconnue'}`);
      setLoading(false);
    });
  }, []);

  if (loading) return <p className="text-sm text-muted-foreground text-center py-8">Chargement…</p>;
  if (errorMsg) return (
    <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">
      <p className="font-semibold mb-1">Impossible de charger les stats Chorus Pro</p>
      <p className="text-xs">{errorMsg}</p>
      <p className="text-xs text-muted-foreground mt-2">Si vous êtes admin et voyez ce message, vérifiez que <code>raw_app_meta_data-&gt;&gt;'role'</code> = <code>'ADMIN_PLATEFORME'</code> sur votre compte (cf. <code>docs/admin-setup.md</code>).</p>
    </div>
  );
  if (!stats) return <p className="text-sm text-muted-foreground text-center py-8">Aucune donnée Chorus Pro pour le moment.</p>;

  const enCours = (stats.par_statut.pending ?? 0) + (stats.par_statut.submitted ?? 0);
  const acceptees = stats.par_statut.accepted ?? 0;
  const rejetees = (stats.par_statut.rejected ?? 0) + (stats.par_statut.error ?? 0);
  // Flux OK relégué : les 10 dernières, hors soumissions déjà listées en « À traiter »
  const fluxOk = recent.filter(s => !estATraiter(s.status));

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        <KpiCard label="Total soumissions" value={stats.total_submissions} />
        <KpiCard label="En cours" value={enCours} color="text-warning" />
        <KpiCard label="Acceptées" value={acceptees} color="text-success" />
        <KpiCard label="Rejetées/Erreurs" value={rejetees} color="text-destructive" />
        <KpiCard label="Erreurs 7j" value={stats.erreurs_7j} color="text-destructive" />
        <KpiCard label="Étabs configurés" value={`${stats.etabs_configures_actifs}/${stats.etabs_secteur_public_total}`} />
      </div>
      <p className="text-xs text-muted-foreground">Dernière sync : {fmtDate(stats.derniere_sync)}</p>

      <FileDeTravail
        nbATraiter={problemes.length}
        aTraiter={<ListeSubmissionsCompacte items={problemes} onDetail={setDetail} />}
        nbHistorique={fluxOk.length}
        historique={<ListeSubmissionsCompacte items={fluxOk} onDetail={setDetail} />}
        labelATraiter="À traiter (rejets, erreurs, identifiants manquants)"
        labelHistorique="Dernières soumissions sans incident"
        titreVide="Aucune soumission en difficulté"
        descriptionVide="Toutes les soumissions Chorus Pro suivent leur cours."
        iconeVide={<FileStack />}
      />

      <ChorusSubmissionDetailDialog
        submission={detail}
        open={!!detail}
        onClose={() => setDetail(null)}
      />
    </div>
  );
}

function KpiCard({ label, value, color }: { label: string; value: string | number; color?: string }) {
  return (
    <div className="card-base text-center">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className={`text-2xl font-bold ${color ?? 'text-foreground'}`}>{value}</p>
    </div>
  );
}

/* ── Submissions ── */
function SubmissionsChorus() {
  const [subs, setSubs] = useState<Submission[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [detail, setDetail] = useState<Submission | null>(null);
  const [resubmitLoading, setResubmitLoading] = useState(false);
  // Structure « file de travail » répliquée (état conservé malgré le rechargement plein écran après resubmit)
  const [historiqueOuvert, setHistoriqueOuvert] = useState(false);

  const charger = async () => {
    setLoading(true);
    const { data } = await supabase.from('chorus_submissions' as any)
      .select(SELECT_SUBMISSIONS)
      .order('created_at', { ascending: false })
      .limit(200);
    if (data) setSubs(data as unknown as Submission[]);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  // Une recherche ou un filtre actif porte souvent sur l'historique : on l'ouvre automatiquement.
  useEffect(() => {
    if (search || statusFilter) setHistoriqueOuvert(true);
  }, [search, statusFilter]);

  const filtered = useMemo(() => subs.filter(s => {
    if (statusFilter && s.status !== statusFilter) return false;
    if (search) {
      const q = search.toLowerCase();
      const hay = [
        s.facture?.numero_facture,
        s.facture?.etablissement?.nom,
        s.facture?.soignant ? `${s.facture.soignant.prenom} ${s.facture.soignant.nom}` : '',
      ].join(' ').toLowerCase();
      return hay.includes(q);
    }
    return true;
  }), [subs, statusFilter, search]);

  // À traiter : rejets, erreurs, identifiants manquants — plus anciennes d'abord. Le reste en historique.
  const { aTraiter, historique } = useMemo(() => ({
    aTraiter: filtered.filter(s => estATraiter(s.status)).sort((a, b) => a.created_at.localeCompare(b.created_at)),
    historique: filtered.filter(s => !estATraiter(s.status)),
  }), [filtered]);

  const resubmit = async (factureId: string) => {
    if (!confirm('Soumettre à nouveau cette facture à Chorus Pro ? La soumission précédente sera réinitialisée.')) return;
    setResubmitLoading(true);
    try {
      const { data: resetRes, error: resetErr } = await supabase.rpc('fn_admin_chorus_submission_reset' as any, { p_facture_honoraire_id: factureId });
      if (resetErr || (resetRes as any)?.error) {
        toast.error((resetRes as any)?.error ?? resetErr?.message ?? 'Erreur reset');
        setResubmitLoading(false);
        return;
      }
      const { data: subRes, error: subErr } = await supabase.functions.invoke('submit-to-chorus', {
        body: { facture_honoraire_id: factureId },
      });
      if (subErr) throw subErr;
      const d: any = subRes;
      if (d.success || d.accepted) {
        toast.success(`Nouvelle soumission envoyée : ${d.message ?? 'traité'}`);
        setDetail(null);
        await charger();
      } else {
        toast.error(`Échec de la nouvelle soumission : ${d.error ?? 'voir le détail'}`);
      }
    } catch (err: any) {
      const msg = await messageErreurEdgeFn(err, 'Erreur lors de la soumission Chorus Pro.');
      toast.error(`Erreur : ${msg}`);
    }
    setResubmitLoading(false);
  };

  const renduListe = (items: Submission[]) => (
    <>
      {/* Desktop : table 8 cols */}
      <div className="hidden md:block card-base overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-muted-foreground border-b">
              <th className="py-2 pr-2">Créée</th>
              <th className="py-2 pr-2">Facture</th>
              <th className="py-2 pr-2">Étab</th>
              <th className="py-2 pr-2">Soignant</th>
              <th className="py-2 pr-2">Type</th>
              <th className="py-2 pr-2">Statut</th>
              <th className="py-2 pr-2">Sync</th>
              <th className="py-2">Action</th>
            </tr>
          </thead>
          <tbody>
            {items.map(s => {
              const b = badgeStatut(s.status);
              return (
                <tr key={s.id} className="border-b hover:bg-muted/30">
                  <td className="py-2 pr-2 text-xs text-muted-foreground">{fmtDate(s.created_at)}</td>
                  <td className="py-2 pr-2 font-medium">{s.facture?.numero_facture ?? s.invoice_id.slice(0, 8)}</td>
                  <td className="py-2 pr-2">{s.facture?.etablissement?.nom ?? '—'}</td>
                  <td className="py-2 pr-2">{s.facture?.soignant ? `${s.facture.soignant.prenom} ${s.facture.soignant.nom}` : '—'}</td>
                  <td className="py-2 pr-2 text-xs">{s.type_document ?? '—'}</td>
                  <td className="py-2 pr-2"><span className={`badge-base text-[10px] ${b.classes}`}>{b.label}</span></td>
                  <td className="py-2 pr-2 text-xs text-muted-foreground">{fmtDate(s.last_checked_at)}</td>
                  <td className="py-2">
                    <BoutonY2K variant="ghost" size="sm" onClick={() => setDetail(s)}>Détail</BoutonY2K>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Mobile : cards */}
      <div className="md:hidden space-y-3">
        {items.map(s => {
          const b = badgeStatut(s.status);
          return (
            <div key={s.id} className="rounded-xl border border-border bg-card p-3 space-y-2">
              <div className="flex items-start justify-between gap-2">
                <p className="text-sm font-semibold truncate">{s.facture?.numero_facture ?? s.invoice_id.slice(0, 8)}</p>
                <span className={`badge-base text-[10px] shrink-0 ${b.classes}`}>{b.label}</span>
              </div>
              <div className="grid grid-cols-1 gap-1 text-xs">
                <div className="flex items-start justify-between gap-2">
                  <span className="text-muted-foreground shrink-0">Étab</span>
                  <span className="text-foreground text-right truncate">{s.facture?.etablissement?.nom ?? '—'}</span>
                </div>
                <div className="flex items-start justify-between gap-2">
                  <span className="text-muted-foreground shrink-0">Soignant</span>
                  <span className="text-foreground text-right truncate">{s.facture?.soignant ? `${s.facture.soignant.prenom} ${s.facture.soignant.nom}` : '—'}</span>
                </div>
                <div className="flex items-start justify-between gap-2">
                  <span className="text-muted-foreground shrink-0">Type</span>
                  <span className="text-foreground text-right">{s.type_document ?? '—'}</span>
                </div>
              </div>
              <div className="flex items-center justify-between text-[10px] text-muted-foreground">
                <span>Créée {fmtDate(s.created_at)}</span>
                {s.last_checked_at && <span>Sync {fmtDate(s.last_checked_at)}</span>}
              </div>
              <BoutonY2K variant="secondary" size="sm" className="w-full min-h-[36px]" onClick={() => setDetail(s)}>
                Voir le détail
              </BoutonY2K>
            </div>
          );
        })}
      </div>
    </>
  );

  return (
    <div className="space-y-3">
      <div className="flex flex-col sm:flex-row gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input value={search} onChange={e => setSearch(e.target.value)} placeholder="Rechercher (facture, étab, soignant)…" className="pl-9" />
        </div>
        <select
          value={statusFilter}
          onChange={e => setStatusFilter(e.target.value)}
          className="input-base sm:w-48"
        >
          <option value="">Tous les statuts</option>
          <option value="pending_credentials">Identifiants manquants</option>
          <option value="pending">En attente</option>
          <option value="submitted">Déposée</option>
          <option value="accepted">Acceptée</option>
          <option value="rejected">Rejetée</option>
          <option value="error">Erreur</option>
        </select>
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground text-center py-8">Chargement…</p>
      ) : filtered.length === 0 ? (
        <p className="text-sm text-muted-foreground text-center py-8">Aucune soumission{search || statusFilter ? ' ne correspond à vos critères' : ''}.</p>
      ) : (
        <div className="space-y-6">
          {/* ── À traiter : toujours visible, en tête ── */}
          <section aria-label="À traiter">
            <h2 className="flex items-center gap-2 text-sm font-bold text-foreground mb-3">
              {aTraiter.length > 0 ? (
                <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold">
                  {aTraiter.length}
                </span>
              ) : (
                <CheckCircle2 className="h-4 w-4 text-emerald-500" />
              )}
              À traiter (rejets, erreurs, identifiants manquants)
            </h2>
            {aTraiter.length === 0 ? (
              <EmptyState
                icone={<CheckCircle2 />}
                titre="Aucune soumission à traiter"
                description="Toutes les soumissions Chorus Pro suivent leur cours."
                variant="success"
                compact
              />
            ) : renduListe(aTraiter)}
          </section>

          {/* ── Historique : replié par défaut ── */}
          <section aria-label="Historique">
            <button
              type="button"
              onClick={() => setHistoriqueOuvert(o => !o)}
              aria-expanded={historiqueOuvert}
              className="flex items-center gap-2 text-sm font-semibold text-muted-foreground hover:text-foreground transition-colors mb-3"
            >
              <History className="h-4 w-4" />
              Historique
              <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-muted text-muted-foreground text-[11px] font-semibold">
                {historique.length}
              </span>
              <ChevronDown className={`h-4 w-4 transition-transform ${historiqueOuvert ? 'rotate-180' : ''}`} />
            </button>
            {historiqueOuvert && (
              historique.length === 0
                ? <p className="text-sm text-muted-foreground">Aucune soumission dans l'historique.</p>
                : renduListe(historique)
            )}
          </section>
        </div>
      )}

      <ChorusSubmissionDetailDialog
        submission={detail}
        open={!!detail}
        onClose={() => setDetail(null)}
        onResubmit={resubmit}
        resubmitLoading={resubmitLoading}
      />
    </div>
  );
}

/* ── Config étabs ── */
function ConfigEtabsChorus() {
  const [etabs, setEtabs] = useState<Etab[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<{ etab: Etab } | null>(null);

  const charger = async () => {
    setLoading(true);
    const { data } = await supabase.from('etablissements' as any)
      .select('id, nom, siret, chorus_pro_config(*)')
      .eq('est_secteur_public', true)
      .is('supprime_le', null)
      .order('nom', { ascending: true });
    if (data) setEtabs(data as unknown as Etab[]);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const toggleActif = async (etab: Etab, nextActif: boolean) => {
    const cfg = etab.chorus_pro_config?.[0];
    if (!cfg && nextActif) {
      // Pas de config, ouvrir dialog pour créer
      setEditing({ etab });
      return;
    }
    const { data, error } = await supabase.rpc('fn_admin_chorus_config_toggle' as any, {
      p_etablissement_id: etab.id,
      p_actif: nextActif,
      p_numero_structure: cfg?.numero_structure ?? null,
      p_code_service: cfg?.code_service ?? null,
      p_identifiant_cpro: cfg?.identifiant_cpro ?? null,
    });
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || error?.message || 'Erreur');
      return;
    }
    toast.success(nextActif ? 'Activé' : 'Désactivé');
    await charger();
  };

  // En tête : étabs sans configuration ou inactifs (ils bloquent l'envoi de factures). Tri alphabétique conservé dans chaque section.
  const aConfigurer = etabs.filter(e => !e.chorus_pro_config?.[0]?.actif);
  const actifs = etabs.filter(e => !!e.chorus_pro_config?.[0]?.actif);

  const renduListe = (liste: Etab[]) => (
    <>
      {/* Desktop : table 6 cols */}
      <div className="hidden md:block card-base overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-muted-foreground border-b">
              <th className="py-2 pr-2">Étab</th>
              <th className="py-2 pr-2">SIRET</th>
              <th className="py-2 pr-2">Num. structure</th>
              <th className="py-2 pr-2">Code service</th>
              <th className="py-2 pr-2">Actif</th>
              <th className="py-2">Action</th>
            </tr>
          </thead>
          <tbody>
            {liste.map(e => {
              const cfg = e.chorus_pro_config?.[0];
              return (
                <tr key={e.id} className="border-b hover:bg-muted/30">
                  <td className="py-2 pr-2 font-medium">{e.nom}</td>
                  <td className="py-2 pr-2 text-xs">{e.siret ?? '—'}</td>
                  <td className="py-2 pr-2 text-xs">{cfg?.numero_structure ?? <span className="text-muted-foreground italic">non configuré</span>}</td>
                  <td className="py-2 pr-2 text-xs">{cfg?.code_service ?? '—'}</td>
                  <td className="py-2 pr-2">
                    <Switch checked={!!cfg?.actif} onCheckedChange={v => toggleActif(e, v)} />
                  </td>
                  <td className="py-2">
                    <BoutonY2K variant="ghost" size="sm" onClick={() => setEditing({ etab: e })} iconeGauche={<Settings className="h-3.5 w-3.5" />}>
                      Éditer
                    </BoutonY2K>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Mobile : cards */}
      <div className="md:hidden space-y-3">
        {liste.map(e => {
          const cfg = e.chorus_pro_config?.[0];
          return (
            <div key={e.id} className="rounded-xl border border-border bg-card p-3 space-y-2">
              <div className="flex items-start justify-between gap-2">
                <p className="text-sm font-semibold truncate">{e.nom}</p>
                <Switch checked={!!cfg?.actif} onCheckedChange={v => toggleActif(e, v)} />
              </div>
              <div className="grid grid-cols-1 gap-1 text-xs">
                <div className="flex items-start justify-between gap-2">
                  <span className="text-muted-foreground shrink-0">SIRET</span>
                  <span className="text-foreground text-right font-mono">{e.siret ?? '—'}</span>
                </div>
                <div className="flex items-start justify-between gap-2">
                  <span className="text-muted-foreground shrink-0">Num. structure</span>
                  <span className="text-foreground text-right">
                    {cfg?.numero_structure ?? <span className="italic text-muted-foreground">non configuré</span>}
                  </span>
                </div>
                <div className="flex items-start justify-between gap-2">
                  <span className="text-muted-foreground shrink-0">Code service</span>
                  <span className="text-foreground text-right">{cfg?.code_service ?? '—'}</span>
                </div>
              </div>
              <BoutonY2K variant="secondary" size="sm" className="w-full min-h-[36px]" onClick={() => setEditing({ etab: e })} iconeGauche={<Settings className="h-3.5 w-3.5" />}>
                Éditer la configuration
              </BoutonY2K>
            </div>
          );
        })}
      </div>
    </>
  );

  if (loading) return <p className="text-sm text-muted-foreground text-center py-8">Chargement…</p>;
  if (etabs.length === 0) return <p className="text-sm text-muted-foreground text-center py-8">Aucun établissement secteur public.</p>;

  return (
    <div className="space-y-6">
      <p className="text-sm text-muted-foreground">{etabs.length} établissements secteur public. Activez Chorus Pro et configurez le numéro de structure pour chaque étab destinataire.</p>

      {/* ── À configurer : sans configuration ou inactifs, en tête ── */}
      <section aria-label="À configurer">
        <h2 className="flex items-center gap-2 text-sm font-bold text-foreground mb-1">
          {aConfigurer.length > 0 ? (
            <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-destructive text-destructive-foreground text-[11px] font-bold">
              {aConfigurer.length}
            </span>
          ) : (
            <CheckCircle2 className="h-4 w-4 text-emerald-500" />
          )}
          À configurer
        </h2>
        <p className="text-xs text-muted-foreground mb-3">Ces établissements n'ont pas de configuration Chorus Pro active : l'envoi de leurs factures est bloqué.</p>
        {aConfigurer.length === 0 ? (
          <EmptyState
            icone={<CheckCircle2 />}
            titre="Tous les établissements sont configurés"
            description="Chorus Pro est actif pour tous les établissements secteur public."
            variant="success"
            compact
          />
        ) : renduListe(aConfigurer)}
      </section>

      {/* ── Configurés et actifs : visibles en dessous (le switch doit rester accessible) ── */}
      {actifs.length > 0 && (
        <section aria-label="Configurés et actifs">
          <h2 className="flex items-center gap-2 text-sm font-semibold text-muted-foreground mb-3">
            <CheckCircle2 className="h-4 w-4 text-success" />
            Configurés et actifs
            <span className="inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-muted text-muted-foreground text-[11px] font-semibold">
              {actifs.length}
            </span>
          </h2>
          {renduListe(actifs)}
        </section>
      )}

      {editing && (
        <ChorusConfigEtabDialog
          etabId={editing.etab.id}
          etabNom={editing.etab.nom}
          config={editing.etab.chorus_pro_config?.[0] ? { ...editing.etab.chorus_pro_config[0], etablissement_id: editing.etab.id } : null}
          open={!!editing}
          onClose={() => setEditing(null)}
          onSaved={charger}
        />
      )}
    </div>
  );
}
