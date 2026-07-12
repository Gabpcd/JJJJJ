import { useState } from 'react';
import { telechargerOuPartager } from '@/lib/telechargement';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { CardY2K, CardY2KContent, CardY2KHeader, CardY2KTitle } from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Skeleton } from '@/components/ui/skeleton';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import {
  ShieldCheck,
  ShieldAlert,
  RefreshCw,
  Download,
  AlertTriangle,
  CheckCircle2,
  Database,
  Lock,
} from 'lucide-react';
import { toast } from 'sonner';

/**
 * Sprint 7 PR 3 — P1-11
 * Page admin /admin/audit-rls
 *
 * Expose la RPC `fn_audit_rls_strict` ajoutée au Sprint 3.
 * Affiche un verdict global + détail des tables sans RLS / sans policy.
 * Aucune action automatique sur les tables — c'est un outil d'inspection
 * destiné à l'admin plateforme (ADMIN_PLATEFORME).
 */

type ProblemeRLS = {
  schema_name: string;
  table_name: string;
  type_probleme: 'RLS_DESACTIVEE' | 'RLS_ACTIVE_SANS_POLICY' | string;
  details?: string | null;
};

type AuditRLSResult = {
  verdict: 'OK' | 'KO';
  total_tables: number;
  tables_sans_rls: number;
  tables_sans_policy: number;
  problemes: ProblemeRLS[];
  executed_at: string;
};

function badgeProbleme(type: string) {
  switch (type) {
    case 'RLS_DESACTIVEE':
      return (
        <BadgeY2K variant="error" icone={<ShieldAlert className="h-3 w-3" />}>
          RLS désactivée
        </BadgeY2K>
      );
    case 'RLS_ACTIVE_SANS_POLICY':
      return (
        <BadgeY2K variant="warning" icone={<Lock className="h-3 w-3" />}>
          Sans policy
        </BadgeY2K>
      );
    default:
      return <BadgeY2K variant="info">{type}</BadgeY2K>;
  }
}

