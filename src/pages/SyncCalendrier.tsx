import React, { useState, useEffect, useCallback } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import {
  Calendar,
  Copy,
  Check,
  RefreshCw,
  Link2,
  Unlink,
  Loader2,
  ExternalLink,
  AlertCircle,
  CheckCircle,
  Clock,
} from 'lucide-react';

/* ── Types ── */
interface CalendarConnection {
  id: string;
  utilisateur_id: string;
  provider: 'google' | 'outlook' | 'apple';
  status: string;
  last_sync_at: string | null;
  created_at: string;
}

/* ── Provider display config ── */
const PROVIDERS: Record<string, { label: string; color: string }> = {
  google: { label: 'Google Calendar', color: 'text-red-500' },
  outlook: { label: 'Outlook', color: 'text-blue-600' },
  apple: { label: 'Apple Calendar', color: 'text-gray-700' },
};

function ProviderIcon({ provider, className }: { provider: string; className?: string }) {
  if (provider === 'google') {
    return (
      <svg className={className} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/>
        <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
        <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
        <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
      </svg>
    );
  }
  if (provider === 'outlook') {
    return (
      <svg className={className} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M24 7.387v10.478c0 .23-.08.424-.238.583a.793.793 0 01-.583.238h-8.196v-8.47l1.462 1.077L24 7.387z" fill="#0364B8"/>
        <path d="M16.462 11.293l-1.479-1.077V20.686H23.18a.793.793 0 00.583-.238.793.793 0 00.238-.583V7.387l-7.538 3.906z" fill="#0A2767"/>
        <path d="M24 3.298v4.09l-8.196 4.52-6.82-4.52V3.298c0-.23.08-.424.238-.583A.793.793 0 019.806 2.477h13.407c.23 0 .424.08.583.238A.793.793 0 0124 3.298z" fill="#28A8EA"/>
        <path d="M8.984 7.387v13.3H1.82a.793.793 0 01-.583-.239.793.793 0 01-.238-.583V5.895c0-.65.212-1.197.636-1.64A2.196 2.196 0 013.238 3.62h5.746v3.767z" fill="#0078D4"/>
        <path d="M8.984 3.62v7.534L0 5.894c0-.65.212-1.197.636-1.64A2.196 2.196 0 012.238 3.62h6.746z" fill="#50D9FF"/>
        <ellipse cx="5.5" cy="14" rx="4" ry="4.5" fill="#0078D4"/>
        <path d="M3.75 12.25h3.5v3.5h-3.5z" fill="white"/>
      </svg>
    );
  }
  // Apple
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
    </svg>
  );
}

