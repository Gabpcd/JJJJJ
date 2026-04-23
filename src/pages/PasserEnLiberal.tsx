import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { useParcoursLiberal } from '@/hooks/useParcoursLiberal';
import { estEligibleLiberal, getRegleInstallation } from '@/lib/regles-installation-liberal';
import { CategorieIDE } from '@/components/parcours-liberal/CategorieIDE';
import { CategorieKine } from '@/components/parcours-liberal/CategorieKine';

export default function PasserEnLiberal() {
  usePageTitle('Passer en libéral');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [profession, setProfession] = useState<string | null>(null);
  const [loadingProfession, setLoadingProfession] = useState(true);

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants').select('profession').eq('id', user.id).single()
      .then(({ data }) => {
        const prof = data?.profession || null;
        setProfession(prof);
        if (prof && !estEligibleLiberal(prof)) {
          navigate('/soignant/tableau-de-bord', { replace: true });
          return;
        }
        setLoadingProfession(false);
      });
  }, [user, navigate]);

  const {
    parcours,
    compteurHeures,
    heuresExternes,
    isLoading,
    error,
    majEtape,
    choisirParcoursKine,
    ajouterHeuresExternes,
    supprimerHeuresExternes,
  } = useParcoursLiberal();

  if (loadingProfession || isLoading) {
    return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;
  }

  if (error) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="card-base border-destructive/40 text-destructive">
          <p className="font-semibold">Erreur de chargement</p>
          <p className="text-sm mt-1">{error}</p>
        </div>
      </LayoutApp>
    );
  }

  if (!profession || !parcours) {
    return (
      <LayoutApp role="SOIGNANT">
        <div className="flex items-center justify-center py-12">
          <Loader2 className="h-6 w-6 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  const regle = getRegleInstallation(profession);
  if (!regle) return null;

  return (
    <LayoutApp role="SOIGNANT">
      {regle.categorie === 'AVEC_HEURES_IDE' && (
        <CategorieIDE
          parcours={parcours}
          compteurHeures={compteurHeures}
          heuresExternes={heuresExternes}
          regle={regle}
          majEtape={majEtape}
          ajouterHeuresExternes={ajouterHeuresExternes}
          supprimerHeuresExternes={supprimerHeuresExternes}
        />
      )}

      {regle.categorie === 'AVEC_HEURES_KINE' && (
        <CategorieKine
          parcours={parcours}
          compteurHeures={compteurHeures}
          heuresExternes={heuresExternes}
          regle={regle}
          majEtape={majEtape}
          choisirParcoursKine={choisirParcoursKine}
          ajouterHeuresExternes={ajouterHeuresExternes}
          supprimerHeuresExternes={supprimerHeuresExternes}
        />
      )}

      {(regle.categorie === 'AVEC_HEURES_IPA'
        || regle.categorie === 'SANS_HEURES_CPAM'
        || regle.categorie === 'SANS_HEURES_CIPAV') && (
        <div className="card-base text-center py-12">
          <h2 className="text-xl font-bold text-foreground mb-2">Votre parcours libéral</h2>
          <p className="text-sm text-muted-foreground max-w-md mx-auto">
            L'interface pour votre profession sera disponible très prochainement.
          </p>
          <p className="text-xs text-muted-foreground mt-3">
            En attendant, consultez vos démarches officielles :
          </p>
          {regle.lien_cpam && (
            <a
              href={regle.lien_cpam}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-block mt-3 text-sm text-primary hover:underline font-medium"
            >
              {regle.label_ordre || 'Démarches CPAM'} →
            </a>
          )}
        </div>
      )}
    </LayoutApp>
  );
}
