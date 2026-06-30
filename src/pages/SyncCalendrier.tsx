import React, { useState, useEffect, useCallback } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { telechargerOuPartager } from '@/lib/telechargement';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { useAuth } from '@/contexts/AuthContext';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';
import {
  Calendar,
  Copy,
  Check,
  RefreshCw,
  Link2,
  Loader2,
  ExternalLink,
  CheckCircle,
  Clock,
  Download,
} from 'lucide-react';

/* ── Provider display config ── */
const PROVIDERS: Record<string, { label: string; color: string; instructions: string }> = {
  google: {
    label: 'Google Calendar',
    color: 'text-red-500',
    instructions: 'Clique pour ajouter le calendrier Jolene à ton Google Calendar. Les missions se mettent à jour automatiquement.',
  },
  outlook: {
    label: 'Outlook',
    color: 'text-blue-600',
    instructions: 'Clique pour ouvrir Outlook Web et ajouter le calendrier Jolene. Compatible Outlook.com et Outlook desktop.',
  },
  apple: {
    label: 'Apple Calendar',
    color: 'text-gray-700',
    instructions: 'Clique pour ouvrir Apple Calendar avec un abonnement à tes missions. Fonctionne sur Mac, iPhone et iPad.',
  },
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

  const [loading, setLoading] = useState(true);
  const [token, setToken] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [syncCount, setSyncCount] = useState(0);
  const [lastSync, setLastSync] = useState<string | null>(null);
  const [syncing, setSyncing] = useState(false);

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

      // If no token, try to generate one
      if (!tokenData) {
        const { data: newToken } = await supabase.rpc('fn_mon_token_calendrier' as any);
        if (newToken) setToken(newToken as string);
      }

      // Fetch sync count
      const { count } = await supabase
        .from('calendar_events_sync' as any)
        .select('id', { count: 'exact', head: true })
        .eq('utilisateur_id', user.id);
      setSyncCount(count || 0);
    } catch (err) {
      logger.error('Erreur chargement sync calendrier', err);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    chargerDonnees();
  }, [chargerDonnees]);

  /* ── URLs ── */
  const icalUrl = token
    ? `${SUPABASE_URL}/functions/v1/calendar-feed?uid=${user?.id}&token=${token}`
    : null;

  const webcalUrl = icalUrl
    ? icalUrl.replace(/^https?:\/\//, 'webcal://')
    : null;

  const googleUrl = webcalUrl
    ? `https://calendar.google.com/calendar/r?cid=${encodeURIComponent(webcalUrl)}`
    : null;

  const outlookUrl = icalUrl
    ? `https://outlook.live.com/calendar/0/addfromweb?url=${encodeURIComponent(icalUrl)}&name=Missions%20Jolene`
    : null;

  /* ── Copy iCal URL ── */
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

  /* ── Download .ics ── */
  const telechargerIcs = async () => {
    if (!icalUrl) return;
    try {
      const res = await fetch(icalUrl);
      const text = await res.text();
      await telechargerOuPartager(text, 'missions-jolene.ics', 'text/calendar');
    } catch {
      toast.error('Erreur lors du téléchargement');
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
      logger.error('Erreur sync', err);
      toast.error('Erreur lors de la synchronisation');
    } finally {
      setSyncing(false);
    }
  };

  if (!user) return <ChargementPage />;
  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const hasToken = !!icalUrl;

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
              Synchronise tes missions Jolene avec ton calendrier personnel
            </p>
          </div>
        </div>

        {/* ── Section 1: S'abonner en un clic ── */}
        <div className="card-base p-5 space-y-4">
          <div className="flex items-center gap-2">
            <Calendar className="h-5 w-5 text-primary" />
            <h2 className="text-base font-semibold text-foreground">S'abonner au calendrier Jolene</h2>
          </div>
          <p className="text-sm text-muted-foreground">
            Clique sur ton calendrier pour y ajouter tes missions. Le calendrier se met à jour automatiquement — tes nouvelles missions apparaissent sans rien faire.
          </p>

          {hasToken ? (
            <div className="grid gap-3 sm:grid-cols-3">
              {/* Google Calendar */}
              <a
                href={googleUrl!}
                target="_blank"
                rel="noopener noreferrer"
                className="flex flex-col items-center gap-2 p-4 rounded-xl border border-border hover:border-primary/50 hover:bg-primary/5 transition-all text-center group"
              >
                <ProviderIcon provider="google" className="h-8 w-8" />
                <span className="text-sm font-medium text-foreground">Google Calendar</span>
                <span className="text-[10px] text-muted-foreground leading-tight">
                  Ouvre Google Calendar et ajoute l'abonnement
                </span>
                <ExternalLink className="h-3.5 w-3.5 text-muted-foreground group-hover:text-primary transition-colors" />
              </a>

              {/* Outlook */}
              <a
                href={outlookUrl!}
                target="_blank"
                rel="noopener noreferrer"
                className="flex flex-col items-center gap-2 p-4 rounded-xl border border-border hover:border-primary/50 hover:bg-primary/5 transition-all text-center group"
              >
                <ProviderIcon provider="outlook" className="h-8 w-8" />
                <span className="text-sm font-medium text-foreground">Outlook</span>
                <span className="text-[10px] text-muted-foreground leading-tight">
                  Ouvre Outlook Web et ajoute l'abonnement
                </span>
                <ExternalLink className="h-3.5 w-3.5 text-muted-foreground group-hover:text-primary transition-colors" />
              </a>

              {/* Apple Calendar */}
              <a
                href={webcalUrl!}
                className="flex flex-col items-center gap-2 p-4 rounded-xl border border-border hover:border-primary/50 hover:bg-primary/5 transition-all text-center group"
              >
                <ProviderIcon provider="apple" className="h-8 w-8" />
                <span className="text-sm font-medium text-foreground">Apple Calendar</span>
                <span className="text-[10px] text-muted-foreground leading-tight">
                  Ouvre Apple Calendar (Mac, iPhone, iPad)
                </span>
                <ExternalLink className="h-3.5 w-3.5 text-muted-foreground group-hover:text-primary transition-colors" />
              </a>
            </div>
          ) : (
            <div className="p-4 rounded-xl bg-muted/30 border border-border text-center">
              <p className="text-sm text-muted-foreground">
                Aucun token calendrier trouvé. Accède à ton planning pour en générer un automatiquement.
              </p>
            </div>
          )}
        </div>

        {/* ── Section 2: Lien iCal (avancé) ── */}
        {hasToken && (
          <div className="card-base p-5 space-y-4">
            <div className="flex items-center gap-2">
              <Link2 className="h-5 w-5 text-primary" />
              <h2 className="text-base font-semibold text-foreground">Lien iCal (avancé)</h2>
            </div>
            <p className="text-sm text-muted-foreground">
              Pour les autres applications de calendrier, copie ce lien et ajoute-le comme "abonnement à un calendrier" ou "calendrier internet".
            </p>

            <div className="flex items-center gap-2">
              <input
                type="text"
                readOnly
                value={icalUrl!}
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

            <button
              onClick={telechargerIcs}
              className="btn-secondary flex items-center gap-2 text-sm"
            >
              <Download className="h-4 w-4" /> Télécharger le fichier .ics
            </button>
          </div>
        )}

        {/* ── Section 3: Statut ── */}
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
