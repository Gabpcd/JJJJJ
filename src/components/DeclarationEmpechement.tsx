import { useState } from 'react';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';

interface DeclarationEmpechementProps {
  missionId: string;
  onDeclare: () => void;
}

/**
 * Attestation d'empêchement impérieux (remplace l'arrêt maladie).
 * Cf. docs/MINI_PR_ARRET_MALADIE.md + docs/CONFORMITE.md §1.4 : aucune donnée
 * de santé — dates d'indisponibilité + attestation sur l'honneur, la nature du
 * motif n'est ni demandée ni stockée (RGPD art. 9). Aucun document.
 */
export function DeclarationEmpechement({ missionId, onDeclare }: DeclarationEmpechementProps) {
  const [ouvert, setOuvert] = useState(false);
  const [debut, setDebut] = useState('');
  const [fin, setFin] = useState('');
  const [surHonneur, setSurHonneur] = useState(false);
  const [envoi, setEnvoi] = useState(false);

  const aujourdHui = new Date().toISOString().slice(0, 10);

  if (!ouvert) {
    return (
      <button
        onClick={() => setOuvert(true)}
        className="w-full text-xs text-muted-foreground hover:text-foreground underline mb-4"
      >
        Je ne peux pas assurer cette mission (empêchement impérieux)
      </button>
    );
  }

  const soumettre = async () => {
    if (!debut || !fin || !surHonneur || envoi) return;
    setEnvoi(true);
    const { data, error } = await supabase.rpc('fn_declarer_empechement_imperieux' as any, {
      p_mission_id: missionId,
      p_indispo_debut: debut,
      p_indispo_fin: fin,
    });
    setEnvoi(false);
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Déclaration impossible.');
      return;
    }
    if ((data as any)?.depassement) {
      toast.warning('Empêchement enregistré. Attention : au-delà de ' + ((data as any).max_12_mois ?? 2) +
        ' empêchements sur 12 mois, une pénalité de score s\'applique.');
    } else {
      toast.success('Empêchement enregistré — l\'établissement est prévenu. Aucun justificatif à fournir.');
    }
    onDeclare();
  };

  return (
    <div className="border border-warning/30 bg-warning/5 rounded-xl p-3 mb-4 space-y-3">
      <p className="text-sm font-semibold text-foreground">Empêchement impérieux</p>
      <p className="text-xs text-muted-foreground">
        Indiquez vos dates d'indisponibilité et attestez sur l'honneur. Aucun justificatif ni
        motif ne vous est demandé — l'établissement est prévenu immédiatement
        {' '}et un remplacement est recherché si la mission est garantie.
      </p>
      <div className="grid grid-cols-2 gap-2">
        <div>
          <label htmlFor="emp-debut" className="text-xs text-muted-foreground mb-1 block">Indisponible du *</label>
          <input id="emp-debut" type="date" value={debut} min={aujourdHui}
            onChange={(e) => setDebut(e.target.value)} className="input-base" />
        </div>
        <div>
          <label htmlFor="emp-fin" className="text-xs text-muted-foreground mb-1 block">au *</label>
          <input id="emp-fin" type="date" value={fin} min={debut || aujourdHui}
            onChange={(e) => setFin(e.target.value)} className="input-base" />
        </div>
      </div>
      <label className="flex items-start gap-2 cursor-pointer">
        <input type="checkbox" checked={surHonneur} onChange={(e) => setSurHonneur(e.target.checked)}
          className="mt-0.5 accent-primary" />
        <span className="text-xs text-foreground">
          J'atteste sur l'honneur d'un empêchement impérieux m'empêchant d'assurer cette mission.
          Une fausse déclaration engage ma responsabilité.
        </span>
      </label>
      <div className="flex gap-2">
        <button onClick={() => setOuvert(false)} className="btn-secondary flex-1 text-sm py-2">
          Retour
        </button>
        <button onClick={soumettre} disabled={!debut || !fin || !surHonneur || envoi}
          className="btn-primary flex-1 text-sm py-2 disabled:opacity-50">
          {envoi ? 'Envoi…' : 'Déclarer'}
        </button>
      </div>
    </div>
  );
}
