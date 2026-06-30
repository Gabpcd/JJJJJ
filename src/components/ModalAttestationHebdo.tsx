import React, { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Checkbox } from '@/components/ui/checkbox';
import { Loader2 } from 'lucide-react';

interface Props {
  semaineISO: string; // ISO date string of Monday of the week
  heuresJoleneSemaine: number;
  onValidated: () => void;
  onCancel: () => void;
}

export function ModalAttestationHebdo({ semaineISO, heuresJoleneSemaine, onValidated, onCancel }: Props) {
  const { user } = useAuth();
  const [heures, setHeures] = useState(0);
  const [employeur, setEmployeur] = useState('');
  const [atteste, setAtteste] = useState(false);
  const [saving, setSaving] = useState(false);
  const [erreur, setErreur] = useState('');

  const totalSemaine = heuresJoleneSemaine + heures;
  const depasse48h = totalSemaine > 48;

  const handleValider = async () => {
    if (!atteste) return;
    if (!employeur.trim() && heures > 0) {
      setErreur("Renseigne le nom de ton employeur.");
      return;
    }
    if (depasse48h) {
      setErreur(`Tu dépasserais le plafond de 48h/semaine (${heuresJoleneSemaine}h Jolene + ${heures}h ailleurs = ${totalSemaine}h).`);
      return;
    }

    setSaving(true);
    setErreur('');

    const { error } = await supabase.from('attestations_heures_externes').insert({
      soignant_id: user!.id,
      semaine_du: semaineISO,
      heures_salarie: heures,
      employeur_principal: employeur.trim() || null,
      attestation_honneur: true,
    } as any);

    if (error) {
      // Duplicate entry = already filled → proceed
      if (error.code === '23505') {
        onValidated();
      } else {
        setErreur(error.message);
      }
    } else {
      onValidated();
    }
    setSaving(false);
  };

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center">
      <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={onCancel} />
      <div className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-full space-y-4">
        <h3 className="text-lg font-bold text-foreground">📋 Déclaration hebdomadaire</h3>
        <p className="text-sm text-muted-foreground">
          Déclare tes heures travaillées ailleurs cette semaine avant d'accepter cette mission.
        </p>

        <div>
          <label className="text-sm font-medium text-foreground mb-1.5 block">
            Heures chez ton employeur principal cette semaine
          </label>
          <input
            type="number"
            min={0}
            max={60}
            value={heures}
            onChange={e => { setHeures(Math.max(0, Math.min(60, Number(e.target.value)))); setErreur(''); }}
            className="input-base"
            placeholder="0"
          />
        </div>

        <div>
          <label className="text-sm font-medium text-foreground mb-1.5 block">Nom de l'employeur</label>
          <input
            value={employeur}
            onChange={e => setEmployeur(e.target.value)}
            className="input-base"
            placeholder="Ex: CHU de Lyon"
          />
        </div>

        {depasse48h && (
          <div className="rounded-xl bg-destructive/10 border border-destructive/20 p-3">
            <p className="text-sm text-destructive font-medium">
              ⛔ Tu dépasserais le plafond de 48h/semaine ({heuresJoleneSemaine}h Jolene + {heures}h ailleurs = {totalSemaine}h).
            </p>
          </div>
        )}

        <label className="flex items-start gap-3 cursor-pointer">
          <Checkbox
            checked={atteste}
            onCheckedChange={(v) => setAtteste(!!v)}
            className="mt-0.5"
          />
          <span className="text-xs text-foreground leading-relaxed">
            J'atteste sur l'honneur que ces informations sont exactes. Je comprends que toute déclaration fausse engage ma responsabilité.
          </span>
        </label>

        {erreur && !depasse48h && (
          <p className="text-sm text-destructive">{erreur}</p>
        )}

        <div className="flex gap-3 pt-2">
          <button
            onClick={onCancel}
            className="flex-1 btn-secondary text-sm py-2.5"
          >
            Annuler
          </button>
          <button
            onClick={handleValider}
            disabled={!atteste || depasse48h || saving}
            className="flex-1 btn-primary text-sm py-2.5 disabled:opacity-50 flex items-center justify-center gap-2"
          >
            {saving ? <><Loader2 className="h-4 w-4 animate-spin" /> Enregistrement…</> : '✅ Valider et continuer'}
          </button>
        </div>
      </div>
    </div>
  );
}