export default function AdminAuditRLS() {
  const [refreshing, setRefreshing] = useState(false);

  const { data, isLoading, isError, error, refetch } = useQuery<AuditRLSResult>({
    queryKey: ['admin', 'audit-rls-strict'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_audit_rls_strict' as any);
      if (error) throw error;
      return data as AuditRLSResult;
    },
  });

  const handleRerun = async () => {
    setRefreshing(true);
    try {
      const result = await refetch();
      if (result.error) {
        toast.error("Erreur lors de l'audit RLS");
      } else {
        toast.success('Audit RLS relancé');
      }
    } finally {
      setRefreshing(false);
    }
  };

  const handleExportJSON = async () => {
    if (!data) {
      toast.error('Aucune donnée à exporter');
      return;
    }
    const ts = new Date().toISOString().replace(/[:.]/g, '-');
    await telechargerOuPartager(JSON.stringify(data, null, 2), `audit-rls-strict-${ts}.json`, 'application/json');
    toast.success('Export JSON téléchargé');
  };

  const verdictOK = !isError && !!data && data.verdict === 'OK';

  return (
    <LayoutAdmin>
      <div className="space-y-6">
        {/* Header */}
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
              <ShieldCheck className="h-7 w-7 text-primary" />
              Audit RLS strict
            </h1>
            <p className="text-sm text-muted-foreground mt-1">
              Vérification automatique de la sécurité Row-Level Security sur toutes les
              tables publiques.
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <BoutonY2K
              variant="secondary"
              size="sm"
              onClick={handleRerun}
              disabled={refreshing || isLoading}
              iconeGauche={<RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />}
            >
              Relancer l'audit
            </BoutonY2K>
            <BoutonY2K
              variant="secondary"
              size="sm"
              onClick={handleExportJSON}
              disabled={!data}
              iconeGauche={<Download className="h-4 w-4" />}
            >
              Exporter JSON
            </BoutonY2K>
          </div>
        </div>

        {/* Erreur de chargement */}
        {isError && (
          <Alert variant="destructive">
            <AlertTriangle className="h-4 w-4" />
            <AlertTitle>Impossible d'exécuter l'audit</AlertTitle>
            <AlertDescription>
              {(error as Error)?.message ?? "Erreur inconnue lors de l'exécution de l'audit."}
            </AlertDescription>
          </Alert>
        )}

        {/* KPI cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Verdict global */}
          <CardY2K
            noPadding
            className={
              isLoading
                ? ''
                : verdictOK
                ? 'border-green-500/40 bg-green-500/5'
                : 'border-destructive/40 bg-destructive/5'
            }
          >
            <CardY2KHeader className="pb-2">
              <CardY2KTitle className="text-sm font-medium text-muted-foreground">
                Verdict global
              </CardY2KTitle>
            </CardY2KHeader>
            <CardY2KContent>
              {isLoading ? (
                <Skeleton className="h-10 w-24" />
              ) : isError || !data ? (
                <div className="flex items-center gap-2 text-destructive">
                  <AlertTriangle className="h-8 w-8" />
                  <div>
                    <div className="text-lg font-bold">Indisponible</div>
                    <div className="text-xs text-muted-foreground">Aucun verdict ne peut être rendu</div>
                  </div>
                </div>
              ) : verdictOK ? (
                <div className="flex items-center gap-2">
                  <CheckCircle2 className="h-8 w-8 text-green-600" />
                  <div>
                    <div className="text-2xl font-bold text-green-700">OK</div>
                    <div className="text-xs text-muted-foreground">
                      Toutes les tables sont protégées
                    </div>
                  </div>
                </div>
              ) : (
                <div className="flex items-center gap-2">
                  <ShieldAlert className="h-8 w-8 text-destructive" />
                  <div>
                    <div className="text-2xl font-bold text-destructive">KO</div>
                    <div className="text-xs text-muted-foreground">
                      {data?.problemes.length ?? 0} problème(s) détecté(s)
                    </div>
                  </div>
                </div>
              )}
            </CardY2KContent>
          </CardY2K>

          {/* Tables sans RLS */}
          <CardY2K noPadding>
            <CardY2KHeader className="pb-2">
              <CardY2KTitle className="text-sm font-medium text-muted-foreground flex items-center gap-2">
                <Database className="h-4 w-4" />
                Tables sans RLS
              </CardY2KTitle>
            </CardY2KHeader>
            <CardY2KContent>
              {isLoading ? (
                <Skeleton className="h-10 w-16" />
              ) : isError || !data ? (
                <div className="text-3xl font-bold text-muted-foreground">—</div>
              ) : (
                <div>
                  <div
                    className={`text-3xl font-bold ${
                      (data?.tables_sans_rls ?? 0) > 0
                        ? 'text-destructive'
                        : 'text-green-700'
                    }`}
                  >
                    {data?.tables_sans_rls ?? 0}
                  </div>
                  <div className="text-xs text-muted-foreground mt-1">
                    RLS désactivée sur la table
                  </div>
                </div>
              )}
            </CardY2KContent>
          </CardY2K>

          {/* Tables RLS active sans policy */}
          <CardY2K noPadding>
            <CardY2KHeader className="pb-2">
              <CardY2KTitle className="text-sm font-medium text-muted-foreground flex items-center gap-2">
                <Lock className="h-4 w-4" />
                RLS active sans policy
              </CardY2KTitle>
            </CardY2KHeader>
            <CardY2KContent>
              {isLoading ? (
                <Skeleton className="h-10 w-16" />
              ) : isError || !data ? (
                <div className="text-3xl font-bold text-muted-foreground">—</div>
              ) : (
                <div>
                  <div
                    className={`text-3xl font-bold ${
                      (data?.tables_sans_policy ?? 0) > 0
                        ? 'text-destructive'
                        : 'text-green-700'
                    }`}
                  >
                    {data?.tables_sans_policy ?? 0}
                  </div>
                  <div className="text-xs text-muted-foreground mt-1">
                    Verrouillage par défaut (deny all)
                  </div>
                </div>
              )}
            </CardY2KContent>
          </CardY2K>
        </div>

        {/* Liste détaillée des problèmes */}
        <CardY2K noPadding>
          <CardY2KHeader>
            <CardY2KTitle className="text-lg">Détail des problèmes</CardY2KTitle>
          </CardY2KHeader>
          <CardY2KContent>
            {isLoading ? (
              <div className="space-y-2">
                {[...Array(3)].map((_, i) => (
                  <Skeleton key={i} className="h-12 w-full" />
                ))}
              </div>
            ) : isError ? (
              <div role="alert" className="text-center py-8 text-destructive">
                <AlertTriangle className="h-12 w-12 mx-auto mb-2" />
                <p className="text-sm">Audit indisponible. Aucun feu vert n'est affiché tant que la vérification échoue.</p>
              </div>
            ) : !data || data.problemes.length === 0 ? (
              <div className="text-center py-8">
                <CheckCircle2 className="h-12 w-12 text-green-600 mx-auto mb-2" />
                <p className="text-sm text-muted-foreground">
                  Aucun problème détecté. Toutes les tables publiques sont protégées
                  par RLS et possèdent au moins une policy.
                </p>
                {data?.executed_at && (
                  <p className="text-xs text-muted-foreground mt-2">
                    Audit exécuté le{' '}
                    {new Date(data.executed_at).toLocaleString('fr-FR')}
                  </p>
                )}
              </div>
            ) : (
              <div className="space-y-2">
                <div className="text-xs text-muted-foreground mb-3">
                  {data.total_tables} table(s) inspectée(s) — {data.problemes.length}{' '}
                  problème(s) — exécuté le{' '}
                  {new Date(data.executed_at).toLocaleString('fr-FR')}
                </div>
                {data.problemes.map((p, idx) => (
                  <div
                    key={`${p.schema_name}.${p.table_name}-${idx}`}
                    className="flex items-center justify-between gap-3 p-3 rounded-md border bg-card"
                  >
                    <div className="flex-1 min-w-0">
                      <div className="font-mono text-sm font-medium truncate">
                        {p.schema_name}.{p.table_name}
                      </div>
                      {p.details && (
                        <div className="text-xs text-muted-foreground mt-0.5 truncate">
                          {p.details}
                        </div>
                      )}
                    </div>
                    <div className="shrink-0">{badgeProbleme(p.type_probleme)}</div>
                  </div>
                ))}
              </div>
            )}
          </CardY2KContent>
        </CardY2K>

        {/* Note d'aide */}
        <Alert>
          <ShieldCheck className="h-4 w-4" />
          <AlertTitle>À propos de cet audit</AlertTitle>
          <AlertDescription className="text-xs leading-relaxed">
            L'audit est exécuté côté serveur avec les droits ADMIN_PLATEFORME. Il
            parcourt toutes les tables du schéma <code>public</code> et signale :
            <ul className="list-disc ml-5 mt-1 space-y-0.5">
              <li>
                <strong>RLS désactivée</strong> : la table accepte des lectures /
                écritures sans aucun filtre — risque critique.
              </li>
              <li>
                <strong>RLS active sans policy</strong> : la table refuse tout accès
                par défaut (deny all) — peut être volontaire pour les tables
                techniques mais à vérifier.
              </li>
            </ul>
            Aucune action automatique n'est déclenchée. La correction doit passer
            par une migration SQL.
          </AlertDescription>
        </Alert>
      </div>
    </LayoutAdmin>
  );
}
