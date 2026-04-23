import { useEffect, useMemo, useState } from 'react';
import { Check, ChevronsUpDown, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';

interface Specialite {
  code: string;
  label: string;
  profession_parent: string;
}

interface Props {
  value: string;
  onChange: (code: string) => void;
  professionParent?: string;
  disabled?: boolean;
  placeholder?: string;
}

function normalize(s: string): string {
  return s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
}

export function SelectSpecialiteMedicale({
  value,
  onChange,
  professionParent = 'MEDECIN',
  disabled,
  placeholder,
}: Props) {
  const [open, setOpen] = useState(false);
  const [specialites, setSpecialites] = useState<Specialite[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    supabase
      .from('specialites_medicales' as any)
      .select('code, label, profession_parent')
      .eq('profession_parent', professionParent)
      .eq('actif', true)
      .order('label', { ascending: true })
      .then(({ data }) => {
        if (!cancelled) {
          setSpecialites((data as unknown as Specialite[]) ?? []);
          setLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [professionParent]);

  const selected = useMemo(() => specialites.find(s => s.code === value), [specialites, value]);

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          type="button"
          variant="outline"
          role="combobox"
          aria-expanded={open}
          disabled={disabled || loading}
          className={cn(
            'input-base w-full justify-between font-normal min-h-11',
            !selected && 'text-muted-foreground',
            (disabled || loading) && 'bg-muted cursor-not-allowed'
          )}
        >
          <span className="truncate text-left">
            {loading
              ? 'Chargement...'
              : selected
                ? selected.label
                : (placeholder ?? 'Sélectionnez une spécialité')}
          </span>
          {loading ? (
            <Loader2 className="ml-2 h-4 w-4 shrink-0 animate-spin opacity-50" />
          ) : (
            <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent
        className="p-0 w-[var(--radix-popover-trigger-width)] max-w-[calc(100vw-2rem)]"
        align="start"
      >
        <Command
          filter={(itemValue, search) => {
            const opt = specialites.find(s => s.code === itemValue);
            if (!opt) return 0;
            const haystack = normalize(`${opt.label} ${opt.code}`);
            const needle = normalize(search);
            return haystack.includes(needle) ? 1 : 0;
          }}
        >
          <CommandInput placeholder="Rechercher une spécialité..." className="h-11" />
          <CommandList>
            <CommandEmpty>Aucune spécialité trouvée.</CommandEmpty>
            <CommandGroup>
              {specialites.map(s => (
                <CommandItem
                  key={s.code}
                  value={s.code}
                  onSelect={(v) => {
                    onChange(v);
                    setOpen(false);
                  }}
                  className="cursor-pointer"
                >
                  <Check
                    className={cn('mr-2 h-4 w-4', value === s.code ? 'opacity-100' : 'opacity-0')}
                  />
                  <span className="truncate">{s.label}</span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
