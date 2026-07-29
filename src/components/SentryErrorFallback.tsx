import { LogoJolene } from '@/components/LogoJolene';

interface Props {
  resetError: () => void;
}

export function SentryErrorFallback({ resetError }: Props) {
  return (
    <div className="min-h-[100dvh] flex items-center justify-center bg-background p-6">
      <div className="text-center max-w-md space-y-4">
        <LogoJolene
          afficherNom={false}
          decoratif
          className="mx-auto"
          imageClassName="h-12 w-12"
        />
        <h1 className="text-2xl font-bold text-foreground">
          Une erreur est survenue
        </h1>
        <p className="text-muted-foreground">
          Notre équipe a été notifiée et travaille à résoudre le problème.
        </p>
        <button
          onClick={resetError}
          className="inline-flex items-center justify-center rounded-md bg-primary px-6 py-3 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90 transition-colors"
        >
          Réessayer
        </button>
      </div>
    </div>
  );
}
