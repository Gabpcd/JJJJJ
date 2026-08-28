import { useState, useMemo } from 'react';
import { Check, ChevronsUpDown } from 'lucide-react';
import { PROFESSIONS } from '@/lib/constantes';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { Drawer, DrawerContent, DrawerDescription, DrawerHeader, DrawerTitle, DrawerTrigger } from '@/components/ui/drawer';
import { useIsMobile } from '@/hooks/use-mobile';

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
  const isMobile = useIsMobile();

  const options = useMemo(
    () => (filtresProfessions ? PROFESSIONS.filter(p => filtresProfessions.includes(p.valeur)) : PROFESSIONS),
    [filtresProfessions]
  );

  const selected = options.find(p => p.valeur === value);

  const trigger = (
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
  );

  const choices = (mobile = false) => (
    <Command
      filter={(itemValue, search) => {
        const opt = options.find(p => p.valeur === itemValue);
        if (!opt) return 0;
        const haystack = normalize(`${opt.label} ${opt.valeur}`);
        const needle = normalize(search);
        return haystack.includes(needle) ? 1 : 0;
      }}
    >
      <CommandInput
        placeholder="Rechercher une profession..."
        className={mobile ? 'h-12 text-base' : 'h-11'}
        autoFocus={false}
      />
      <CommandList className={mobile ? 'max-h-[55dvh]' : undefined}>
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
              className={cn('cursor-pointer', mobile && 'min-h-12 px-3 text-base')}
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
  );

  if (isMobile) {
    return (
      <Drawer open={open} onOpenChange={setOpen} shouldScaleBackground={false}>
        <DrawerTrigger asChild>{trigger}</DrawerTrigger>
        <DrawerContent
          className="max-h-[82dvh] rounded-t-[24px] border-x-0 border-b-0 pb-[env(safe-area-inset-bottom)]"
          onOpenAutoFocus={(event) => event.preventDefault()}
        >
          <DrawerHeader className="pb-2 text-left">
            <DrawerTitle>Choisir une profession</DrawerTitle>
            <DrawerDescription>Parcours la liste ou touche la recherche pour filtrer.</DrawerDescription>
          </DrawerHeader>
          <div className="min-h-0 overflow-hidden px-2 pb-3">
            {choices(true)}
          </div>
        </DrawerContent>
      </Drawer>
    );
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>{trigger}</PopoverTrigger>
      <PopoverContent
        className="p-0 w-[var(--radix-popover-trigger-width)] max-w-[calc(100vw-2rem)]"
        align="start"
      >
        {choices()}
      </PopoverContent>
    </Popover>
  );
}
