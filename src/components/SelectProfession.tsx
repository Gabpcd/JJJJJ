import { PROFESSIONS } from '@/lib/constantes';

interface SelectProfessionProps {
  value: string;
  onChange: (val: string) => void;
  disabled?: boolean;
}

export function SelectProfession({ value, onChange, disabled }: SelectProfessionProps) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      disabled={disabled}
      className="input-base disabled:bg-muted disabled:cursor-not-allowed"
    >
      <option value="">Sélectionnez votre profession</option>
      {PROFESSIONS.map((p) => (
        <option key={p.valeur} value={p.valeur}>{p.label}</option>
      ))}
    </select>
  );
}
