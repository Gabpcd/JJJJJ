import { useState } from 'react';
import { Landmark, Loader2, ExternalLink } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';

interface Props {
  facture: any;
  onUpdate: () => void;
}

const CHORUS_STATUT_STYLES: Record<string, string> = {
  NON_APPLICABLE: 'bg-muted text-muted-foreground',
  A_DEPOSER: 'bg-warning/10 text-warning',
  DEPOSEE: 'bg-primary/10 text-primary',
  ACCEPTEE: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  REJETEE: 'bg-destructive/10 text-destructive',
  MISE_EN_PAIEMENT: 'bg-green-200 text-green-800 dark:bg-green-900/50 dark:text-green-300',
};

const CHORUS_STATUT_LABELS: Record<string, string> = {
  NON_APPLICABLE: '—',
  A_DEPOSER: '🟠 À déposer',
  DEPOSEE: '🔵 Déposée',
  ACCEPTEE: '🟢 Acceptée',
  REJETEE: '🔴 Rejetée',
  MISE_EN_PAIEMENT: '🟢 Mise en paiement',
};

export function FactureChorus({ facture, onUpdate }: Props) {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [numEngagement, setNumEngagement] = useState('');
  const [codeService, setCodeService] = useState('');
  const [numStructure, setNumStructure] = useState('');

  const deposer = async () => {
    if (!user) return;
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_deposer_chorus' as any, {
      p_facture_id: facture.id,
    });
    if (error || data?.error) {
      afficherNotification({ type: 'erreur', message: data?.error || 'Erreur lors du dépôt Chorus' });
      setLoading(false);
      return;
    }

    setLoading(false);
    setOpen(false);
    afficherNotification({ type: 'succes', message: '✅ Facture marquée comme déposée sur Chorus Pro' });
    onUpdate();
  };

  const statut = facture.chorus_pro_statut || 'A_DEPOSER';

  // Already processed statuses
  if (['DEPOSEE', 'ACCEPTEE', 'MISE_EN_PAIEMENT'].includes(statut)) {
    return (
      <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${CHORUS_STATUT_STYLES[statut] ?? ''}`}>
        <Landmark className="h-3 w-3 inline mr-1" />
        {CHORUS_STATUT_LABELS[statut]}
      </span>
    );
  }

  if (statut === 'REJETEE') {
    return (
      <div className="flex flex-col gap-1">
        <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${CHORUS_STATUT_STYLES.REJETEE}`}>
          {CHORUS_STATUT_LABELS.REJETEE}
        </span>
        <button onClick={() => setOpen(true)} className="btn-secondary text-xs flex items-center gap-1">
          <Landmark className="h-3.5 w-3.5" /> Redéposer
        </button>
      </div>
    );
  }

  if (!open) {
    return (
      <button onClick={() => setOpen(true)} className="btn-secondary text-xs flex items-center gap-1">
        <Landmark className="h-3.5 w-3.5" /> Chorus Pro
      </button>
    );
  }

  return (
    <div className="card-base p-3 space-y-3 mt-2 w-full">
      <p className="text-sm font-semibold text-foreground flex items-center gap-1">
        <Landmark className="h-4 w-4 text-primary" /> Facture secteur public — Chorus Pro
      </p>
      <p className="text-xs text-muted-foreground">
        Renseignez les informations Chorus puis marquez comme déposée. Délai de paiement estimé : 30-60 jours.
      </p>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
        <div>
          <label className="block text-[10px] font-medium text-muted-foreground mb-0.5">N° engagement</label>
          <input value={numEngagement} onChange={e => setNumEngagement(e.target.value)} className="input-base w-full text-xs" placeholder="EJ-2026-..." />
        </div>
        <div>
          <label className="block text-[10px] font-medium text-muted-foreground mb-0.5">Code service</label>
          <input value={codeService} onChange={e => setCodeService(e.target.value)} className="input-base w-full text-xs" placeholder="SRV001" />
        </div>
        <div>
          <label className="block text-[10px] font-medium text-muted-foreground mb-0.5">N° structure Chorus</label>
          <input value={numStructure} onChange={e => setNumStructure(e.target.value)} className="input-base w-full text-xs" placeholder="12345678" />
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        <button onClick={deposer} disabled={loading} className="btn-primary text-xs flex items-center gap-1 disabled:opacity-50">
          {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Landmark className="h-3.5 w-3.5" />}
          📤 Marquer comme déposée
        </button>
        <a
          href="https://chorus-pro.gouv.fr"
          target="_blank"
          rel="noopener noreferrer"
          className="btn-secondary text-xs flex items-center gap-1"
        >
          <ExternalLink className="h-3.5 w-3.5" /> Déposer manuellement →
        </a>
        <button onClick={() => setOpen(false)} className="btn-secondary text-xs">Annuler</button>
      </div>
    </div>
  );
}

export function ChorusStatutBadge({ statut }: { statut: string }) {
  if (!statut || statut === 'NON_APPLICABLE') return null;
  return (
    <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold inline-flex items-center gap-1 ${CHORUS_STATUT_STYLES[statut] ?? CHORUS_STATUT_STYLES.A_DEPOSER}`}>
      <Landmark className="h-3 w-3" />
      {CHORUS_STATUT_LABELS[statut] ?? statut}
    </span>
  );
}
