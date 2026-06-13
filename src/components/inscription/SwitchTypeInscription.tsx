import { Link } from 'react-router-dom';

interface SwitchTypeInscriptionProps {
  actif: 'soignant' | 'etablissement';
}

export function SwitchTypeInscription({ actif }: SwitchTypeInscriptionProps) {
  return (
    <div className="flex justify-center mb-4" role="group" aria-label="Type de compte">
      <div className="inline-flex rounded-full border border-border bg-muted p-1 gap-1">
        <Link
          to="/inscription/soignant"
          className={`px-4 py-1.5 rounded-full text-sm font-medium transition-colors ${
            actif === 'soignant'
              ? 'bg-primary text-primary-foreground shadow-sm'
              : 'text-muted-foreground hover:text-foreground'
          }`}
          aria-current={actif === 'soignant' ? 'page' : undefined}
        >
          Je suis soignant
        </Link>
        <Link
          to="/inscription/etablissement"
          className={`px-4 py-1.5 rounded-full text-sm font-medium transition-colors ${
            actif === 'etablissement'
              ? 'bg-primary text-primary-foreground shadow-sm'
              : 'text-muted-foreground hover:text-foreground'
          }`}
          aria-current={actif === 'etablissement' ? 'page' : undefined}
        >
          Je suis établissement
        </Link>
      </div>
    </div>
  );
}
