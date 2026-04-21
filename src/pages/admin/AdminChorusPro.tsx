import { useState, useEffect, useMemo } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { FileStack, RefreshCw, Search, Settings } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { getChorusStatutBadge } from '@/lib/chorus-helpers';
import { ChorusSubmissionDetailDialog } from '@/components/admin/ChorusSubmissionDetailDialog';
import { ChorusConfigEtabDialog } from '@/components/admin/ChorusConfigEtabDialog';

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

export default function AdminChorusPro() {
  usePageTitle('Chorus Pro — Admin');

  const [tab, setTab] = useState('dashboard');
  const [syncing, setSyncing] = useState(false);

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
      toast.error(`Erreur sync : ${err.message ?? 'inconnu'}`);
    }
    setSyncing(false);
  };

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin items={[{ label: 'Chorus Pro' }]} />
      <div className="flex items-center justify-between gap-3 mb-6">
        <div className="flex items-center gap-3">
          <FileStack className="h-7 w-7 text-primary" />
          <h1 className="text-2xl font-bold text-foreground">Chorus Pro</h1>
        </div>
        <Button onClick={syncNow} disabled={syncing} variant="outline">
          <RefreshCw className={`h-4 w-4 mr-2 ${syncing ? 'animate-spin' : ''}`} />
          {syncing ? 'Sync en cours…' : 'Sync maintenant'}
        </Button>
      </div>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="mb-4">
          <TabsTrigger value="dashboard">Dashboard</TabsTrigger>
          <TabsTrigger value="submissions">Submissions</TabsTrigger>
          <TabsTrigger value="config">Config établissements</TabsTrigger>
        </TabsList>

        <TabsContent value="dashboard"><DashboardChorus /></TabsContent>
        <TabsContent value="submissions"><SubmissionsChorus /></TabsContent>
        <TabsContent value="config"><ConfigEtabsChorus /></TabsContent>
      </Tabs>
    </LayoutAdmin>
  );
}

/* ── Dashboard ── */
function DashboardChorus() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [recent, setRecent] = useState<Submission[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      supabase.rpc('fn_admin_chorus_stats' as any),
      supabase.from('chorus_submissions' as any)
        .select(`*, facture:factures_honoraires!invoice_id(numero_facture, montant_ttc, soignant:soignants(prenom, nom), etablissement:etablissements(nom))`)
        .order('created_at', { ascending: false })
        .limit(10),
    ]).then(([sRes, rRes]) => {
      if (sRes.data && !(sRes.data as any).error) setStats(sRes.data as Stats);
      if (rRes.data) setRecent(rRes.data as unknown as Submission[]);
      setLoading(false);
    }).catch(() => setLoading(false));
  }, []);

  if (loading) return <p className="text-sm text-muted-foreground text-center py-8">Chargement…</p>;
  if (!stats) return <p className="text-sm text-destructive text-center py-8">Accès refusé ou erreur chargement stats.</p>;

  const enCours = (stats.par_statut.pending ?? 0) + (stats.par_statut.submitted ?? 0);
  const acceptees = stats.par_statut.accepted ?? 0;
  const rejetees = (stats.par_statut.rejected ?? 0) + (stats.par_statut.error ?? 0);

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        <KpiCard label="Total submissions" value={stats.total_submissions} />
        <KpiCard label="En cours" value={enCours} color="text-warning" />
        <KpiCard label="Acceptées" value={acceptees} color="text-success" />
        <KpiCard label="Rejetées/Err" value={rejetees} color="text-destructive" />
        <KpiCard label="Erreurs 7j" value={stats.erreurs_7j} color="text-destructive" />
        <KpiCard label="Étabs configs" value={`${stats.etabs_configures_actifs}/${stats.etabs_secteur_public_total}`} />
      </div>
      <p className="text-xs text-muted-foreground">Dernière sync : {fmtDate(stats.derniere_sync)}</p>

      <section className="card-base">
        <h2 className="font-semibold text-foreground mb-3">10 dernières submissions</h2>
        {recent.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucune soumission.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-muted-foreground border-b">
                  <th className="py-2 pr-2">Créée</th>
                  <th className="py-2 pr-2">Facture</th>
                  <th className="py-2 pr-2">Étab</th>
                  <th className="py-2 pr-2">Type</th>
                  <th className="py-2">Statut</th>
                </tr>
              </thead>
              <tbody>
                {recent.map(s => {
                  const b = getChorusStatutBadge(s.status);
                  return (
                    <tr key={s.id} className="border-b hover:bg-muted/30">
                      <td className="py-2 pr-2 text-xs text-muted-foreground">{fmtDate(s.created_at)}</td>
                      <td className="py-2 pr-2">{s.facture?.numero_facture ?? s.invoice_id.slice(0, 8)}</td>
                      <td className="py-2 pr-2">{s.facture?.etablissement?.nom ?? '—'}</td>
                      <td className="py-2 pr-2">{s.type_document ?? '—'}</td>
                      <td className="py-2"><span className={`badge-base text-[10px] ${b.classes}`}>{b.label}</span></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
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

  const charger = async () => {
    setLoading(true);
    const { data } = await supabase.from('chorus_submissions' as any)
      .select(`*, facture:factures_honoraires!invoice_id(numero_facture, montant_ttc, soignant:soignants(prenom, nom), etablissement:etablissements(nom))`)
      .order('created_at', { ascending: false })
      .limit(200);
    if (data) setSubs(data as unknown as Submission[]);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

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

  const resubmit = async (factureId: string) => {
    if (!confirm('Reset de l\'idempotence + re-soumettre cette facture à Chorus Pro ?')) return;
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
        toast.success(`Resubmit OK : ${d.message ?? 'traité'}`);
        setDetail(null);
        await charger();
      } else {
        toast.error(`Resubmit erreur : ${d.error ?? 'voir logs'}`);
      }
    } catch (err: any) {
      toast.error(`Erreur : ${err.message ?? 'inconnu'}`);
    }
    setResubmitLoading(false);
  };

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
          <option value="pending_credentials">Credentials manquants</option>
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
        <p className="text-sm text-muted-foreground text-center py-8">Aucune soumission.</p>
      ) : (
        <div className="card-base overflow-x-auto">
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
              {filtered.map(s => {
                const b = getChorusStatutBadge(s.status);
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
                      <Button variant="ghost" size="sm" onClick={() => setDetail(s)}>Détail</Button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
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
    const { error } = await supabase.from('chorus_pro_config' as any).upsert({
      etablissement_id: etab.id,
      numero_structure: cfg?.numero_structure ?? null,
      code_service: cfg?.code_service ?? null,
      identifiant_cpro: cfg?.identifiant_cpro ?? null,
      actif: nextActif,
    }, { onConflict: 'etablissement_id' });
    if (error) { toast.error(error.message); return; }
    toast.success(nextActif ? 'Activé' : 'Désactivé');
    await charger();
  };

  if (loading) return <p className="text-sm text-muted-foreground text-center py-8">Chargement…</p>;
  if (etabs.length === 0) return <p className="text-sm text-muted-foreground text-center py-8">Aucun établissement secteur public.</p>;

  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">{etabs.length} établissements secteur public. Activez Chorus Pro et configurez le numéro de structure pour chaque étab destinataire.</p>

      <div className="card-base overflow-x-auto">
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
            {etabs.map(e => {
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
                    <Button variant="ghost" size="sm" onClick={() => setEditing({ etab: e })}>
                      <Settings className="h-3.5 w-3.5 mr-1" /> Éditer
                    </Button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

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
