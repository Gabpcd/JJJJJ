import { useState, useEffect } from 'react';
import * as Sentry from '@sentry/react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Activity, AlertCircle, AlertTriangle, Bug, CheckCircle, Clock, ExternalLink, RefreshCw } from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

type CronInfo = {
  jobid: number;
  jobname: string;
  schedule: string;
  dernier_run: string | null;
  dernier_statut: string | null;
  retard: boolean;
  echec: boolean;
};

type AlerteInfo = {
  id: string;
  type: string;
  severite: 'INFO' | 'WARNING' | 'CRITICAL';
  source: string;
  message: string;
  cree_le: string;
};

type HealthData = {
  timestamp: string;
  database: { connected: boolean; version: string };
  crons: { crons: CronInfo[]; alertes_emises: number };
  stripe_webhooks: { total_24h: number; avec_erreur: number; non_traites: number; taux_erreur_pct: number };
  alertes_actives: AlerteInfo[];
  stats_temps_reel: {
    soignants_actifs_7j: number;
    missions_ouvertes: number;
    missions_assignees: number;
    missions_en_cours: number;
    candidatures_pending: number;
    litiges_ouverts: number;
  };
  logs_recents: { audit_24h: number; emails_24h: number; sms_24h: number; notifications_24h: number };
};

