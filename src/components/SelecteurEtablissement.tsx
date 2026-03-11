import React from 'react';
import { getLabelTypeEtablissement } from '@/lib/constantes';

interface SelecteurEtablissementProps {
  etablissements: any[];
  valeur: string;
  onChange: (id: string) => void;
  avecFiltres?: boolean;
  filtreDepartement?: string;
  onChangeDepartement?: (dep: string) => void;
  filtreType?: string;
  onChangeType?: (type: string) => void;
}

export function SelecteurEtablissement({
  etablissements, valeur, onChange, avecFiltres,
  filtreDepartement, onChangeDepartement, filtreType, onChangeType,
}: SelecteurEtablissementProps) {
  const departements = [...new Set(etablissements.map(e => e.adresse_departement).filter(Boolean))].sort();
  const types = [...new Set(etablissements.map(e => e.type).filter(Boolean))].sort();

  return (
    <div className="space-y-3">
      <select
        value={valeur}
        onChange={(e) => onChange(e.target.value)}
        className="input-base font-medium"
      >
        <option value="tous">📊 Vue groupe — Tous les établissements ({etablissements.length})</option>
        {etablissements.map(e => (
          <option key={e.id} value={e.id}>
            {e.nom} — {e.adresse_ville} {e.adresse_departement ? `(${e.adresse_departement})` : ''}
          </option>
        ))}
      </select>

      {avecFiltres && (
        <div className="flex gap-2 flex-wrap">
          <select
            value={filtreDepartement || ''}
            onChange={(e) => onChangeDepartement?.(e.target.value)}
            className="input-base text-sm flex-1 min-w-[150px]"
          >
            <option value="">Tous les départements</option>
            {departements.map(d => (
              <option key={d} value={d}>{d}</option>
            ))}
          </select>
          <select
            value={filtreType || ''}
            onChange={(e) => onChangeType?.(e.target.value)}
            className="input-base text-sm flex-1 min-w-[150px]"
          >
            <option value="">Tous les types</option>
            {types.map(t => (
              <option key={t} value={t}>{getLabelTypeEtablissement(t)}</option>
            ))}
          </select>
          {(filtreDepartement || filtreType) && (
            <button
              onClick={() => { onChangeDepartement?.(''); onChangeType?.(''); }}
              className="text-xs text-primary hover:underline px-2"
            >
              Réinitialiser
            </button>
          )}
        </div>
      )}
    </div>
  );
}
