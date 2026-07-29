import { LogoJolene } from '@/components/LogoJolene';

interface ChargementAdminProps {
  titre: string;
}

/** État de chargement qui conserve le titre de niveau 1 de la page admin. */
export function ChargementAdmin({ titre }: ChargementAdminProps) {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-foreground">{titre}</h1>
      <div
        className="min-h-[50vh] flex flex-col items-center justify-center gap-3 text-muted-foreground"
        role="status"
        aria-live="polite"
      >
        <LogoJolene
          afficherNom={false}
          decoratif
          imageClassName="h-10 w-10 animate-pulse"
        />
        <p className="text-sm font-medium">Chargement en cours…</p>
      </div>
    </div>
  );
}

export function ChargementSectionAdmin({ label = 'Chargement en cours…' }: { label?: string }) {
  return (
    <div className="min-h-48 flex flex-col items-center justify-center gap-3 text-muted-foreground" role="status" aria-live="polite">
      <LogoJolene
        afficherNom={false}
        decoratif
        imageClassName="h-8 w-8 animate-pulse"
      />
      <p className="text-sm font-medium">{label}</p>
    </div>
  );
}
