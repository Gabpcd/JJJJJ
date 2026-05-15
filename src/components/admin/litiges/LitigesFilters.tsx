import React from 'react';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { RotateCcw } from 'lucide-react';
import {
  TYPES_LITIGE,
  CATEGORIES_LITIGE,
  STATUTS_OUVERTS,
  LABELS_TYPE_LITIGE,
  LABELS_CATEGORIE,
  LABELS_STATUT,
  FILTRES_DEFAUT,
  type FiltresLitiges,
} from './types';

type Props = {
  filtres: FiltresLitiges;
  onChange: (f: FiltresLitiges) => void;
};

export function LitigesFilters({ filtres, onChange }: Props) {
  const reset = () => onChange(FILTRES_DEFAUT);

  return (
    <div className="flex flex-wrap items-end gap-3 rounded-lg border bg-muted/30 p-3">
      <div className="min-w-[180px] flex-1">
        <Label className="mb-1.5 block text-xs">Type de litige</Label>
        <Select
          value={filtres.type_litige}
          onValueChange={(v) =>
            onChange({ ...filtres, type_litige: v as FiltresLitiges['type_litige'] })
          }
        >
          <SelectTrigger aria-label="Filtre type de litige">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="TOUS">Tous</SelectItem>
            {TYPES_LITIGE.map((t) => (
              <SelectItem key={t} value={t}>
                {LABELS_TYPE_LITIGE[t]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="min-w-[160px] flex-1">
        <Label className="mb-1.5 block text-xs">Catégorie</Label>
        <Select
          value={filtres.categorie_litige}
          onValueChange={(v) =>
            onChange({ ...filtres, categorie_litige: v as FiltresLitiges['categorie_litige'] })
          }
        >
          <SelectTrigger aria-label="Filtre catégorie">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="TOUTES">Toutes</SelectItem>
            {CATEGORIES_LITIGE.map((c) => (
              <SelectItem key={c} value={c}>
                {LABELS_CATEGORIE[c]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="min-w-[160px] flex-1">
        <Label className="mb-1.5 block text-xs">Statut</Label>
        <Select
          value={filtres.statut}
          onValueChange={(v) =>
            onChange({ ...filtres, statut: v as FiltresLitiges['statut'] })
          }
        >
          <SelectTrigger aria-label="Filtre statut">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="TOUS_OUVERTS">Tous ouverts</SelectItem>
            {STATUTS_OUVERTS.map((s) => (
              <SelectItem key={s} value={s}>
                {LABELS_STATUT[s]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="min-w-[160px] flex-1">
        <Label className="mb-1.5 block text-xs">Tri</Label>
        <Select
          value={filtres.tri}
          onValueChange={(v) =>
            onChange({ ...filtres, tri: v as FiltresLitiges['tri'] })
          }
        >
          <SelectTrigger aria-label="Tri">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="GRAVITE">Par gravité</SelectItem>
            <SelectItem value="TRESORERIE">Par trésorerie bloquée</SelectItem>
            <SelectItem value="ESCALADE_MEDIATION">Par escalade médiation</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <BoutonY2K
        type="button"
        size="sm"
        variant="secondary"
        onClick={reset}
        aria-label="Réinitialiser les filtres"
        iconeGauche={<RotateCcw className="h-3.5 w-3.5" />}
      >
        Reset filtres
      </BoutonY2K>
    </div>
  );
}
