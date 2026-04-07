import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, Download, ArrowLeft, Loader2, CheckCircle, Clock, AlertTriangle, Info } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

const STATUT_CONFIG: Record<string, { label: string; icon: JSX.Element; color: string }> = {
  BROUILLON: { label: 'Brouillon', icon: <Clock className="h-3 w-3" />, color: 'bg-muted text-muted-foreground' },
  EMISE: { label: 'Émise', icon: <FileText className="h-3 w-3" />, color: 'bg-primary/10 text-primary' },
  EN_RETARD: { label: 'En retard', icon: <AlertTriangle className="h-3 w-3" />, color: 'bg-destructive/10 text-destructive' },
  PAYEE: { label: 'Payée', icon: <CheckCircle className="h-3 w-3" />, color: 'bg-success/10 text-success' },
  FACTORISEE: { label: 'Avance reçue', icon: <CheckCircle className="h-3 w-3" />, color: 'bg-success/20 text-success' },
  ANNULEE: { label: 'Annulée', icon: <AlertTriangle className="h-3 w-3" />, color: 'bg-muted text-muted-foreground' },
};

export default function MesFacturesHonoraires() {
  usePageTitle('Mes factures d\'honoraires');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [factures, setFactures] = useState<any[]>([]);
  const [mandatSigne, setMandatSigne] = useState(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const [{ data: sgData }, { data: facts }] = await Promise.all([
        supabase.from('soignants').select('mandat_facturation_signe').eq('id', user.id).maybeSingle(),
        supabase.rpc('fn_mes_factures_honoraires' as any),
      ]);
      setMandatSigne(!!sgData?.mandat_facturation_signe);
      setFactures(facts || []);
      setLoading(false);
    })();
  }, [user]);

  if (loading) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  const totalFacture = factures.reduce((s, f) => s + Number(f.montant_ttc || 0), 0);
  const totalPaye = factures.filter(f => f.statut === 'PAYEE' || f.statut === 'FACTORISEE').reduce((s, f) => s + Number(f.montant_ttc || 0), 0);
  const totalAttente = factures.filter(f => f.statut === 'EMISE' || f.statut === 'EN_RETARD').reduce((s, f) => s + Number(f.montant_ttc || 0), 0);

  return (
    <LayoutApp role="SOIGNANT">
      <div className="space-y-5">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={() => navigate(-1)}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
              <FileText className="h-5 w-5 text-primary" /> Mes factures d'honoraires
            </h1>
            <p className="text-xs text-muted-foreground">Factures émises en votre nom par Jolene (mandataire)</p>
          </div>
        </div>

        {!mandatSigne && (
          <div className="rounded-xl border-2 border-warning/30 bg-warning/5 p-4 flex items-start gap-3">
            <Info className="h-5 w-5 text-warning shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="font-semibold text-foreground">Mandat de facturation non signé</p>
              <p className="text-sm text-muted-foreground mt-0.5">
                Pour que Jolene puisse produire automatiquement vos factures d'honoraires et préparer l'accès au paiement rapide,
                vous devez d'abord signer le mandat de facturation.
              </p>
              <Button onClick={() => navigate('/soignant/mandat-facturation')} className="mt-3 gap-2" size="sm">
                Signer le mandat
              </Button>
            </div>
          </div>
        )}

        {/* KPIs */}
        <div className="grid grid-cols-3 gap-3">
          <div className="card-base">
            <p className="text-xs text-muted-foreground">Total facturé</p>
            <p className="text-xl font-bold text-foreground">{fmt(totalFacture)}</p>
          </div>
          <div className="card-base border-success/20 bg-success/5">
            <p className="text-xs text-muted-foreground">Encaissé</p>
            <p className="text-xl font-bold text-success">{fmt(totalPaye)}</p>
          </div>
          <div className="card-base border-warning/20 bg-warning/5">
            <p className="text-xs text-muted-foreground">En attente</p>
            <p className="text-xl font-bold text-warning">{fmt(totalAttente)}</p>
          </div>
        </div>

        {factures.length === 0 ? (
          <div className="card-base text-center py-10">
            <FileText className="h-12 w-12 text-muted-foreground mx-auto mb-3" />
            <p className="font-semibold text-foreground">Aucune facture d'honoraires pour le moment</p>
            <p className="text-sm text-muted-foreground mt-1">
              {mandatSigne
                ? 'Les factures apparaîtront dès que vos missions seront terminées et validées.'
                : 'Signez d\'abord le mandat de facturation pour commencer à recevoir des factures automatiques.'}
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            {factures.map((f: any) => {
              const config = STATUT_CONFIG[f.statut] || STATUT_CONFIG.EMISE;
              return (
                <div key={f.id} className="card-base hover:border-primary/30 transition-colors">
                  <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-mono text-xs font-bold text-foreground">{f.numero_facture}</span>
                        <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full inline-flex items-center gap-1 ${config.color}`}>
                          {config.icon} {config.label}
                        </span>
                      </div>
                      <p className="text-sm text-foreground font-medium">{f.mission_intitule || '—'}</p>
                      <p className="text-xs text-muted-foreground">{f.etablissement_nom}</p>
                      <p className="text-[10px] text-muted-foreground mt-1">
                        Émise le {f.date_emission ? format(new Date(f.date_emission), 'dd/MM/yyyy', { locale: fr }) : '—'}
                        {f.date_echeance && ` · Échéance ${format(new Date(f.date_echeance), 'dd/MM/yyyy', { locale: fr })}`}
                        {f.date_paiement && ` · Payée le ${format(new Date(f.date_paiement), 'dd/MM/yyyy', { locale: fr })}`}
                      </p>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="text-right">
                        <p className="text-lg font-bold text-foreground">{fmt(f.montant_ttc)}</p>
                        <p className="text-[10px] text-muted-foreground">Exonéré TVA (art. 261-4 CGI)</p>
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </LayoutApp>
  );
}
