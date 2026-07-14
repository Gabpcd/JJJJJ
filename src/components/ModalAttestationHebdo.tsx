import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Checkbox } from '@/components/ui/checkbox';
import { Loader2 } from 'lucide-react';

interface Props {
  semaineISO: string; // ISO date string of Monday of the week
  heuresJoleneSemaine: number;
  onValidated: (peutContinuer: boolean) => void;
  onCancel: () => void;
}

export function ModalAttestationHebdo({ semaineISO, heuresJoleneSemaine, onValidated, onCancel }: Props) {
  const { user } = useAuth();
  const [heures, setHeures] = useState(0);
  const [employeur, setEmployeur] = useState('');
  const [atteste, setAtteste] = useState(false);
  const [saving, setSaving] = useState(false);
  const [erreur, setErreur] = useState('');
  const dialogRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const precedent = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const dialog = dialogRef.current;
    const elements = () => Array.from(dialog?.querySelectorAll<HTMLElement>(
      'button:not([disabled]), input:not([disabled]), [href], [tabindex]:not([tabindex="-1"])',
    ) ?? []).filter((element) => !element.hasAttribute('aria-hidden'));

    elements()[0]?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !saving) {
        event.preventDefault();
        onCancel();
        return;
      }
      if (event.key !== 'Tab') return;
      const focusables = elements();
      if (focusables.length === 0) {
        event.preventDefault();
        dialog?.focus();
        return;
      }
      const premier = focusables[0];
      const dernier = focusables[focusables.length - 1];
      if (event.shiftKey && document.activeElement === premier) {
        event.preventDefault();
        dernier.focus();
      } else if (!event.shiftKey && document.activeElement === dernier) {
        event.preventDefault();
        premier.focus();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      precedent?.focus();
    };
  }, [onCancel, saving]);

  const totalSemaine = heuresJoleneSemaine + heures;
  const depasse48h = totalSemaine > 48;

  const handleValider = async () => {
    if (!atteste) return;
    if (!employeur.trim() && heures > 0) {
      setErreur("Renseigne le nom de ton employeur.");
      return;
    }
    if (!user) {
      setErreur('Ta session a expiré. Reconnecte-toi avant d’enregistrer cette déclaration.');
      return;
    }

    setSaving(true);
    setErreur('');

    const { error } = await supabase.from('attestations_heures_externes').insert({
      soignant_id: user.id,
      semaine_du: semaineISO,
      heures_salarie: heures,
      employeur_principal: employeur.trim() || null,
      attestation_honneur: true,
    } as any);

    if (error) {
      if (error.code === '23505') {
        setErreur('Une déclaration existe déjà pour cette semaine. Ferme cette fenêtre puis relance l’acceptation pour utiliser les données enregistrées.');
      } else {
        setErreur('Impossible d’enregistrer la déclaration. Vérifie les informations puis réessaie.');
      }
    } else {
      // Une déclaration véridique est toujours conservée. Le dépassement
      // bloque seulement l'acceptation et ouvre une revue de conformité.
      onValidated(!depasse48h);
    }
    setSaving(false);
  };

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center">
      <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={saving ? undefined : onCancel} aria-hidden="true" />
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="attestation-hebdo-titre"
        aria-describedby="attestation-hebdo-description"
        tabIndex={-1}
        className="relative bg-card rounded-2xl shadow-xl p-6 mx-4 max-w-md w-full max-h-[calc(100dvh-2rem)] overflow-y-auto space-y-4"
      >
        <h3 id="attestation-hebdo-titre" className="text-lg font-bold text-foreground">📋 Déclaration hebdomadaire</h3>
        <p id="attestation-hebdo-description" className="text-sm text-muted-foreground">
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
          <div className="rounded-xl bg-destructive/10 border border-destructive/20 p-3" role="alert">
            <p className="text-sm text-destructive font-medium">
              Ta déclaration sera enregistrée, mais cette mission ne pourra pas être acceptée : {heuresJoleneSemaine}h Jolene + {heures}h ailleurs = {totalSemaine}h, au-delà du plafond de 48h. Si une mission est déjà affectée, l'équipe Jolene vérifiera la situation.
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

        {erreur && (
          <p className="text-sm text-destructive" role="alert">{erreur}</p>
        )}

        <div className="flex gap-3 pt-2">
          <button
            onClick={onCancel}
            disabled={saving}
            className="flex-1 min-h-11 btn-secondary text-sm py-2.5"
          >
            Annuler
          </button>
          <button
            onClick={handleValider}
            disabled={!atteste || saving}
            className="flex-1 min-h-11 btn-primary text-sm py-2.5 disabled:opacity-50 flex items-center justify-center gap-2"
          >
            {saving
              ? <><Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> Enregistrement…</>
              : depasse48h ? 'Enregistrer sans accepter' : 'Valider et continuer'}
          </button>
        </div>
      </div>
    </div>
  );
}
