import { PROFESSIONS } from '@/lib/constantes';

interface SelectProfessionProps {
  value: string;
  onChange: (val: string) => void;
  disabled?: boolean;
  filtresProfessions?: string[];
}

export function SelectProfession({ value, onChange, disabled, filtresProfessions }: SelectProfessionProps) {
  const options = filtresProfessions
    ? PROFESSIONS.filter(p => filtresProfessions.includes(p.valeur))
    : PROFESSIONS;

  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      disabled={disabled}
      className="input-base disabled:bg-muted disabled:cursor-not-allowed"
    >
      <option value="">Sélectionnez votre profession</option>
      {options.map((p) => (
        <option key={p.valeur} value={p.valeur}>{p.label}</option>
      ))}
    </select>
  );
}
