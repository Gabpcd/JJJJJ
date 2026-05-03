import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowRight, X, CheckCircle2, UserCircle, FileUp, Search, FileSignature, MapPin, Building2, PlusCircle, Users, CreditCard } from 'lucide-react';
import { UserRole } from '@/lib/types';
import { Progress } from '@/components/ui/progress';

interface Etape {
  titre: string;
  description: string;
  icone: React.ElementType;
  lien?: string;
  labelLien?: string;
}

const ETAPES_SOIGNANT: Etape[] = [
  { titre: 'Complétez votre profil', description: 'Renseignez vos informations personnelles, votre profession et votre numéro RPPS.', icone: UserCircle, lien: '/soignant/profil', labelLien: 'Compléter mon profil' },
  { titre: 'Téléversez vos documents', description: 'Ajoutez vos diplômes, pièce d\'identité et attestations pour être éligible aux missions.', icone: FileUp, lien: '/soignant/documents', labelLien: 'Ajouter mes documents' },
  { titre: 'Trouvez une mission', description: 'Parcourez les missions disponibles près de chez vous et postulez en un clic.', icone: Search, lien: '/soignant/missions', labelLien: 'Voir les missions' },
  { titre: 'Signez le contrat', description: 'Une fois sélectionné(e), signez votre contrat de mission directement en ligne.', icone: FileSignature },
  { titre: 'Pointez le jour J', description: 'Le jour de la mission, pointez votre arrivée et votre départ via l\'application.', icone: MapPin },
];

const ETAPES_ETABLISSEMENT: Etape[] = [
  { titre: 'Complétez votre profil', description: 'Renseignez les informations de votre établissement (adresse, FINESS, contact).', icone: Building2, lien: '/etablissement/profil', labelLien: 'Compléter le profil' },
  { titre: 'Publiez une mission', description: 'Décrivez le besoin, les horaires et le taux horaire. Les soignants qualifiés seront notifiés.', icone: PlusCircle, lien: '/etablissement/missions/creer', labelLien: 'Publier une mission' },
  { titre: 'Gérez les candidatures', description: 'Consultez les profils des soignants intéressés, vérifiez leur score de fiabilité.', icone: Users },
  { titre: 'Validez et payez', description: 'À la fin de chaque mission, validez les heures pointées. Facturation automatisée.', icone: CreditCard },
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
  const [direction, setDirection] = useState<'next' | 'prev'>('next');

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
      setDirection('next');
      setEtapeCourante(etapeCourante + 1);
    } else {
      fermer();
    }
  };

  const precedent = () => {
    if (etapeCourante > 0) {
      setDirection('prev');
      setEtapeCourante(etapeCourante - 1);
    }
  };

  if (!visible) return null;

  const etape = etapes[etapeCourante];
  const Icone = etape.icone;
  const isLast = etapeCourante === etapes.length - 1;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/55 p-4 overflow-y-auto" style={{ paddingTop: 'max(1rem, env(safe-area-inset-top))', paddingBottom: 'max(1rem, env(safe-area-inset-bottom))' }}>
      <div className="bg-card rounded-2xl shadow-2xl max-w-md w-full overflow-hidden animate-in fade-in zoom-in-95 duration-300 my-auto">
        {/* Header */}
        <div className="px-6 pt-6 pb-3">
          <div className="flex items-center justify-between mb-3">
            <span className="text-xs font-semibold text-primary">
              Étape {etapeCourante + 1} / {etapes.length}
            </span>
            <button
              onClick={fermer}
              className="text-muted-foreground hover:text-foreground transition-colors rounded-full p-1"
              aria-label="Passer l'introduction"
              title="Passer"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
          <Progress value={progression} className="h-1.5" />
        </div>

        {/* Content with transition */}
        <div
          key={etapeCourante}
          className={`px-6 py-6 animate-in duration-300 ${direction === 'next' ? 'slide-in-from-right-4' : 'slide-in-from-left-4'} fade-in`}
        >
          {/* Large icon */}
          <div className="flex justify-center mb-5">
            <div className="rounded-2xl p-5 bg-primary/10 animate-in zoom-in-50 duration-500">
              <Icone className="h-12 w-12 text-primary" />
            </div>
          </div>

          <div className="text-center space-y-2">
            <h2 className="text-lg font-bold text-foreground">{etape.titre}</h2>
            <p className="text-sm text-muted-foreground leading-relaxed">{etape.description}</p>
          </div>

          {etape.lien && (
            <button
              onClick={() => { fermer(); navigate(etape.lien!); }}
              className="mt-4 mx-auto flex items-center gap-1.5 text-sm font-medium text-primary hover:underline"
            >
              {etape.labelLien} <ArrowRight className="h-3.5 w-3.5" />
            </button>
          )}
        </div>

        {/* Footer */}
        <div className="px-6 py-4 flex items-center justify-between border-t border-border">
          <div className="flex gap-2">
            {etapeCourante > 0 && (
              <button
                onClick={precedent}
                className="text-sm text-muted-foreground hover:text-foreground transition-colors"
              >
                Précédent
              </button>
            )}
            {etapeCourante >= 3 && (
              <button
                onClick={fermer}
                className="text-sm text-muted-foreground hover:text-foreground transition-colors"
              >
                Passer
              </button>
            )}
          </div>
          <button
            onClick={suivant}
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-semibold text-primary-foreground bg-primary hover:bg-primary/90 transition-colors"
          >
            {isLast ? 'Commencer' : 'Suivant'}
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>

        {/* Step dots */}
        <div className="flex items-center justify-center gap-1.5 pb-5">
          {etapes.map((_, i) => (
            <button
              key={i}
              onClick={() => { setDirection(i > etapeCourante ? 'next' : 'prev'); setEtapeCourante(i); }}
              className={`h-1.5 rounded-full transition-all duration-300 ${
                i === etapeCourante
                  ? 'w-6 bg-primary'
                  : i < etapeCourante
                  ? 'w-1.5 bg-primary/50'
                  : 'w-1.5 bg-muted-foreground/20'
              }`}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