export default function AdminStatus() {
  usePageTitle('Status système');
  const [data, setData] = useState<HealthData | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const charger = async () => {
    setRefreshing(true);
    const { data: result, error } = await supabase.rpc('fn_admin_health_check' as any);
    setRefreshing(false);
    setLoading(false);
    if (error || (result as any)?.error) {
      toast.error((result as any)?.error || 'Erreur chargement health check');
      return;
    }
    setData(result as unknown as HealthData);
  };

  useEffect(() => {
    charger();
    const t = setInterval(charger, 60_000);
    return () => clearInterval(t);
  }, []);

  const resoudre = async (alerteId: string) => {
    const { data, error } = await supabase.rpc('fn_admin_resoudre_alerte' as any, { p_alerte_id: alerteId });
    if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Erreur'); return; }
    toast.success('Alerte résolue');
    charger();
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;
  if (!data) return <LayoutAdmin><div className="p-6 text-destructive">Erreur chargement health check</div></LayoutAdmin>;

  const cronsCritiques = data.crons.crons.filter(c => c.echec);
  const cronsRetard = data.crons.crons.filter(c => c.retard && !c.echec);
  const cronsOk = data.crons.crons.filter(c => !c.retard && !c.echec);

  const severiteVariant = (s: string): 'error' | 'warning' | 'info' => s === 'CRITICAL' ? 'error'
    : s === 'WARNING' ? 'warning'
    : 'info';

  return (
    <LayoutAdmin>
      <div className="flex items-start justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold flex items-center gap-2">
            <Activity className="h-6 w-6 text-primary" /> Status système
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Dernière vérification : {format(new Date(data.timestamp), 'd MMM yyyy HH:mm:ss', { locale: fr })}
          </p>
        </div>
        <Button onClick={charger} disabled={refreshing} variant="outline" size="sm" className="gap-1.5">
          <RefreshCw className={`h-3.5 w-3.5 ${refreshing ? 'animate-spin' : ''}`} /> Refresh
        </Button>
      </div>

      {/* Alertes actives */}
      {data.alertes_actives.length > 0 && (
        <Card className="mb-4 border-destructive/30">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2 text-destructive">
              <AlertCircle className="h-4 w-4" /> Alertes actives ({data.alertes_actives.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {data.alertes_actives.map(a => (
              <div key={a.id} className="flex items-start gap-2 p-2 rounded-lg bg-muted/30">
                <BadgeY2K variant={severiteVariant(a.severite)} size="sm">{a.severite}</BadgeY2K>
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-semibold">{a.type} — {a.source}</p>
                  <p className="text-xs text-muted-foreground line-clamp-2">{a.message}</p>
                  <p className="text-[10px] text-muted-foreground mt-0.5">
                    {format(new Date(a.cree_le), 'd MMM HH:mm', { locale: fr })}
                  </p>
                </div>
                <Button size="sm" variant="ghost" onClick={() => resoudre(a.id)}>Résoudre</Button>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {/* Health checks systèmes */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-4">
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm flex items-center gap-2"><CheckCircle className="h-4 w-4 text-success" /> Database</CardTitle></CardHeader>
          <CardContent><p className="text-xs text-muted-foreground">PG {data.database.version.split(' ')[0]}</p></CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm flex items-center gap-2"><Clock className="h-4 w-4 text-info" /> Crons actifs</CardTitle></CardHeader>
          <CardContent>
            <div className="flex gap-2 text-xs">
              <span className="text-success font-semibold">{cronsOk.length} OK</span>
              {cronsRetard.length > 0 && <span className="text-warning font-semibold">{cronsRetard.length} retard</span>}
              {cronsCritiques.length > 0 && <span className="text-destructive font-semibold">{cronsCritiques.length} échec</span>}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm flex items-center gap-2"><Activity className="h-4 w-4 text-primary" /> Stripe Webhooks 24h</CardTitle></CardHeader>
          <CardContent>
            <p className="text-xs">{data.stripe_webhooks.total_24h} reçus · {data.stripe_webhooks.taux_erreur_pct}% erreur</p>
          </CardContent>
        </Card>
      </div>

      {/* Stats temps réel */}
      <Card className="mb-4">
        <CardHeader className="pb-2"><CardTitle className="text-base">Stats temps réel</CardTitle></CardHeader>
        <CardContent className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 text-xs">
          {[
            ['Soignants actifs 7j', data.stats_temps_reel.soignants_actifs_7j],
            ['Missions ouvertes', data.stats_temps_reel.missions_ouvertes],
            ['Missions assignées', data.stats_temps_reel.missions_assignees],
            ['Missions en cours', data.stats_temps_reel.missions_en_cours],
            ['Candidatures pending', data.stats_temps_reel.candidatures_pending],
            ['Litiges ouverts', data.stats_temps_reel.litiges_ouverts],
          ].map(([label, val]) => (
            <div key={label as string} className="rounded-lg bg-muted/30 p-2">
              <p className="text-muted-foreground">{label}</p>
              <p className="text-lg font-bold">{val}</p>
            </div>
          ))}
        </CardContent>
      </Card>

      {/* Logs 24h */}
      <Card className="mb-4">
        <CardHeader className="pb-2"><CardTitle className="text-base">Logs 24h</CardTitle></CardHeader>
        <CardContent className="grid grid-cols-2 md:grid-cols-4 gap-3 text-xs">
          {[
            ['Audit', data.logs_recents.audit_24h],
            ['Emails', data.logs_recents.emails_24h],
            ['SMS', data.logs_recents.sms_24h],
            ['Notifications', data.logs_recents.notifications_24h],
          ].map(([label, val]) => (
            <div key={label as string} className="rounded-lg bg-muted/30 p-2">
              <p className="text-muted-foreground">{label}</p>
              <p className="text-lg font-bold">{val}</p>
            </div>
          ))}
        </CardContent>
      </Card>

      {/* Crons détail */}
      <Card className="mb-4">
        <CardHeader className="pb-2"><CardTitle className="text-base">Crons (17 actifs)</CardTitle></CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead className="border-b border-border">
                <tr className="text-left text-muted-foreground">
                  <th className="py-1">Nom</th>
                  <th>Schedule</th>
                  <th>Dernier run</th>
                  <th>Statut</th>
                </tr>
              </thead>
              <tbody>
                {data.crons.crons.map(c => (
                  <tr key={c.jobid} className="border-b border-border/50">
                    <td className="py-1.5 font-medium">{c.jobname}</td>
                    <td className="text-muted-foreground"><code className="text-[10px]">{c.schedule}</code></td>
                    <td className="text-muted-foreground">
                      {c.dernier_run ? format(new Date(c.dernier_run), 'd MMM HH:mm', { locale: fr }) : '—'}
                    </td>
                    <td>
                      {c.echec ? <BadgeY2K variant="error" size="sm" icone={<AlertCircle className="h-3 w-3" />}>Échec</BadgeY2K>
                        : c.retard ? <BadgeY2K variant="warning" size="sm" icone={<AlertTriangle className="h-3 w-3" />}>Retard</BadgeY2K>
                        : <BadgeY2K variant="success" size="sm" icone={<CheckCircle className="h-3 w-3" />}>OK</BadgeY2K>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      {/* Liens dashboards externes */}
      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Dashboards externes</CardTitle></CardHeader>
        <CardContent className="grid grid-cols-2 md:grid-cols-3 gap-2 text-xs">
          {[
            ['Supabase', 'https://supabase.com/dashboard/project/flripxtsyegjshnhzjkz'],
            ['Vercel', 'https://vercel.com/dashboard'],
            ['Stripe', 'https://dashboard.stripe.com'],
            ['Resend', 'https://resend.com/emails'],
            ['Sentry', 'https://sentry.io/organizations/jolene'],
            ['Twilio', 'https://console.twilio.com'],
          ].map(([label, url]) => (
            <a key={url} href={url} target="_blank" rel="noopener noreferrer"
               className="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg bg-muted/30 hover:bg-muted/50 transition-colors">
              <ExternalLink className="h-3 w-3" /> {label}
            </a>
          ))}
        </CardContent>
      </Card>

      {/* Outils diagnostic */}
      <Card className="mb-4 border-warning/30">
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <Bug className="h-4 w-4 text-warning" /> Outils diagnostic
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div>
            <p className="text-xs text-muted-foreground mb-2">
              Déclenche une exception volontaire avec tag <code className="bg-muted px-1.5 py-0.5 rounded">test=true</code> pour
              vérifier la chaîne Sentry (DSN → release → sourcemaps → user context). À filtrer dans les alertes prod.
            </p>
            <Button
              size="sm"
              variant="outline"
              className="border-warning/30 text-warning hover:bg-warning/5 gap-1.5"
              onClick={() => {
                try {
                  Sentry.captureException(new Error('Sentry test event from /admin/status'), {
                    tags: { test: 'true', source: 'admin-diagnostic' },
                    level: 'info',
                  });
                  toast.success('Erreur test envoyée à Sentry. Vérifiez le dashboard.');
                } catch (e: any) {
                  toast.error(`Échec : ${e?.message || 'Sentry indisponible'}`);
                }
              }}
            >
              <Bug className="h-3.5 w-3.5" /> Déclencher erreur test Sentry
            </Button>
          </div>
          <p className="text-[11px] text-muted-foreground italic">
            ℹ️ Si la VITE_SENTRY_DSN n'est pas configurée côté Vercel, ce bouton est inactif silencieusement.
            Voir <code>docs/sentry-setup.md</code> pour activer Sentry.
          </p>
        </CardContent>
      </Card>
    </LayoutAdmin>
  );
}
