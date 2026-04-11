import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { supabase } from '@/integrations/supabase/client';
import { Loader2 } from 'lucide-react';

function fmt(v: number) {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

function Ligne({ label, montant, bold, green }: { label: string; montant: number; bold?: boolean; green?: boolean }) {
  return (
    <div className={`flex justify-between py-1.5 ${bold ? 'font-bold' : ''}`}>
      <span className="text-sm text-foreground">{label}</span>
      <span className={`text-sm tabular-nums ${green ? 'text-success font-bold text-base' : bold ? 'text-foreground' : 'text-muted-foreground'}`}>{fmt(montant)}</span>
    </div>
  );
}

export function ModalCotisations({ missionId, open, onClose }: { missionId: string | null; open: boolean; onClose: () => void }) {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!open || !missionId) return;
    setLoading(true);
    supabase.from('cotisations_sociales').select('*').eq('mission_id', missionId).maybeSingle()
      .then(({ data: d }) => { setData(d); setLoading(false); });
  }, [open, missionId]);

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-[calc(100%-1rem)] sm:max-w-md max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Détail des cotisations</DialogTitle>
        </DialogHeader>

        {loading ? (
          <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-primary" /></div>
        ) : !data ? (
          <p className="text-sm text-muted-foreground text-center py-4">Données non disponibles pour cette mission.</p>
        ) : (
          <div className="space-y-4">
            {/* Brut */}
            <div>
              <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-1">Rémunération brute</h3>
              <div className="border border-border rounded-lg px-3 py-1">
                <Ligne label="Salaire brut" montant={data.salaire_brut} bold />
                {data.ifm > 0 && <Ligne label="IFM (10%)" montant={data.ifm} />}
                {data.icp > 0 && <Ligne label="ICP (10%)" montant={data.icp} />}
              </div>
            </div>

            {/* Cotisations salariales */}
            <div>
              <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-1">Cotisations salariales</h3>
              <div className="border border-border rounded-lg px-3 py-1">
                <Ligne label="CSG déductible" montant={data.csg_deductible} />
                <Ligne label="CSG non déductible" montant={data.csg_non_deductible} />
                <Ligne label="CRDS" montant={data.crds} />
                <Ligne label="Sécu vieillesse plafonnée" montant={data.securite_sociale_vieillesse_plafonnee} />
                <Ligne label="Sécu vieillesse déplafonnée" montant={data.securite_sociale_vieillesse_deplafonnee} />
                <Ligne label="Sécu maladie" montant={data.securite_sociale_maladie} />
                <Ligne label="Retraite complémentaire T1" montant={data.retraite_complementaire_t1} />
                <Ligne label="Retraite complémentaire T2" montant={data.retraite_complementaire_t2} />
                <Ligne label="Assurance chômage" montant={data.assurance_chomage} />
                <Ligne label="Contribution équilibre général" montant={data.contribution_equilibre_general} />
                <div className="border-t border-border mt-1 pt-1">
                  <Ligne label="Total cotisations salariales" montant={data.total_cotisations_salariales} bold />
                </div>
              </div>
            </div>

            {/* Net */}
            <div className="bg-success/5 border border-success/20 rounded-lg px-3 py-3">
              <Ligne label="Net avant impôt" montant={data.net_avant_impot} green />
            </div>

            {/* Côté employeur */}
            <div>
              <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-1">Côté employeur</h3>
              <div className="border border-border rounded-lg px-3 py-1">
                <Ligne label="Patronal sécu sociale" montant={data.patronal_securite_sociale} />
                <Ligne label="Patronal allocations familiales" montant={data.patronal_allocations_familiales} />
                <Ligne label="Patronal accident du travail" montant={data.patronal_accident_travail} />
                <Ligne label="Patronal retraite complémentaire" montant={data.patronal_retraite_complementaire} />
                <Ligne label="Patronal chômage" montant={data.patronal_chomage} />
                <Ligne label="Transport" montant={data.patronal_transport} />
                <Ligne label="Formation" montant={data.patronal_formation} />
                <Ligne label="FNAL" montant={data.patronal_fnal} />
                <div className="border-t border-border mt-1 pt-1">
                  <Ligne label="Total patronales" montant={data.total_cotisations_patronales} bold />
                  <Ligne label="Coût total employeur" montant={data.cout_total_employeur} bold />
                </div>
              </div>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
