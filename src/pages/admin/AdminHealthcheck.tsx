import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { CheckCircle, XCircle, Clock, RefreshCw, Server, Database, Mail, CreditCard, Shield, Smartphone, Globe, KeyRound, Loader2, MessageSquare, Send } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';

interface ServiceStatus {
  name: string;
  icon: any;
  status: 'ok' | 'error' | 'loading' | 'degraded';
  latency?: number;
  detail?: string;
}

export default function AdminHealthcheck() {
  usePageTitle('Healthcheck Services');
  const { user } = useAuth();
  const [services, setServices] = useState<ServiceStatus[]>([]);
  const [checking, setChecking] = useState(false);
  const [lastCheck, setLastCheck] = useState<Date | null>(null);
  const [smsTesting, setSmsTesting] = useState(false);
  const [smsPhone, setSmsPhone] = useState('');
  const [smsResult, setSmsResult] = useState<null | { ok: boolean; detail: string }>(null);

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

    // 8. Sentry — masqué si DSN non configurée (activation à venir côté Vercel).
    const sentryDsn = import.meta.env.VITE_SENTRY_DSN;
    if (sentryDsn) {
      results.push({ name: 'Sentry Monitoring', icon: Shield, status: 'ok', detail: 'DSN configuré' });
    }

    setServices(results);
    setLastCheck(new Date());
    setChecking(false);
  };

  useEffect(() => { checkAll(); }, []);

  // ── Pro Santé Connect : test isolé (jour J de la bascule prod) ──
  const [pscChecking, setPscChecking] = useState(false);
  const [pscResult, setPscResult] = useState<null | {
    env: string;
    secrets_ok: boolean;
    missing_secrets: string[];
    discovery_ok: boolean;
    discovery_status: number | null;
    endpoints_match: boolean;
    endpoints_diff: string[];
    duration_ms: number;
  }>(null);

  // Charger le téléphone admin connecté pour pré-remplir le test SMS
  useEffect(() => {
    if (!user) return;
    (async () => {
      // Si l'admin est aussi inscrit comme soignant, on récupère son téléphone
      const { data } = await supabase.from('soignants').select('telephone').eq('id', user.id).maybeSingle();
      if (data && (data as any).telephone) setSmsPhone((data as any).telephone);
    })();
  }, [user]);

  const testerSMS = async () => {
    if (!smsPhone || smsPhone.replace(/\D/g, '').length < 8) {
      toast.error('Numéro invalide. Format : +33 6 XX XX XX XX');
      return;
    }
    setSmsTesting(true);
    setSmsResult(null);
    try {
      const { data, error } = await supabase.functions.invoke('send-sms', {
        body: {
          telephone: smsPhone.trim(),
          type: 'TEST_ADMIN',
          contenu: `Test SMS Jolene depuis /admin/healthcheck à ${new Date().toLocaleTimeString('fr-FR')}.`,
          // Pas de destinataire_id → pas de check sms_alertes_actives, c'est un test admin pur
        },
      });
      if (error) {
        setSmsResult({ ok: false, detail: error.message || 'Erreur invocation' });
        toast.error(`Échec : ${error.message || 'Erreur'}`);
      } else if (data?.success === false) {
        setSmsResult({ ok: false, detail: data.error || 'Twilio rejected' });
        toast.error(`Twilio rejette : ${data.error || 'Erreur'}`);
      } else if (data?.configured === false) {
        setSmsResult({ ok: false, detail: 'Twilio non configuré (TWILIO_FROM_NUMBER absent)' });
        toast.warning('Twilio non configuré');
      } else if (data?.sid) {
        setSmsResult({ ok: true, detail: `SMS envoyé · sid=${data.sid} · to=${data.to}` });
        toast.success('SMS envoyé');
      } else {
        setSmsResult({ ok: true, detail: 'Réponse inattendue : ' + JSON.stringify(data).slice(0, 200) });
      }
    } catch (e: any) {
      setSmsResult({ ok: false, detail: e?.message || String(e) });
      toast.error(`Exception : ${e?.message || e}`);
    } finally {
      setSmsTesting(false);
    }
  };

  const verifierPSC = async () => {
    setPscChecking(true);
    setPscResult(null);
    try {
      const { data, error } = await supabase.functions.invoke('psc-test-connexion', { body: {} });
      if (error) throw error;
      setPscResult(data);
      const allOk = data?.secrets_ok && data?.discovery_ok && data?.endpoints_match;
      if (allOk) {
        toast.success(`PSC OK — ${data.env} · ${data.duration_ms}ms`);
      } else if (data?.discovery_ok && !data?.secrets_ok) {
        toast.warning(`PSC : endpoint joignable mais secrets incomplets (${data.missing_secrets.length} manquants)`);
      } else {
        toast.error('PSC : configuration incomplète — voir détail ci-dessous');
      }
    } catch (e: any) {
      toast.error(`PSC : erreur — ${e?.message || e}`);
      setPscResult({
        env: 'inconnu',
        secrets_ok: false,
        missing_secrets: [],
        discovery_ok: false,
        discovery_status: null,
        endpoints_match: false,
        endpoints_diff: [`Exception : ${e?.message || e}`],
        duration_ms: 0,
      });
    } finally {
      setPscChecking(false);
    }
  };

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

      {/* ── Pro Santé Connect : diagnostic isolé (bascule prod) ── */}
      <div className="card-base mt-6 p-5">
        <div className="flex items-start justify-between gap-4 mb-4">
          <div>
            <h2 className="text-base font-bold text-foreground flex items-center gap-2">
              <KeyRound className="h-4 w-4 text-primary" />
              Pro Santé Connect
            </h2>
            <p className="text-xs text-muted-foreground mt-0.5">
              Vérifie la configuration PSC : secrets présents, OIDC discovery joignable, endpoints alignés. Outil critique le jour de la bascule prod.
            </p>
          </div>
          <button
            onClick={verifierPSC}
            disabled={pscChecking}
            className="btn-primary flex items-center gap-2 disabled:opacity-50 shrink-0"
          >
            {pscChecking ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
            {pscChecking ? 'Vérification…' : 'Vérifier connexion PSC'}
          </button>
        </div>

        {pscResult && (
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="p-3 rounded-lg border border-border bg-muted/20">
              <p className="text-[10px] uppercase text-muted-foreground tracking-wide">Environnement</p>
              <p className="text-sm font-semibold text-foreground mt-1">{pscResult.env}</p>
            </div>
            <div className={`p-3 rounded-lg border ${pscResult.secrets_ok ? 'border-success/30 bg-success/5' : 'border-destructive/30 bg-destructive/5'}`}>
              <p className="text-[10px] uppercase text-muted-foreground tracking-wide">Secrets</p>
              <p className={`text-sm font-semibold mt-1 ${pscResult.secrets_ok ? 'text-success' : 'text-destructive'}`}>
                {pscResult.secrets_ok ? 'OK' : `${pscResult.missing_secrets.length} manquant(s)`}
              </p>
              {!pscResult.secrets_ok && pscResult.missing_secrets.length > 0 && (
                <p className="text-[10px] text-muted-foreground mt-0.5 truncate">
                  {pscResult.missing_secrets.join(', ')}
                </p>
              )}
            </div>
            <div className={`p-3 rounded-lg border ${pscResult.discovery_ok && pscResult.endpoints_match ? 'border-success/30 bg-success/5' : 'border-warning/30 bg-warning/5'}`}>
              <p className="text-[10px] uppercase text-muted-foreground tracking-wide">Discovery OIDC</p>
              <p className={`text-sm font-semibold mt-1 ${pscResult.discovery_ok ? 'text-success' : 'text-destructive'}`}>
                {pscResult.discovery_ok ? `HTTP ${pscResult.discovery_status}` : 'Inaccessible'}
              </p>
              <p className="text-[10px] text-muted-foreground mt-0.5">
                Endpoints {pscResult.endpoints_match ? 'alignés' : 'divergents'} · {pscResult.duration_ms}ms
              </p>
            </div>
            {pscResult.endpoints_diff.length > 0 && (
              <div className="sm:col-span-3 p-3 rounded-lg border border-warning/30 bg-warning/5">
                <p className="text-[10px] uppercase text-muted-foreground tracking-wide mb-1">Divergences détectées</p>
                <ul className="text-[11px] text-foreground font-mono space-y-0.5">
                  {pscResult.endpoints_diff.map((d, i) => (
                    <li key={i}>· {d}</li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
      </div>

      {/* ── SMS Twilio : test rapide ── */}
      <div className="card-base mt-6 p-5">
        <div className="flex items-start justify-between gap-4 mb-4">
          <div>
            <h2 className="text-base font-bold text-foreground flex items-center gap-2">
              <MessageSquare className="h-4 w-4 text-primary" />
              SMS Twilio
            </h2>
            <p className="text-xs text-muted-foreground mt-0.5">
              Envoi d'un SMS de test au numéro indiqué (préchargé depuis votre profil si admin = soignant). Coût ~0.045€.
            </p>
          </div>
        </div>
        <div className="flex flex-col sm:flex-row gap-2">
          <input
            type="tel"
            inputMode="tel"
            value={smsPhone}
            onChange={(e) => setSmsPhone(e.target.value)}
            placeholder="+33 6 XX XX XX XX"
            className="input-base flex-1"
          />
          <button
            onClick={testerSMS}
            disabled={smsTesting || !smsPhone.trim()}
            className="btn-primary inline-flex items-center justify-center gap-2 disabled:opacity-50"
          >
            {smsTesting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            {smsTesting ? 'Envoi…' : 'Tester SMS'}
          </button>
        </div>
        {smsResult && (
          <div className={`mt-3 p-3 rounded-lg border text-xs ${smsResult.ok ? 'border-success/30 bg-success/5 text-success' : 'border-destructive/30 bg-destructive/5 text-destructive'}`}>
            <span className="font-mono">{smsResult.detail}</span>
          </div>
        )}
      </div>

      {!import.meta.env.VITE_SENTRY_DSN && (
        <p className="text-[11px] text-muted-foreground/60 italic mt-6 text-center">
          ℹ️ Sentry sera activé prochainement (configuration VITE_SENTRY_DSN côté Vercel à venir).
        </p>
      )}
    </LayoutAdmin>
  );
}
