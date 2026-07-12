import { useEffect, useState } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import {
  CardY2K,
  CardY2KContent,
} from '@/components/y2k/CardY2K';
import { Badge } from '@/components/ui/badge';
import { Zap, TrendingUp, CheckCircle, XCircle, Clock, Loader2, AlertTriangle } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';

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

const STATUT_LIBELLE: Record<string, string> = {
  DEMANDEE: 'Demandée',
  EN_ANALYSE: 'En analyse',
  APPROUVEE: 'Approuvée',
  FINANCEE: 'Financée',
  RECOUVREE: 'Recouvrée',
  REJETEE: 'Rejetée',
  IMPAYEE: 'Impayée',
  ANNULEE: 'Annulée',
};

const libelleStatut = (statut: string) => STATUT_LIBELLE[statut] || statut.replace('_', ' ');

// Priorité d'affichage : les statuts demandant l'attention en premier, le reste ensuite (par date décroissante)
const STATUT_PRIORITE: Record<string, number> = {
  IMPAYEE: 0,
  DEMANDEE: 1,
  EN_ANALYSE: 2,
  APPROUVEE: 3,
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
    })
      .catch((err) => {
        setLoading(false);
        toast.error(err?.message || 'Erreur chargement affacturage');
      });
  }, []);

  const triees = [...advances].sort((a, b) => {
    const pa = STATUT_PRIORITE[a.statut] ?? 4;
    const pb = STATUT_PRIORITE[b.statut] ?? 4;
    if (pa !== pb) return pa - pb;
    return new Date(b.cree_le || 0).getTime() - new Date(a.cree_le || 0).getTime();
  });
  const filtered = filtre === 'TOUS' ? triees : triees.filter(a => a.statut === filtre);

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Affacturage" /></LayoutAdmin>;

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Affacturage" />
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
            <Zap className="h-6 w-6 text-primary" /> Affacturage
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Suivi des demandes d'avance via affactureur (Defacto). Une marge Jolene est appliquée à chaque opération.
          </p>
        </div>

        {/* KPIs */}
        <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
          <CardY2K noPadding>
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">Demandes total</p>
              <p className="text-2xl font-bold text-foreground">{stats?.total_demandes ?? 0}</p>
            </CardY2KContent>
          </CardY2K>
          <CardY2K noPadding className="border-primary/30 bg-primary/5">
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">En cours</p>
              <p className="text-2xl font-bold text-primary">{stats?.demandes_en_cours ?? 0}</p>
            </CardY2KContent>
          </CardY2K>
          <CardY2K noPadding className="border-success/30 bg-success/5">
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">Financées</p>
              <p className="text-2xl font-bold text-success">{stats?.demandes_financees ?? 0}</p>
            </CardY2KContent>
          </CardY2K>
          <CardY2K noPadding>
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">Volume financé</p>
              <p className="text-xl font-bold text-foreground">{fmt(Number(stats?.volume_finance_total || 0))}</p>
            </CardY2KContent>
          </CardY2K>
          <CardY2K noPadding className="border-rose/30 bg-rose/5">
            <CardY2KContent className="pt-4 pb-3">
              <p className="text-[10px] text-muted-foreground uppercase">Marge Jolene</p>
              <p className="text-xl font-bold text-rose">{fmt(Number(stats?.commission_jolene_total || 0))}</p>
            </CardY2KContent>
          </CardY2K>
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
              {s === 'TOUS' ? 'Tous' : libelleStatut(s)}
            </button>
          ))}
        </div>

        {/* Tableau */}
        <CardY2K noPadding>
          <CardY2KContent className="p-0">
            {filtered.length === 0 ? (
              <p className="p-8 text-center text-muted-foreground">Aucune demande d'affacturage</p>
            ) : (
              <>
                {/* Desktop table */}
                <div className="hidden md:block overflow-x-auto">
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
                      {filtered.map((a) => {
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
                                {libelleStatut(a.statut)}
                              </Badge>
                              {a.motif_rejet && <p className="text-[10px] text-destructive mt-0.5">{a.motif_rejet}</p>}
                            </td>
                            <td className="p-3 text-xs text-muted-foreground">
                              {a.cree_le ? format(new Date(a.cree_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>

                {/* Mobile cards */}
                <div className="md:hidden space-y-3 p-3">
                  {filtered.map((a) => {
                    const fh = a.factures_honoraires as any;
                    const sg = a.soignants as any;
                    const etab = a.etablissements as any;
                    const mission = a.missions as any;
                    return (
                      <div key={a.id} className="card-base space-y-2">
                        <div className="flex items-start justify-between gap-2">
                          <div className="min-w-0">
                            <p className="font-mono text-xs font-semibold text-foreground">{fh?.numero_facture || '—'}</p>
                            {mission?.intitule && <p className="text-[10px] text-muted-foreground truncate">{mission.intitule}</p>}
                          </div>
                          <Badge className={`text-[10px] shrink-0 ${STATUT_BADGE[a.statut] || 'bg-muted'}`}>
                            {libelleStatut(a.statut)}
                          </Badge>
                        </div>
                        <div className="text-xs text-muted-foreground space-y-0.5">
                          <p>
                            Soignant :{' '}
                            <button onClick={() => navigate(`/admin/utilisateurs/${a.soignant_id}`)} className="text-primary hover:underline">
                              {sg ? `${sg.prenom} ${sg.nom}` : '—'}
                            </button>
                          </p>
                          <p>
                            Établissement :{' '}
                            <button onClick={() => navigate(`/admin/utilisateurs/${a.etablissement_id}`)} className="text-primary hover:underline">
                              {etab?.nom || '—'}
                            </button>
                          </p>
                        </div>
                        <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs pt-1 border-t border-border/50">
                          <div>
                            <p className="text-muted-foreground">Montant TTC</p>
                            <p className="font-semibold text-foreground">{fmt(a.montant_facture_ttc)}</p>
                          </div>
                          <div>
                            <p className="text-muted-foreground">Net soignant</p>
                            <p className="font-bold text-success">{a.montant_net_soignant ? fmt(a.montant_net_soignant) : '—'}</p>
                          </div>
                          <div>
                            <p className="text-muted-foreground">Frais factor</p>
                            <p className="text-foreground">{a.frais_factor ? fmt(a.frais_factor) : '—'}</p>
                          </div>
                          <div>
                            <p className="text-muted-foreground">Marge Jolene</p>
                            <p className="text-rose font-medium">{a.frais_jolene ? fmt(a.frais_jolene) : '—'}</p>
                          </div>
                        </div>
                        <p className="text-[10px] text-muted-foreground">
                          {a.cree_le ? format(new Date(a.cree_le), 'dd/MM/yyyy', { locale: fr }) : '—'}
                          {a.motif_rejet && <span className="text-destructive ml-2">{a.motif_rejet}</span>}
                        </p>
                      </div>
                    );
                  })}
                </div>
              </>
            )}
          </CardY2KContent>
        </CardY2K>
      </div>
    </LayoutAdmin>
  );
}
