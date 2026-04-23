import { useState } from 'react';
import { ExternalLink, CheckCircle2, Info } from 'lucide-react';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { Checkbox } from '@/components/ui/checkbox';

export interface Etape {
  cle: string;
  label: string;
  description?: string;
  lienExterne?: string;
  lienLabel?: string;
  informatif?: boolean;
}

interface Props {
  etapes: Etape[];
  etapesValidees: Record<string, unknown>;
  onToggle: (cle: string, valeur: boolean) => Promise<void>;
  disabled?: boolean;
}

export function ChecklistEtapes({ etapes, etapesValidees, onToggle, disabled }: Props) {
  const [optimistic, setOptimistic] = useState<Record<string, boolean>>({});
  const [saving, setSaving] = useState<Record<string, boolean>>({});

  const isChecked = (cle: string) => {
    if (cle in optimistic) return optimistic[cle];
    return Boolean(etapesValidees[cle]);
  };

  const getDateValidation = (cle: string): string | null => {
    const d = etapesValidees[`${cle}_date`];
    return typeof d === 'string' && d !== 'null' ? d : null;
  };

  const handleToggle = async (cle: string, val: boolean) => {
    setOptimistic(prev => ({ ...prev, [cle]: val }));
    setSaving(prev => ({ ...prev, [cle]: true }));
    try {
      await onToggle(cle, val);
      setOptimistic(prev => {
        const { [cle]: _removed, ...rest } = prev;
        return rest;
      });
    } catch {
      setOptimistic(prev => ({ ...prev, [cle]: !val }));
      toast.error('Impossible de mettre à jour cette étape.');
      setTimeout(() => {
        setOptimistic(prev => {
          const { [cle]: _removed, ...rest } = prev;
          return rest;
        });
      }, 2000);
    } finally {
      setSaving(prev => ({ ...prev, [cle]: false }));
    }
  };

  return (
    <div className="space-y-2">
      {etapes.map(etape => {
        const checked = isChecked(etape.cle);
        const dateVal = checked ? getDateValidation(etape.cle) : null;

        return (
          <div
            key={etape.cle}
            className={`rounded-xl border p-3 transition-colors duration-200 ${checked ? 'border-success/30 bg-success/5' : 'border-border bg-card hover:bg-muted/30'}`}
          >
            <div className="flex items-start gap-3">
              {etape.informatif ? (
                <Info className="h-5 w-5 text-info shrink-0 mt-0.5" />
              ) : (
                <Checkbox
                  id={`etape-${etape.cle}`}
                  checked={checked}
                  disabled={disabled || saving[etape.cle]}
                  onCheckedChange={(c) => handleToggle(etape.cle, Boolean(c))}
                  className="mt-0.5 shrink-0"
                />
              )}
              <div className="flex-1 min-w-0">
                <label
                  htmlFor={`etape-${etape.cle}`}
                  className={`text-sm font-semibold block ${etape.informatif ? '' : 'cursor-pointer'} ${checked ? 'text-success' : 'text-foreground'}`}
                >
                  {etape.label}
                </label>
                {etape.description && (
                  <p className="text-xs text-muted-foreground mt-1">{etape.description}</p>
                )}
                {checked && dateVal && (
                  <p className="text-[11px] text-success mt-1 flex items-center gap-1">
                    <CheckCircle2 className="h-3 w-3" />
                    Validé le {format(new Date(dateVal), 'd MMM yyyy', { locale: fr })}
                  </p>
                )}
                {etape.lienExterne && (
                  <a
                    href={etape.lienExterne}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-xs text-primary hover:underline mt-2"
                  >
                    {etape.lienLabel || 'Ouvrir le site'}
                    <ExternalLink className="h-3 w-3" />
                  </a>
                )}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
