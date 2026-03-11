import { TYPES_ETABLISSEMENT } from '@/lib/constantes';

interface SelectTypeEtablissementProps {
  value: string;
  onChange: (val: string) => void;
  disabled?: boolean;
}

export function SelectTypeEtablissement({ value, onChange, disabled }: SelectTypeEtablissementProps) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      disabled={disabled}
      className="input-base disabled:bg-muted disabled:cursor-not-allowed"
    >
      <option value="">Sélectionnez le type</option>
      {TYPES_ETABLISSEMENT.map((t) => (
        <option key={t.valeur} value={t.valeur}>{t.label}</option>
      ))}
    </select>
  );
}
