import { TYPES_ETABLISSEMENT } from '@/lib/constantes';

interface SelectTypeEtablissementProps {
  id?: string;
  value: string;
  onChange: (val: string) => void;
  disabled?: boolean;
}

export function SelectTypeEtablissement({ id, value, onChange, disabled }: SelectTypeEtablissementProps) {
  return (
    <select
      id={id}
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
