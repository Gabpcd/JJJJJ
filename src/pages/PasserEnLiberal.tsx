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
import { CategorieIPA } from '@/components/parcours-liberal/CategorieIPA';
import { CategorieSansHeuresCPAM } from '@/components/parcours-liberal/CategorieSansHeuresCPAM';
import { CategorieSansHeuresCIPAV } from '@/components/parcours-liberal/CategorieSansHeuresCIPAV';
import { FinaliserInstallationLiberal } from '@/components/parcours-liberal/FinaliserInstallationLiberal';

export default function PasserEnLiberal() {
  usePageTitle('Passer en libéral');
  const navigate = useNavigate();
  const { user } = useAuth();
  const [profession, setProfession] = useState<string | null>(null);
  const [loadingProfession, setLoadingProfession] = useState(true);

  useEffect(() => {
    if (!user) return;
    supabase.from('soignants').select('profession').eq('id', user.id).maybeSingle()
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

      {regle.categorie === 'AVEC_HEURES_IPA' && (
        <CategorieIPA
          parcours={parcours}
          regle={regle}
          majEtape={majEtape}
        />
      )}

      {regle.categorie === 'SANS_HEURES_CPAM' && (
        <CategorieSansHeuresCPAM
          parcours={parcours}
          regle={regle}
          majEtape={majEtape}
          soignantProfession={profession}
        />
      )}

      {regle.categorie === 'SANS_HEURES_CIPAV' && (
        <CategorieSansHeuresCIPAV
          parcours={parcours}
          regle={regle}
          majEtape={majEtape}
          soignantProfession={profession}
        />
      )}

      <div className="mt-4">
        <FinaliserInstallationLiberal />
      </div>
    </LayoutApp>
  );
}
