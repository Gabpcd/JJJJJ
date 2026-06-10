import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { FileText, Banknote } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

interface Option {
  value: string;
  label: string;
}

interface Props {
  open: boolean;
  options: Option[];
  onChoose: (value: string) => void;
  onClose: () => void;
  loading?: boolean;
  /** Affiche "Se souvenir de mon choix" — enregistre soignants.preference_contrat_mixte
   *  (le backend l'applique ensuite automatiquement : plus de dialog). */
  proposerMemorisation?: boolean;
}

export function ChoixContratDialog({ open, options, onChoose, onClose, loading, proposerMemorisation }: Props) {
  const [selected, setSelected] = useState<string | null>(null);
  const [memoriser, setMemoriser] = useState(true);

  const confirmer = async () => {
    if (!selected) return;
    if (proposerMemorisation && memoriser) {
      const { data: auth } = await supabase.auth.getUser();
      if (auth.user) {
        await supabase.from('soignants')
          .update({ preference_contrat_mixte: selected } as any)
          .eq('id', auth.user.id);
      }
    }
    onChoose(selected);
  };

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Choisissez votre mode de contrat</DialogTitle>
          <DialogDescription>
            Cette mission accepte les deux types de contrat. Sélectionnez celui qui correspond à votre situation.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3 mt-2">
          {options.map(opt => (
            <button
              key={opt.value}
              onClick={() => setSelected(opt.value)}
              className={`w-full flex items-center gap-3 p-4 rounded-xl border-2 text-left transition-colors ${
                selected === opt.value
                  ? 'border-primary bg-primary/5'
                  : 'border-border hover:border-primary/40'
              }`}
            >
              {opt.value === 'LIBERAL' ? (
                <FileText className="h-5 w-5 text-blue-500 shrink-0" />
              ) : (
                <Banknote className="h-5 w-5 text-muted-foreground shrink-0" />
              )}
              <div>
                <p className="text-sm font-semibold text-foreground">{opt.label}</p>
              </div>
            </button>
          ))}
        </div>
        {proposerMemorisation && (
          <label className="flex items-center gap-2 mt-3 text-sm text-muted-foreground cursor-pointer select-none">
            <input
              type="checkbox"
              checked={memoriser}
              onChange={e => setMemoriser(e.target.checked)}
              className="h-4 w-4 rounded border-border accent-primary"
            />
            Se souvenir de mon choix (modifiable dans mon profil)
          </label>
        )}
        <div className="flex justify-end gap-2 mt-4">
          <BoutonY2K variant="secondary" onClick={onClose} disabled={loading}>Annuler</BoutonY2K>
          <BoutonY2K onClick={confirmer} disabled={!selected || loading} loading={loading}>
            {loading ? 'Envoi…' : 'Confirmer'}
          </BoutonY2K>
        </div>
      </DialogContent>
    </Dialog>
  );
}
