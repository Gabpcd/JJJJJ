import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Input } from '@/components/ui/input';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { format, startOfMonth, endOfMonth, subMonths, startOfYear, endOfYear } from 'date-fns';

interface ModalAttestationProps {
  open: boolean;
  onClose: () => void;
}

const RACCOURCIS = [
  { label: 'Ce mois', fn: () => ({ debut: startOfMonth(new Date()), fin: endOfMonth(new Date()) }) },
  { label: 'Mois dernier', fn: () => ({ debut: startOfMonth(subMonths(new Date(), 1)), fin: endOfMonth(subMonths(new Date(), 1)) }) },
  { label: 'Ce trimestre', fn: () => {
    const m = new Date().getMonth();
    const q = Math.floor(m / 3) * 3;
    return { debut: new Date(new Date().getFullYear(), q, 1), fin: new Date(new Date().getFullYear(), q + 3, 0) };
  }},
  { label: 'Cette année', fn: () => ({ debut: startOfYear(new Date()), fin: endOfYear(new Date()) }) },
];

export function ModalAttestation({ open, onClose }: ModalAttestationProps) {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [debut, setDebut] = useState(format(startOfMonth(new Date()), 'yyyy-MM-dd'));
  const [fin, setFin] = useState(format(endOfMonth(new Date()), 'yyyy-MM-dd'));
  const [preview, setPreview] = useState({ nb: 0, heures: 0 });
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!open || !user) return;
    const load = async () => {
      setLoading(true);
      const { data } = await supabase
        .from('missions')
        .select('duree_heures')
        .eq('soignant_assigne_id', user.id)
        .eq('statut', 'TERMINEE')
        .gte('debut_le', debut)
        .lte('debut_le', fin);
      const ms = (data as any[]) || [];
      setPreview({ nb: ms.length, heures: ms.reduce((s: number, m: any) => s + (m.duree_heures || 0), 0) });
      setLoading(false);
    };
    load();
  }, [open, user, debut, fin]);

  function appliquerRaccourci(r: typeof RACCOURCIS[0]) {
    const { debut: d, fin: f } = r.fn();
    setDebut(format(d, 'yyyy-MM-dd'));
    setFin(format(f, 'yyyy-MM-dd'));
  }

  function generer() {
    window.open(`/soignant/attestation-heures?debut=${debut}&fin=${fin}`, '_blank');
    onClose();
  }

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>📥 Générer une attestation d'heures</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div>
            <p className="text-sm font-medium text-foreground mb-2">Période :</p>
            <div className="flex items-center gap-2">
              <div className="flex-1">
                <label className="text-xs text-muted-foreground">Du</label>
                <Input type="date" value={debut} onChange={(e) => setDebut(e.target.value)} />
              </div>
              <div className="flex-1">
                <label className="text-xs text-muted-foreground">Au</label>
                <Input type="date" value={fin} onChange={(e) => setFin(e.target.value)} />
              </div>
            </div>
          </div>

          <div>
            <p className="text-xs text-muted-foreground mb-1.5">Raccourcis :</p>
            <div className="flex flex-wrap gap-1.5">
              {RACCOURCIS.map(r => (
                <button key={r.label} onClick={() => appliquerRaccourci(r)} className="text-xs bg-muted text-muted-foreground hover:bg-primary/10 hover:text-primary px-3 py-1.5 rounded-full transition-colors">
                  {r.label}
                </button>
              ))}
            </div>
          </div>

          <div className="bg-muted/50 rounded-xl p-3 text-center">
            {loading ? (
              <p className="text-sm text-muted-foreground">Chargement...</p>
            ) : (
              <p className="text-sm font-medium text-foreground">
                Missions incluses : <span className="text-primary font-bold">{preview.nb} mission{preview.nb > 1 ? 's' : ''}</span> · <span className="text-primary font-bold">{Math.round(preview.heures)}h</span>
              </p>
            )}
          </div>

          <div className="flex gap-2 justify-end pt-2">
            <BoutonY2K variant="secondary" onClick={onClose}>Annuler</BoutonY2K>
            <BoutonY2K onClick={generer} disabled={preview.nb === 0}>
              Générer l'attestation
            </BoutonY2K>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
