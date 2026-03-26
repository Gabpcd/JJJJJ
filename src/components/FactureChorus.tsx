import { useState } from 'react';
import { Landmark, Loader2, ExternalLink, RefreshCw } from 'lucide-react';
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

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || 'https://flripxtsyegjshnhzjkz.supabase.co';

async function callChorusEdge(accessToken: string, factureId: string, action: 'deposer' | 'statut', extra: Record<string, string> = {}) {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/chorus-pro-deposit`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ facture_id: factureId, action, ...extra }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || 'Erreur Chorus Pro');
  return data;
}

export function FactureChorus({ facture, onUpdate }: Props) {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(false);
  const [checkingStatus, setCheckingStatus] = useState(false);
  const [open, setOpen] = useState(false);
  const [numEngagement, setNumEngagement] = useState('');
  const [codeService, setCodeService] = useState('');
  const [numStructure, setNumStructure] = useState('');

  const getAccessToken = async (): Promise<string | null> => {
    const { data } = await supabase.auth.getSession();
    return data.session?.access_token ?? null;
  };

  const deposer = async () => {
    const token = await getAccessToken();
    if (!token) return;
    setLoading(true);
    try {
      const result = await callChorusEdge(token, facture.id, 'deposer', {
        num_engagement: numEngagement,
        code_service: codeService,
        num_structure: numStructure,
      });
      const msg = result.simulation
        ? `🧪 Simulation : ${result.message}`
        : `✅ ${result.message}`;
      afficherNotification({ type: 'succes', message: msg });
      setOpen(false);
      onUpdate();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: 'Erreur lors du dépôt Chorus. Veuillez réessayer.' });
    } finally {
      setLoading(false);
    }
  };

  const verifierStatut = async () => {
    const token = await getAccessToken();
    if (!token) return;
    setCheckingStatus(true);
    try {
      const result = await callChorusEdge(token, facture.id, 'statut');
      const prefix = result.simulation ? '🧪 Simulation — ' : '';
      afficherNotification({
        type: 'info',
        message: `${prefix}Statut Chorus : ${CHORUS_STATUT_LABELS[result.statut] ?? result.statut}`,
      });
      onUpdate();
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err.message || 'Erreur vérification statut' });
    } finally {
      setCheckingStatus(false);
    }
  };

  const statut = facture.chorus_pro_statut || 'A_DEPOSER';

  // Already processed statuses — show badge + check status button
  if (['DEPOSEE', 'ACCEPTEE', 'MISE_EN_PAIEMENT'].includes(statut)) {
    return (
      <div className="flex items-center gap-2 flex-wrap">
        <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${CHORUS_STATUT_STYLES[statut] ?? ''}`}>
          <Landmark className="h-3 w-3 inline mr-1" />
          {CHORUS_STATUT_LABELS[statut]}
        </span>
        <button
          onClick={verifierStatut}
          disabled={checkingStatus}
          className="btn-secondary text-xs flex items-center gap-1 disabled:opacity-50"
          title="Vérifier le statut Chorus Pro"
        >
          <RefreshCw className={`h-3 w-3 ${checkingStatus ? 'animate-spin' : ''}`} />
          Vérifier
        </button>
      </div>
    );
  }

  if (statut === 'REJETEE') {
    return (
      <div className="flex flex-col gap-1">
        <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${CHORUS_STATUT_STYLES.REJETEE}`}>
          {CHORUS_STATUT_LABELS.REJETEE}
        </span>
        <div className="flex gap-1 flex-wrap">
          <button onClick={() => setOpen(true)} className="btn-secondary text-xs flex items-center gap-1">
            <Landmark className="h-3.5 w-3.5" /> Redéposer
          </button>
          <button
            onClick={verifierStatut}
            disabled={checkingStatus}
            className="btn-secondary text-xs flex items-center gap-1 disabled:opacity-50"
          >
            <RefreshCw className={`h-3 w-3 ${checkingStatus ? 'animate-spin' : ''}`} />
          </button>
        </div>
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
        Renseignez les informations Chorus puis déposez via l'API. Délai de paiement estimé : 30-60 jours.
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
          📤 Déposer sur Chorus Pro
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
