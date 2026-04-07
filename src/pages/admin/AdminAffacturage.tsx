import { useEffect, useState } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Zap, TrendingUp, CheckCircle, XCircle, Clock, Loader2, AlertTriangle } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { useNavigate } from 'react-router-dom';

const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);

const STATUT_BADGE: Record<string, string> = {
  DEMANDEE: 'bg-warning/10 text-warning',
  EN_ANALYSE: 'bg-primary/10 text-primary',
  APPROUVEE: 'bg-primary/10 text-primary',
  FINANCEE: 'bg-success/10 text-success',
  RECOUVREE: 'bg-success/20 text-success',
  REJETEE: 'bg-destructive/10 text-destructive',
  IMPAYEE: 'bg-destructive/10 text-destructive',
  ANNULEE: 'bg-muted text-muted-foreground',
};

export default function AdminAffacturage() {
  usePageTitle('Affacturage');
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState<any>(null);
  const [advances, setAdvances] = useState<any[]>([]);
  const [filtre, setFiltre] = useState<string>('TOUS');

  useEffect(() => {
    Promise.all([
      supabase.rpc('fn_admin_factor_stats' as any),
      supabase.from('factor_advances')
        .select('*, factures_honoraires(numero_facture), soignants(prenom, nom), etablissements(nom), missions(intitule)')
        .order('cree_le', { ascending: false })
        .limit(500),
    ]).then(([sRes, aRes]) => {
      if (sRes.data) setStats(sRes.data);
      if (aRes.data) setAdvances(aRes.data);
      setLoading(false);
    });
  }, []);

  const filtered = filtre === 'TOUS' ? advances : advances.filter(a => a.statut === filtre);

  if (loading) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Affacturage" />
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Zap className="h-6 w-6 text-primary" /> Affacturage
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Suivi des demandes d'avance via affactureur (Defacto). Marge Jolene par opération configurable via le secret FACTOR_MARGE_JOLENE.
          </p>
        </div>

        {/* KPIs */}
        <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
          <Card>
            <CardContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">Demandes total</p>
              <p className="text-2xl font-bold text-foreground">{stats?.total_demandes ?? 0}</p>
            </CardContent>
          </Card>
          <Card className="border-primary/30 bg-primary/5">
            <CardContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">En cours</p>
              <p className="text-2xl font-bold text-primary">{stats?.demandes_en_cours ?? 0}</p>
            </CardContent>
          </Card>
          <Card className="border-success/30 bg-success/5">
            <CardContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">Financées</p>
              <p className="text-2xl font-bold text-success">{stats?.demandes_financees ?? 0}</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">Volume financé</p>
              <p className="text-xl font-bold text-foreground">{fmt(Number(stats?.volume_finance_total || 0))}</p>
            </CardContent>
          </Card>
          <Card className="border-rose/30 bg-rose/5">
            <CardContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">Marge Jolene</p>
              <p className="text-xl font-bold text-rose">{fmt(Number(stats?.commission_jolene_total || 0))}</p>
            </CardContent>
          </Card>
        </div>

        {/* Filtres */}
        <div className="flex flex-wrap gap-2">
          {['TOUS', 'DEMANDEE', 'EN_ANALYSE', 'APPROUVEE', 'FINANCEE', 'RECOUVREE', 'REJETEE', 'IMPAYEE'].map(s => (
            <button
              key={s}
              onClick={() => setFiltre(s)}
              className={`px-3 py-1.5 text-xs font-medium rounded-lg border transition-colors ${
                filtre === s ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:border-primary/30'
              }`}
            >
              {s === 'TOUS' ? 'Tous' : s.replace('_', ' ')}
            </button>
          ))}
        </div>

        {/* Tableau */}
        <Card>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs text-muted-foreground">
                    <th className="p-3 font-medium">Facture</th>
                    <th className="p-3 font-medium">Soignant</th>
                    <th className="p-3 font-medium">Établissement</th>
                    <th className="p-3 font-medium text-right">Montant</th>
                    <th className="p-3 font-medium text-right">Frais factor</th>
                    <th className="p-3 font-medium text-right">Marge Jolene</th>
                    <th className="p-3 font-medium text-right">Net soignant</th>
                    <th className="p-3 font-medium">Statut</th>
                    <th className="p-3 font-medium">Date</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.length === 0 ? (
                    <tr>
                      <td colSpan={9} className="p-8 text-center text-muted-foreground">
                        Aucune demande d'affacturage
                      </td>
                    </tr>
                  ) : (
                    filtered.map((a) => {
                      const fh = a.factures_honoraires as any;
                      const sg = a.soignants as any;
                      const etab = a.etablissements as any;
                      const mission = a.missions as any;
                      return (
                        <tr key={a.id} className="border-b border-border/50 hover:bg-muted/30">
                          <td className="p-3 font-mono text-xs">{fh?.numero_facture || '—'}</td>
                          <td className="p-3">
                            <button
                              onClick={() => navigate(`/admin/utilisateurs/${a.soignant_id}`)}
                              className="text-primary hover:underline"
                            >
                              {sg ? `${sg.prenom} ${sg.nom}` : '—'}
                            </button>
                          </td>
                          <td className="p-3">
                            <button
                              onClick={() => navigate(`/admin/utilisateurs/${a.etablissement_id}`)}
                              className="text-primary hover:underline"
                            >
                              {etab?.nom || '—'}
                            </button>
                            {mission?.intitule && <p className="text-[10px] text-muted-foreground">{mission.intitule}</p>}
                          </td>
                          <td className="p-3 text-right font-medium">{fmt(a.montant_facture_ttc)}</td>
                          <td className="p-3 text-right text-xs text-muted-foreground">{a.frais_factor ? fmt(a.frais_factor) : '—'}</td>
                          <td className="p-3 text-right text-xs text-rose font-medium">{a.frais_jolene ? fmt(a.frais_jolene) : '—'}</td>
                          <td className="p-3 text-right font-bold text-success">{a.montant_net_soignant ? fmt(a.montant_net_soignant) : '—'}</td>
                          <td className="p-3">
                            <Badge className={`text-[10px] ${STATUT_BADGE[a.statut] || 'bg-muted'}`}>
                              {a.statut.replace('_', ' ')}
                            </Badge>
                            {a.motif_rejet && <p className="text-[10px] text-destructive mt-0.5">{a.motif_rejet}</p>}
                          </td>
                          <td className="p-3 text-xs text-muted-foreground">
                            {a.cree_le ? format(new Date(a.cree_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      </div>
    </LayoutAdmin>
  );
}
