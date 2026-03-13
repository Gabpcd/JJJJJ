import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowRight, X, CheckCircle2 } from 'lucide-react';
import { UserRole } from '@/lib/types';
import { JaugeProgression } from '@/components/JaugeProgression';

interface Etape {
  titre: string;
  description: string;
  lien?: string;
  labelLien?: string;
}

const ETAPES_SOIGNANT: Etape[] = [
  { titre: 'Bienvenue ! Complétez votre profil', description: 'Renseignez vos informations personnelles, votre profession et votre numéro RPPS.', lien: '/soignant/profil', labelLien: 'Compléter mon profil' },
  { titre: 'Téléversez vos documents', description: 'Ajoutez vos diplômes, pièce d\'identité et attestations pour être éligible aux missions.', lien: '/soignant/documents', labelLien: 'Ajouter mes documents' },
  { titre: 'Trouvez une mission', description: 'Parcourez les missions disponibles près de chez vous et postulez en un clic.', lien: '/soignant/missions', labelLien: 'Voir les missions' },
  { titre: 'Acceptez et signez le contrat', description: 'Une fois sélectionné(e), signez votre contrat de mission directement en ligne.' },
  { titre: 'Pointez votre arrivée le jour J', description: 'Le jour de la mission, pointez votre arrivée et votre départ via l\'application.' },
];

const ETAPES_ETABLISSEMENT: Etape[] = [
  { titre: 'Complétez votre profil', description: 'Renseignez les informations de votre établissement (adresse, FINESS, contact).', lien: '/etablissement/profil', labelLien: 'Compléter le profil' },
  { titre: 'Publiez votre première mission', description: 'Décrivez le besoin, les horaires et le taux horaire. Les soignants qualifiés seront notifiés.', lien: '/etablissement/missions/creer', labelLien: 'Publier une mission' },
  { titre: 'Gérez les candidatures', description: 'Consultez les profils des soignants intéressés, vérifiez leur score de fiabilité et sélectionnez le meilleur candidat.' },
  { titre: 'Validez les présences et payez', description: 'À la fin de chaque mission, validez les heures pointées. La facturation et le paiement sont automatisés.' },
];

const STORAGE_KEY = 'onboarding_complete';

function getStorageKey(userId: string) {
  return `${STORAGE_KEY}_${userId}`;
}

interface OnboardingGuideProps {
  role: UserRole;
  userId: string;
}

export function OnboardingGuide({ role, userId }: OnboardingGuideProps) {
  const navigate = useNavigate();
  const [etapeCourante, setEtapeCourante] = useState(0);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const done = localStorage.getItem(getStorageKey(userId));
    if (!done) setVisible(true);
  }, [userId]);

  const etapes = role === 'SOIGNANT' ? ETAPES_SOIGNANT : ETAPES_ETABLISSEMENT;
  const progression = Math.round(((etapeCourante + 1) / etapes.length) * 100);

  const fermer = () => {
    localStorage.setItem(getStorageKey(userId), 'true');
    setVisible(false);
  };

  const suivant = () => {
    if (etapeCourante < etapes.length - 1) {
      setEtapeCourante(etapeCourante + 1);
    } else {
      fermer();
    }
  };

  if (!visible) return null;

  const etape = etapes[etapeCourante];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-card rounded-2xl shadow-2xl max-w-md w-full overflow-hidden animate-in fade-in zoom-in-95 duration-300">
        {/* Header with progress */}
        <div className="px-6 pt-6 pb-4">
          <div className="flex items-center justify-between mb-4">
            <span className="text-xs font-semibold text-[hsl(187,75%,40%)]">
              Étape {etapeCourante + 1} / {etapes.length}
            </span>
            <button
              onClick={fermer}
              className="text-muted-foreground hover:text-foreground transition-colors rounded-full p-1"
              aria-label="Passer l'introduction"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
          <JaugeProgression
            valeur={etapeCourante + 1}
            max={etapes.length}
            couleurBarre="bg-[hsl(187,75%,40%)]"
            couleurFond="bg-[hsl(187,75%,40%)]/10"
          />
        </div>

        {/* Content */}
        <div className="px-6 pb-2">
          <div className="flex items-start gap-3 mb-3">
            <div className="rounded-full p-2 bg-[hsl(187,75%,40%)]/10 shrink-0 mt-0.5">
              <CheckCircle2 className="h-5 w-5 text-[hsl(187,75%,40%)]" />
            </div>
            <div>
              <h2 className="text-lg font-bold text-foreground leading-tight">{etape.titre}</h2>
              <p className="text-sm text-muted-foreground mt-2 leading-relaxed">{etape.description}</p>
            </div>
          </div>

          {etape.lien && (
            <button
              onClick={() => { fermer(); navigate(etape.lien!); }}
              className="mt-2 text-sm font-medium text-[hsl(187,75%,40%)] hover:underline flex items-center gap-1"
            >
              {etape.labelLien} <ArrowRight className="h-3.5 w-3.5" />
            </button>
          )}
        </div>

        {/* Footer */}
        <div className="px-6 py-4 flex items-center justify-between border-t border-border mt-4">
          <button
            onClick={fermer}
            className="text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            Passer
          </button>
          <button
            onClick={suivant}
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-semibold text-white bg-[hsl(187,75%,40%)] hover:bg-[hsl(187,75%,33%)] transition-colors"
          >
            {etapeCourante < etapes.length - 1 ? 'Suivant' : 'Commencer'}
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>

        {/* Step dots */}
        <div className="flex items-center justify-center gap-1.5 pb-5">
          {etapes.map((_, i) => (
            <div
              key={i}
              className={`h-1.5 rounded-full transition-all duration-300 ${
                i === etapeCourante
                  ? 'w-6 bg-[hsl(187,75%,40%)]'
                  : i < etapeCourante
                  ? 'w-1.5 bg-[hsl(187,75%,40%)]/50'
                  : 'w-1.5 bg-muted-foreground/20'
              }`}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