/* ── Helpers ── */
function formatDateHeure(d: string | null): string {
  if (!d) return 'Jamais';
  return new Date(d).toLocaleString('fr-FR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export default function SyncCalendrier() {
  usePageTitle('Sync Calendrier');
  const { user } = useAuth();
  const { afficherNotification } = useNotification();

  const [loading, setLoading] = useState(true);
  const [token, setToken] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [connections, setConnections] = useState<CalendarConnection[]>([]);
  const [syncCount, setSyncCount] = useState(0);
  const [lastSync, setLastSync] = useState<string | null>(null);
  const [syncing, setSyncing] = useState(false);

  // Apple CalDAV form state
  const [showAppleForm, setShowAppleForm] = useState(false);
  const [applePassword, setApplePassword] = useState('');
  const [appleCalDavUrl, setAppleCalDavUrl] = useState('https://caldav.icloud.com');

  /* ── Load data ── */
  const chargerDonnees = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    try {
      // Fetch iCal token
      const { data: tokenData } = await supabase
        .from('tokens_calendrier' as any)
        .select('token')
        .eq('soignant_id', user.id)
        .maybeSingle();
      if (tokenData) setToken((tokenData as any).token);

      // Fetch calendar connections
      const { data: conns } = await supabase
        .from('calendar_connections' as any)
        .select('*')
        .eq('utilisateur_id', user.id);
      if (conns) setConnections(conns as any[]);

      // Fetch sync count
      const { data: syncData, count } = await supabase
        .from('calendar_events_sync' as any)
        .select('id', { count: 'exact', head: true })
        .eq('utilisateur_id', user.id);
      setSyncCount(count || 0);

      // Determine last sync from connections
      const syncTimes = (conns as any[] || [])
        .map((c: any) => c.last_sync_at)
        .filter(Boolean)
        .sort()
        .reverse();
      setLastSync(syncTimes[0] || null);
    } catch (err) {
      console.error('Erreur chargement sync calendrier:', err);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    chargerDonnees();
  }, [chargerDonnees]);

  /* ── Copy iCal URL ── */
  const icalUrl = token
    ? `${SUPABASE_URL}/functions/v1/calendar-feed?uid=${user?.id}&token=${token}`
    : null;

  const copierLien = async () => {
    if (!icalUrl) return;
    try {
      await navigator.clipboard.writeText(icalUrl);
      setCopied(true);
      toast.success('Lien copié dans le presse-papier');
      setTimeout(() => setCopied(false), 2000);
    } catch {
      toast.error('Impossible de copier le lien');
    }
  };

  /* ── Connect providers ── */
  const connecterGoogle = () => {
    toast.info('Bientôt disponible — configuration OAuth2 en cours');
  };

  const connecterOutlook = () => {
    toast.info('Bientôt disponible — configuration OAuth2 en cours');
  };

  const connecterApple = async () => {
    if (!applePassword.trim()) {
      toast.error('Veuillez saisir votre mot de passe spécifique à l\'application');
      return;
    }
    // For now, store connection entry as placeholder
    toast.info('Bientôt disponible — intégration CalDAV en cours');
    setShowAppleForm(false);
    setApplePassword('');
  };

  /* ── Disconnect ── */
  const deconnecter = async (connectionId: string) => {
    try {
      await supabase
        .from('calendar_connections' as any)
        .delete()
        .eq('id', connectionId);
      toast.success('Calendrier déconnecté');
      chargerDonnees();
    } catch {
      toast.error('Erreur lors de la déconnexion');
    }
  };

  /* ── Manual sync ── */
  const synchroniserMaintenant = async () => {
    if (!user) return;
    setSyncing(true);
    try {
      const { data, error } = await supabase.functions.invoke('calendar-sync', {
        body: { user_id: user.id },
      });
      if (error) throw error;
      toast.success(`Synchronisation terminée — ${data?.synced || 0} mission(s) synchronisée(s)`);
      chargerDonnees();
    } catch (err) {
      console.error('Erreur sync:', err);
      toast.error('Erreur lors de la synchronisation');
    } finally {
      setSyncing(false);
    }
  };

  if (!user) return <ChargementPage />;
  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="max-w-3xl mx-auto space-y-6">
        {/* ── Header ── */}
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 rounded-xl bg-primary/10 flex items-center justify-center">
            <Calendar className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-foreground">Synchronisation Calendrier</h1>
            <p className="text-sm text-muted-foreground">
              Synchronisez vos missions Jolene avec votre calendrier personnel
            </p>
          </div>
        </div>

        {/* ── Section 1: Lien iCal ── */}
        <div className="card-base p-5 space-y-4">
          <div className="flex items-center gap-2">
            <Link2 className="h-5 w-5 text-primary" />
            <h2 className="text-base font-semibold text-foreground">Flux iCal (lecture seule)</h2>
          </div>
          <p className="text-sm text-muted-foreground">
            Collez ce lien dans Outlook, Google Calendar ou Apple Calendar pour afficher vos missions.
            Le calendrier se met à jour automatiquement.
          </p>

          {icalUrl ? (
            <div className="flex items-center gap-2">
              <input
                type="text"
                readOnly
                value={icalUrl}
                className="input-base flex-1 text-xs font-mono truncate"
              />
              <button
                onClick={copierLien}
                className="btn-secondary flex items-center gap-1.5 px-3 py-2 text-sm whitespace-nowrap"
              >
                {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                {copied ? 'Copié' : 'Copier'}
              </button>
            </div>
          ) : (
            <p className="text-sm text-muted-foreground italic">
              Aucun token calendrier trouvé. Accédez à votre planning pour en générer un.
            </p>
          )}
        </div>

        {/* ── Section 2: Calendriers connectés ── */}
        <div className="card-base p-5 space-y-4">
          <div className="flex items-center gap-2">
            <RefreshCw className="h-5 w-5 text-primary" />
            <h2 className="text-base font-semibold text-foreground">Calendriers connectés</h2>
          </div>
          <p className="text-sm text-muted-foreground">
            Connectez un calendrier pour une synchronisation bidirectionnelle de vos missions.
          </p>

          {/* Existing connections */}
          {connections.length > 0 && (
            <div className="space-y-3">
              {connections.map((conn) => {
                const provider = PROVIDERS[conn.provider] || { label: conn.provider, color: 'text-foreground' };
                const isError = conn.status === 'error';
                return (
                  <div
                    key={conn.id}
                    className="flex items-center justify-between p-3 rounded-lg bg-muted/50 border border-border"
                  >
                    <div className="flex items-center gap-3">
                      <ProviderIcon provider={conn.provider} className={`h-5 w-5 ${provider.color}`} />
                      <div>
                        <p className="text-sm font-medium text-foreground">{provider.label}</p>
                        <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                          {isError ? (
                            <AlertCircle className="h-3 w-3 text-destructive" />
                          ) : (
                            <CheckCircle className="h-3 w-3 text-success" />
                          )}
                          <span>{isError ? 'Erreur' : 'Connecté'}</span>
                          {conn.last_sync_at && (
                            <>
                              <span className="mx-1">·</span>
                              <Clock className="h-3 w-3" />
                              <span>Dernière sync : {formatDateHeure(conn.last_sync_at)}</span>
                            </>
                          )}
                        </div>
                      </div>
                    </div>
                    <button
                      onClick={() => deconnecter(conn.id)}
                      className="btn-secondary flex items-center gap-1 px-2 py-1.5 text-xs text-destructive hover:text-destructive"
                    >
                      <Unlink className="h-3.5 w-3.5" />
                      Déconnecter
                    </button>
                  </div>
                );
              })}
            </div>
          )}

          {/* Connect buttons */}
          <div className="grid gap-3 sm:grid-cols-3">
            {/* Google */}
            <button
              onClick={connecterGoogle}
              className="btn-secondary flex items-center justify-center gap-2 p-3 text-sm"
            >
              <ProviderIcon provider="google" className="h-5 w-5" />
              Google Calendar
            </button>

            {/* Outlook */}
            <button
              onClick={connecterOutlook}
              className="btn-secondary flex items-center justify-center gap-2 p-3 text-sm"
            >
              <ProviderIcon provider="outlook" className="h-5 w-5" />
              Outlook
            </button>

            {/* Apple */}
            <button
              onClick={() => setShowAppleForm(!showAppleForm)}
              className="btn-secondary flex items-center justify-center gap-2 p-3 text-sm"
            >
              <ProviderIcon provider="apple" className="h-5 w-5" />
              Apple Calendar
            </button>
          </div>

          {/* Apple CalDAV form */}
          {showAppleForm && (
            <div className="p-4 rounded-lg bg-muted/30 border border-border space-y-3">
              <p className="text-sm font-medium text-foreground">Connexion Apple Calendar (CalDAV)</p>
              <p className="text-xs text-muted-foreground">
                Apple utilise des mots de passe spécifiques aux applications.{' '}
                <a
                  href="https://support.apple.com/fr-fr/102654"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-primary hover:underline inline-flex items-center gap-0.5"
                >
                  Comment en créer un <ExternalLink className="h-3 w-3" />
                </a>
              </p>
              <div className="space-y-2">
                <label className="text-xs font-medium text-foreground">URL CalDAV</label>
                <input
                  type="url"
                  value={appleCalDavUrl}
                  onChange={(e) => setAppleCalDavUrl(e.target.value)}
                  placeholder="https://caldav.icloud.com"
                  className="input-base w-full text-sm"
                />
              </div>
              <div className="space-y-2">
                <label className="text-xs font-medium text-foreground">Mot de passe spécifique à l'application</label>
                <input
                  type="password"
                  value={applePassword}
                  onChange={(e) => setApplePassword(e.target.value)}
                  placeholder="xxxx-xxxx-xxxx-xxxx"
                  className="input-base w-full text-sm"
                />
              </div>
              <div className="flex gap-2">
                <button onClick={connecterApple} className="btn-primary px-4 py-2 text-sm">
                  Connecter
                </button>
                <button
                  onClick={() => { setShowAppleForm(false); setApplePassword(''); }}
                  className="btn-secondary px-4 py-2 text-sm"
                >
                  Annuler
                </button>
              </div>
            </div>
          )}
        </div>

        {/* ── Section 3: Statut de synchronisation ── */}
        <div className="card-base p-5 space-y-4">
          <div className="flex items-center gap-2">
            <CheckCircle className="h-5 w-5 text-primary" />
            <h2 className="text-base font-semibold text-foreground">Statut de synchronisation</h2>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="p-3 rounded-lg bg-muted/50">
              <p className="text-2xl font-bold text-foreground">{syncCount}</p>
              <p className="text-xs text-muted-foreground">Mission(s) synchronisée(s)</p>
            </div>
            <div className="p-3 rounded-lg bg-muted/50">
              <p className="text-sm font-medium text-foreground">{formatDateHeure(lastSync)}</p>
              <p className="text-xs text-muted-foreground">Dernière synchronisation</p>
            </div>
          </div>

          <button
            onClick={synchroniserMaintenant}
            disabled={syncing}
            className="btn-primary flex items-center justify-center gap-2 w-full py-2.5 text-sm"
          >
            {syncing ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <RefreshCw className="h-4 w-4" />
            )}
            {syncing ? 'Synchronisation en cours...' : 'Synchroniser maintenant'}
          </button>
        </div>
      </div>
    </LayoutApp>
  );
}
