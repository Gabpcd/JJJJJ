import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { FileText, Banknote } from 'lucide-react';

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
}

export function ChoixContratDialog({ open, options, onChoose, onClose, loading }: Props) {
  const [selected, setSelected] = useState<string | null>(null);

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
        <div className="flex justify-end gap-2 mt-4">
          <Button variant="outline" onClick={onClose} disabled={loading}>Annuler</Button>
          <Button onClick={() => selected && onChoose(selected)} disabled={!selected || loading}>
            {loading ? 'Envoi…' : 'Confirmer'}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
