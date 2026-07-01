import { useNavigate } from 'react-router-dom';
import { AlertCircle, CheckCircle2, Circle, Sparkles, ArrowRight } from 'lucide-react';
import { calculerCompletionProfil, type ItemCompletion } from '@/lib/profil-soignant';
import type { Database } from '@/integrations/supabase/types';

type Soignant = Database['public']['Tables']['soignants']['Row'];

interface Props {
  soignant: Soignant | null;
  variant?: 'compact' | 'detaille';
  masquerSiComplet?: boolean;
  className?: string;
}

function getCouleurs(pourcentage: number, peutCandidater: boolean): { bg: string; border: string; text: string; barre: string; icone: string } {
  // Ton encourageant, jamais punitif (orienté conversion) : pas de rouge « échec »
  // sur un profil en cours. Dès que le soignant peut candidater → positif (vert).
  // Sinon → couleur de marque (primary) : un nudge vers l'étape suivante, pas une alarme.
  if (pourcentage >= 100 || peutCandidater) {
    return { bg: 'bg-success/5', border: 'border-success/30', text: 'text-success', barre: 'bg-success', icone: 'text-success' };
  }
  return { bg: 'bg-primary/5', border: 'border-primary/30', text: 'text-primary', barre: 'bg-primary', icone: 'text-primary' };
}

export function BandeauCompletionProfil({ soignant, variant = 'detaille', masquerSiComplet = true, className = '' }: Props) {
  const navigate = useNavigate();

  if (!soignant) {
    return (
      <div className="rounded-2xl bg-primary/5 border border-primary/30 p-4 mb-4 flex items-start gap-3">
        <Sparkles className="h-5 w-5 text-primary shrink-0 mt-0.5" />
        <div className="flex-1">
          <p className="text-sm font-semibold text-foreground">Bienvenue sur Jolene</p>
          <p className="text-xs text-muted-foreground mt-1">
            Finalise ton inscription pour accéder à toutes les fonctionnalités et candidater aux missions.
          </p>
          <button
            onClick={() => navigate('/soignant/profil')}
            className="btn-primary text-xs mt-3 inline-flex items-center gap-1.5"
          >
            Finaliser mon inscription <ArrowRight className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>
    );
  }

  const resume = calculerCompletionProfil(soignant);

  if (resume.est_complet && masquerSiComplet) return null;

  const couleurs = getCouleurs(resume.pourcentage, resume.peut_candidater);

  if (variant === 'compact') {
    return (
      <div className={`rounded-xl ${couleurs.bg} border ${couleurs.border} p-3 flex items-center justify-between gap-3 ${className}`}>
        <div className="flex items-center gap-2 min-w-0">
          <AlertCircle className={`h-4 w-4 ${couleurs.icone} shrink-0`} />
          <p className={`text-sm font-medium ${couleurs.text} truncate`}>
            Profil {resume.pourcentage}%
            {resume.items_obligatoires_manquants.length > 0 && (
              <span className="text-muted-foreground font-normal">
                {' '}· À compléter : {resume.items_obligatoires_manquants.map((i) => i.label).join(', ')}
              </span>
            )}
          </p>
        </div>
        <button
          onClick={() => navigate('/soignant/profil')}
          className="text-xs font-medium text-primary hover:underline shrink-0 inline-flex items-center gap-1"
        >
          Compléter <ArrowRight className="h-3 w-3" />
        </button>
      </div>
    );
  }

  return (
    <div className={`rounded-2xl ${couleurs.bg} border ${couleurs.border} p-4 md:p-5 mb-6`}>
      <div className="flex items-center justify-between mb-3 gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <AlertCircle className={`h-4 w-4 ${couleurs.icone} shrink-0`} />
          <h2 className={`text-sm font-semibold ${couleurs.text}`}>
            Profil complété à {resume.pourcentage}%
          </h2>
        </div>
        <span className="text-xs text-muted-foreground shrink-0">
          {resume.items_remplis}/{resume.total_items}
        </span>
      </div>
      <div className="h-2 bg-muted rounded-full overflow-hidden mb-3">
        <div
          className={`h-full ${couleurs.barre} transition-all`}
          style={{ width: `${resume.pourcentage}%` }}
        />
      </div>
      {/* Requis pour candidater (bloquant) — nommé explicitement */}
      {resume.items_obligatoires_manquants.length > 0 ? (
        <p className={`text-xs mb-2 ${couleurs.text} font-medium`}>
          Requis pour candidater : {resume.items_obligatoires_manquants.map((i) => i.label).join(', ')}.
        </p>
      ) : (
        <p className="text-xs mb-2 text-success font-medium">
          ✅ Informations requises complétées — tu peux candidater.
        </p>
      )}
      {/* Recommandé (non bloquant) — améliore la visibilité / accès */}
      {resume.items_recommandes_manquants.length > 0 && (
        <p className="text-xs mb-3 text-muted-foreground">
          Recommandé (améliore ta visibilité) : {resume.items_recommandes_manquants.map((i) => i.label).join(', ')}.
        </p>
      )}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-1.5 mb-3">
        {resume.items.map((item: ItemCompletion) => (
          <div key={item.cle} className="flex items-center gap-1.5 text-xs">
            {item.rempli ? (
              <CheckCircle2 className="h-3.5 w-3.5 text-success shrink-0" />
            ) : (
              <Circle className={`h-3.5 w-3.5 shrink-0 ${item.obligatoire ? 'text-primary' : 'text-muted-foreground'}`} />
            )}
            <span className={item.rempli ? 'text-muted-foreground' : (item.obligatoire ? 'text-foreground font-medium' : 'text-muted-foreground')}>
              {item.label}
              {!item.rempli && item.obligatoire && <span className="text-primary ml-1">*</span>}
            </span>
          </div>
        ))}
      </div>
      <button
        onClick={() => navigate('/soignant/profil')}
        className="btn-primary text-xs inline-flex items-center gap-1.5"
      >
        Compléter mon profil <ArrowRight className="h-3.5 w-3.5" />
      </button>
    </div>
  );
}
