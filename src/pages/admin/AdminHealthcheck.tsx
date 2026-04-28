import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { CheckCircle, XCircle, Clock, RefreshCw, Server, Database, Mail, CreditCard, Shield, Smartphone, Globe } from 'lucide-react';

interface ServiceStatus {
  name: string;
  icon: any;
  status: 'ok' | 'error' | 'loading' | 'degraded';
  latency?: number;
  detail?: string;
}

export default function AdminHealthcheck() {
  usePageTitle('Healthcheck Services');
  const [services, setServices] = useState<ServiceStatus[]>([]);
  const [checking, setChecking] = useState(false);
  const [lastCheck, setLastCheck] = useState<Date | null>(null);

  const checkAll = async () => {
    setChecking(true);
    const results: ServiceStatus[] = [];

    // 1. Supabase DB
    const dbStart = Date.now();
    try {
      const { error } = await supabase.from('health_check').select('id').limit(1);
      results.push({ name: 'Supabase PostgreSQL', icon: Database, status: error ? 'error' : 'ok', latency: Date.now() - dbStart, detail: error?.message });
    } catch (e: any) {
      results.push({ name: 'Supabase PostgreSQL', icon: Database, status: 'error', latency: Date.now() - dbStart, detail: e.message });
    }

    // 2. Supabase Auth
    const authStart = Date.now();
    try {
      const { data } = await supabase.auth.getSession();
      results.push({ name: 'Supabase Auth', icon: Shield, status: data?.session ? 'ok' : 'degraded', latency: Date.now() - authStart, detail: data?.session ? 'Session active' : 'Pas de session' });
    } catch (e: any) {
      results.push({ name: 'Supabase Auth', icon: Shield, status: 'error', latency: Date.now() - authStart, detail: e.message });
    }

    // 3. Edge Functions (health-check)
    const efStart = Date.now();
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/health-check`, { method: 'HEAD' });
      results.push({ name: 'Edge Functions', icon: Server, status: res.status < 500 ? 'ok' : 'error', latency: Date.now() - efStart, detail: `HTTP ${res.status}` });
    } catch (e: any) {
      results.push({ name: 'Edge Functions', icon: Server, status: 'error', latency: Date.now() - efStart, detail: e.message });
    }

    // 4. Stripe (check if key is configured)
    try {
      const stripeKey = import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY;
      results.push({ name: 'Stripe', icon: CreditCard, status: stripeKey ? 'ok' : 'degraded', detail: stripeKey ? 'Clé configurée' : 'VITE_STRIPE_PUBLISHABLE_KEY manquante' });
    } catch {
      results.push({ name: 'Stripe', icon: CreditCard, status: 'error', detail: 'Erreur config' });
    }

    // 5. Twilio SMS
    const smsStart = Date.now();
    try {
      const { data } = await supabase.functions.invoke('send-sms', { body: { warm: true } });
      results.push({ name: 'Twilio SMS', icon: Smartphone, status: 'ok', latency: Date.now() - smsStart, detail: data?.warm ? 'Warm ping OK' : 'Réponse inattendue' });
    } catch (e: any) {
      results.push({ name: 'Twilio SMS', icon: Smartphone, status: 'error', latency: Date.now() - smsStart, detail: e.message });
    }

    // 6. Document AI (verify-document warm ping)
    const aiStart = Date.now();
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/verify-document`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ warm: true }),
      });
      const data = await res.json();
      results.push({ name: 'Document AI', icon: Globe, status: data?.warm ? 'ok' : 'degraded', latency: Date.now() - aiStart, detail: data?.warm ? 'Warm ping OK' : `HTTP ${res.status}` });
    } catch (e: any) {
      results.push({ name: 'Document AI', icon: Globe, status: 'error', latency: Date.now() - aiStart, detail: e.message });
    }

    // 7. Email (send-email warm)
    const emailStart = Date.now();
    try {
      await supabase.functions.invoke('send-email', { body: { warm: true } });
      results.push({ name: 'Resend Email', icon: Mail, status: 'ok', latency: Date.now() - emailStart, detail: 'Warm ping OK' });
    } catch (e: any) {
      results.push({ name: 'Resend Email', icon: Mail, status: 'error', latency: Date.now() - emailStart, detail: e.message });
    }

    // 8. Sentry
    const sentryDsn = import.meta.env.VITE_SENTRY_DSN;
    results.push({ name: 'Sentry Monitoring', icon: Shield, status: sentryDsn ? 'ok' : 'degraded', detail: sentryDsn ? 'DSN configuré' : 'VITE_SENTRY_DSN manquante' });

    setServices(results);
    setLastCheck(new Date());
    setChecking(false);
  };

  useEffect(() => { checkAll(); }, []);

  const statusColor = (s: string) => s === 'ok' ? 'text-success' : s === 'degraded' ? 'text-warning' : s === 'error' ? 'text-destructive' : 'text-muted-foreground';
  const statusIcon = (s: string) => s === 'ok' ? CheckCircle : s === 'error' ? XCircle : Clock;
  const okCount = services.filter(s => s.status === 'ok').length;
  const totalCount = services.length;

  return (
    <LayoutAdmin>
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-6 gap-3">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2"><Server className="h-5 w-5 text-primary" /> Healthcheck Services</h1>
          <p className="text-sm text-muted-foreground">
            {totalCount > 0 ? `${okCount}/${totalCount} services opérationnels` : 'Vérification en cours...'}
            {lastCheck && ` — dernière vérification ${lastCheck.toLocaleTimeString('fr-FR')}`}
          </p>
        </div>
        <button onClick={checkAll} disabled={checking} className="btn-primary flex items-center gap-2 disabled:opacity-50">
          <RefreshCw className={`h-4 w-4 ${checking ? 'animate-spin' : ''}`} />
          {checking ? 'Vérification...' : 'Revérifier'}
        </button>
      </div>

      {/* Overall status */}
      {totalCount > 0 && (
        <div className={`card-base mb-6 p-4 border-l-4 ${okCount === totalCount ? 'border-success bg-success/5' : okCount > totalCount / 2 ? 'border-warning bg-warning/5' : 'border-destructive bg-destructive/5'}`}>
          <p className="text-lg font-bold text-foreground">
            {okCount === totalCount ? 'Tous les services sont opérationnels' : `${totalCount - okCount} service(s) en alerte`}
          </p>
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        {services.map((svc, i) => {
          const StatusIcon = statusIcon(svc.status);
          return (
            <div key={i} className="card-base p-4">
              <div className="flex items-center gap-3 mb-2">
                <svc.icon className={`h-5 w-5 ${statusColor(svc.status)}`} />
                <span className="text-sm font-semibold text-foreground">{svc.name}</span>
              </div>
              <div className="flex items-center gap-2">
                <StatusIcon className={`h-4 w-4 ${statusColor(svc.status)}`} />
                <span className={`text-xs font-medium ${statusColor(svc.status)}`}>
                  {svc.status === 'ok' ? 'Opérationnel' : svc.status === 'degraded' ? 'Dégradé' : svc.status === 'error' ? 'Erreur' : 'Vérification...'}
                </span>
                {svc.latency != null && <span className="text-[10px] text-muted-foreground ml-auto">{svc.latency}ms</span>}
              </div>
              {svc.detail && <p className="text-[10px] text-muted-foreground mt-1 truncate">{svc.detail}</p>}
            </div>
          );
        })}
      </div>
    </LayoutAdmin>
  );
}
