import { presentationInternat } from '@/lib/internat-presentation';

export function StatutInternat({ value, declareEtudiant = false, profession, detail = false }: {
  value: unknown; declareEtudiant?: boolean; profession?: string | null; detail?: boolean;
}) {
  const info = presentationInternat(value, declareEtudiant, profession);
  if (!info) return null;
  const colors = info.tone === 'verified' ? 'bg-success/10 text-success' : info.tone === 'expired'
    ? 'bg-destructive/10 text-destructive' : 'bg-warning/10 text-warning';
  return <span className="inline-flex max-w-full flex-col gap-1 align-top" data-testid="internat-status">
    <span className={`inline-flex self-start break-words rounded-lg px-2 py-1 text-xs font-semibold ${colors}`}>{info.label}</span>
    {info.specialite && <span className="break-words text-xs text-foreground">Spécialité autorisée : {info.specialite}</span>}
    {info.validite && <span className="text-xs text-muted-foreground">Validité de la licence : {info.validite.split('-').reverse().join('/')}</span>}
    {detail && <span className="text-xs font-normal text-muted-foreground">{info.detail}</span>}
  </span>;
}
