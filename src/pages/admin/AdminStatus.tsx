import { useState, useEffect } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { usePageTitle } from '@/hooks/usePageTitle';
import { Activity, AlertCircle, AlertTriangle, CheckCircle, Clock, ExternalLink, RefreshCw } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
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
    const { error } = await supabase.from('alertes_systeme').update({ resolu_le: new Date().toISOString() }).eq('id', alerteId);
    if (error) { toast.error('Erreur'); return; }
    toast.success('Alerte résolue');
    charger();
  };

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;
  if (!data) return <LayoutAdmin><div className="p-6 text-destructive">Erreur chargement health check</div></LayoutAdmin>;

  const cronsCritiques = data.crons.crons.filter(c => c.echec);
  const cronsRetard = data.crons.crons.filter(c => c.retard && !c.echec);
  const cronsOk = data.crons.crons.filter(c => !c.retard && !c.echec);

  const severiteBadge = (s: string) => s === 'CRITICAL' ? 'bg-destructive/10 text-destructive border-destructive/30'
    : s === 'WARNING' ? 'bg-warning/10 text-warning border-warning/30'
    : 'bg-info/10 text-info border-info/30';

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
                <Badge variant="outline" className={`text-[10px] ${severiteBadge(a.severite)}`}>{a.severite}</Badge>
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
                      {c.echec ? <Badge className="bg-destructive/10 text-destructive border-destructive/30 text-[10px]"><AlertCircle className="h-3 w-3 mr-1" />Échec</Badge>
                        : c.retard ? <Badge className="bg-warning/10 text-warning border-warning/30 text-[10px]"><AlertTriangle className="h-3 w-3 mr-1" />Retard</Badge>
                        : <Badge className="bg-success/10 text-success border-success/30 text-[10px]"><CheckCircle className="h-3 w-3 mr-1" />OK</Badge>}
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
    </LayoutAdmin>
  );
}
