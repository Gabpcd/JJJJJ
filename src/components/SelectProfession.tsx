import { useState, useMemo } from 'react';
import { Check, ChevronsUpDown } from 'lucide-react';
import { PROFESSIONS } from '@/lib/constantes';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';

interface SelectProfessionProps {
  value: string;
  onChange: (val: string) => void;
  disabled?: boolean;
  filtresProfessions?: string[];
  placeholder?: string;
  triggerId?: string;
}

function normalize(s: string): string {
  return s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
}

export function SelectProfession({ value, onChange, disabled, filtresProfessions, placeholder, triggerId }: SelectProfessionProps) {
  const [open, setOpen] = useState(false);

  const options = useMemo(
    () => (filtresProfessions ? PROFESSIONS.filter(p => filtresProfessions.includes(p.valeur)) : PROFESSIONS),
    [filtresProfessions]
  );

  const selected = options.find(p => p.valeur === value);

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          type="button"
          variant="outline"
          role="combobox"
          id={triggerId}
          aria-expanded={open}
          disabled={disabled}
          className={cn(
            'input-base w-full justify-between font-normal min-h-11',
            !selected && 'text-muted-foreground',
            disabled && 'bg-muted cursor-not-allowed'
          )}
        >
          <span className="truncate text-left">
            {selected ? selected.label : (placeholder ?? 'Sélectionnez votre profession')}
          </span>
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent
        className="p-0 w-[var(--radix-popover-trigger-width)] max-w-[calc(100vw-2rem)]"
        align="start"
      >
        <Command
          filter={(itemValue, search) => {
            const opt = options.find(p => p.valeur === itemValue);
            if (!opt) return 0;
            const haystack = normalize(`${opt.label} ${opt.valeur}`);
            const needle = normalize(search);
            return haystack.includes(needle) ? 1 : 0;
          }}
        >
          <CommandInput placeholder="Rechercher une profession..." className="h-11" />
          <CommandList>
            <CommandEmpty>Aucune profession trouvée.</CommandEmpty>
            <CommandGroup>
              {options.map(p => (
                <CommandItem
                  key={p.valeur}
                  value={p.valeur}
                  data-testid={`profession-option-${p.valeur}`}
                  onSelect={(v) => {
                    onChange(v);
                    setOpen(false);
                  }}
                  className="cursor-pointer"
                >
                  <Check
                    className={cn('mr-2 h-4 w-4', value === p.valeur ? 'opacity-100' : 'opacity-0')}
                  />
                  <span className="truncate">{p.label}</span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
