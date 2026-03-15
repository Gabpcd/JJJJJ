import { useNavigate } from 'react-router-dom';
import { CheckCircle2, Circle } from 'lucide-react';
import { JaugeProgression } from '@/components/JaugeProgression';

interface BarreCompletionProfilProps {
  nom: boolean;
  rppsVerifie: boolean;
  auMoinsUnDocument: boolean;
  adresseRenseignee: boolean;
  telephoneRenseigne: boolean;
}

export function BarreCompletionProfil({
  nom,
  rppsVerifie,
  auMoinsUnDocument,
  adresseRenseignee,
  telephoneRenseigne,
}: BarreCompletionProfilProps) {
  const navigate = useNavigate();

  const criteres: [boolean, string][] = [
    [nom, 'Nom rempli'],
    [rppsVerifie, 'RPPS vérifié'],
    [auMoinsUnDocument, 'Document uploadé'],
    [adresseRenseignee, 'Adresse renseignée'],
    [telephoneRenseigne, 'Téléphone renseigné'],
  ];

  const completes = criteres.filter(([ok]) => ok).length;
  const pourcentage = Math.round((completes / criteres.length) * 100);

  if (pourcentage === 100) return null;

  return (
    <div className="rounded-2xl bg-gradient-to-r from-primary/5 to-info/5 border border-primary/20 p-4 md:p-5 mb-6">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-semibold text-foreground">
          Profil complété à {pourcentage}%
        </h2>
        <button
          onClick={() => navigate('/soignant/profil')}
          className="text-xs text-[hsl(187,75%,40%)] font-medium hover:underline"
        >
          Compléter →
        </button>
      </div>
      <JaugeProgression
        valeur={pourcentage}
        max={100}
        couleurBarre="bg-[hsl(187,75%,40%)]"
        couleurFond="bg-[hsl(187,75%,40%)]/10"
      />
      <div className="mt-3 grid grid-cols-2 gap-1.5">
        {criteres.map(([ok, label]) => (
          <div key={label} className="flex items-center gap-1.5 text-xs">
            {ok ? (
              <CheckCircle2 className="h-3.5 w-3.5 text-[hsl(187,75%,40%)]" />
            ) : (
              <Circle className="h-3.5 w-3.5 text-muted-foreground" />
            )}
            <span className={ok ? 'text-[hsl(187,75%,40%)]' : 'text-muted-foreground'}>{label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
