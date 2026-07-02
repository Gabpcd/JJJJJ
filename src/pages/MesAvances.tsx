import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Zap, Loader2, CheckCircle, Clock, AlertTriangle, XCircle, TrendingUp } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { EmptyState } from '@/components/ui/EmptyState';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

const STATUT_CONFIG: Record<string, { label: string; icon: JSX.Element; color: string; bg: string }> = {
  DEMANDEE: { label: 'Demandée', icon: <Clock className="h-3.5 w-3.5" />, color: 'text-warning', bg: 'bg-warning/10' },
  EN_ANALYSE: { label: 'En analyse', icon: <Loader2 className="h-3.5 w-3.5 animate-spin" />, color: 'text-primary', bg: 'bg-primary/10' },
  APPROUVEE: { label: 'Approuvée', icon: <CheckCircle className="h-3.5 w-3.5" />, color: 'text-primary', bg: 'bg-primary/10' },
  FINANCEE: { label: 'Reçu sur votre compte', icon: <CheckCircle className="h-3.5 w-3.5" />, color: 'text-success', bg: 'bg-success/10' },
  RECOUVREE: { label: 'Recouvrement terminé', icon: <CheckCircle className="h-3.5 w-3.5" />, color: 'text-success', bg: 'bg-success/20' },
  REJETEE: { label: 'Refusée', icon: <XCircle className="h-3.5 w-3.5" />, color: 'text-destructive', bg: 'bg-destructive/10' },
  IMPAYEE: { label: 'Impayée', icon: <AlertTriangle className="h-3.5 w-3.5" />, color: 'text-destructive', bg: 'bg-destructive/10' },
  ANNULEE: { label: 'Annulée', icon: <XCircle className="h-3.5 w-3.5" />, color: 'text-muted-foreground', bg: 'bg-muted' },
};

export default function MesAvances() {
  usePageTitle('Mes avances');
  return (
    <LayoutApp role="SOIGNANT">
      <MesAvancesContent />
    </LayoutApp>
  );
}

export function MesAvancesContent() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [avances, setAvances] = useState<any[]>([]);
  const [typeExercice, setTypeExercice] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const [{ data: profil }, { data }] = await Promise.all([
        supabase.from('soignants').select('type_exercice').eq('id', user.id).maybeSingle(),
        supabase.rpc('fn_mes_avances_factor' as any),
      ]);
      setTypeExercice((profil as any)?.type_exercice || null);
      setAvances(data || []);
      setLoading(false);
    })();
  }, [user]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  // Salarié pur → pas d'affacturage (pas de créances libérales à céder)
  if (!loading && typeExercice && typeExercice !== 'LIBERAL' && typeExercice !== 'MIXTE') {
    return (
      <div className="max-w-lg mx-auto py-12 text-center space-y-4">
        <Zap className="h-12 w-12 text-muted-foreground mx-auto" />
        <h2 className="text-lg font-bold text-foreground">Avances non disponibles</h2>
        <p className="text-sm text-muted-foreground">
          L'avance de paiement (affacturage) est réservée aux soignants en libéral ou mixte.
          En tant que salarié(e), vos paiements sont gérés par l'établissement.
        </p>
      </div>
    );
  }

  const totalFinance = avances.filter(a => ['FINANCEE', 'RECOUVREE'].includes(a.statut)).reduce((s, a) => s + Number(a.montant_net_soignant || 0), 0);
  const enAttente = avances.filter(a => ['DEMANDEE', 'EN_ANALYSE', 'APPROUVEE'].includes(a.statut)).length;

  return (
    <div className="space-y-5">
        <p className="text-xs text-muted-foreground">Historique de vos demandes d'affacturage Defacto</p>

        {/* KPIs */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div className="card-base">
            <p className="text-xs text-muted-foreground">Total reçu</p>
            <p className="text-xl font-bold text-success">{fmt(totalFinance)}</p>
          </div>
          <div className="card-base">
            <p className="text-xs text-muted-foreground">En cours</p>
            <p className="text-xl font-bold text-foreground">{enAttente}</p>
          </div>
          <div className="card-base">
            <p className="text-xs text-muted-foreground">Total demandes</p>
            <p className="text-xl font-bold text-foreground">{avances.length}</p>
          </div>
        </div>

        <div className="rounded-lg bg-primary/5 border border-primary/20 p-3 flex items-start gap-2">
          <TrendingUp className="h-4 w-4 text-primary shrink-0 mt-0.5" />
          <p className="text-xs text-primary">
            {/* 7c : « paiement rapide » est désormais réservé au badge ⚡ (étab
                préfinancé) — ici c'est une AVANCE (affacturage, frais retenus). */}
            L'avance de paiement vous permet de recevoir vos honoraires en 24-48h au lieu d'attendre 30-60 jours.
            Des frais d'affacturage (2-3%) sont retenus.
          </p>
        </div>

        {avances.length === 0 ? (
          <EmptyState
            icone={<Zap />}
            mascotte="thinking"
            titre="Aucune avance pour le moment"
            description="Demandez une avance de paiement depuis vos factures d'honoraires."
            cta={{
              label: 'Voir mes factures',
              onClick: () => navigate('/soignant/mes-gains?tab=factures'),
            }}
          />
        ) : (
          <div className="space-y-2">
            {avances.map((a) => {
              const cfg = STATUT_CONFIG[a.statut] || STATUT_CONFIG.DEMANDEE;
              return (
                <div key={a.id} className="card-base hover:border-primary/30 transition-colors">
                  <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-mono text-xs font-bold text-foreground">{a.numero_facture}</span>
                        <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full inline-flex items-center gap-1 ${cfg.bg} ${cfg.color}`}>
                          {cfg.icon} {cfg.label}
                        </span>
                      </div>
                      <p className="text-sm text-foreground font-medium">{a.mission_intitule || '—'}</p>
                      <p className="text-xs text-muted-foreground">{a.etablissement_nom}</p>
                      <p className="text-[10px] text-muted-foreground mt-1">
                        Demandée le {a.cree_le ? format(new Date(a.cree_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
                        {a.financee_le && ` · Versée le ${format(new Date(a.financee_le), 'dd/MM/yyyy', { locale: fr })}`}
                      </p>
                    </div>
                    <div className="text-right space-y-0.5">
                      <p className="text-xs text-muted-foreground">Facture</p>
                      <p className="text-sm font-medium">{fmt(a.montant_facture_ttc)}</p>
                      {a.frais_factor && (
                        <>
                          <p className="text-[10px] text-muted-foreground mt-1">- Frais factor : {fmt(a.frais_factor)}</p>
                          {a.frais_jolene > 0 && <p className="text-[10px] text-muted-foreground">- Frais Jolene : {fmt(a.frais_jolene)}</p>}
                        </>
                      )}
                      {a.montant_net_soignant && (
                        <>
                          <p className="text-xs text-muted-foreground">Vous recevez</p>
                          <p className="text-lg font-bold text-success">{fmt(a.montant_net_soignant)}</p>
                        </>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
    </div>
  );
}
