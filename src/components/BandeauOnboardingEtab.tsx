import { useEffect, useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

export function BandeauOnboardingEtab() {
  const { etablissementId, resolved, error: scopeError } = useEtablissementScope();
  const navigate = useNavigate();
  const location = useLocation();
  const [lecture, setLecture] = useState<{
    etablissementId: string;
    pathname: string;
    show: boolean;
  } | null>(null);

  useEffect(() => {
    setLecture(null);
    if (!resolved || scopeError || !etablissementId || location.pathname === '/etablissement/activer') return;

    let active = true;
    let suspendue = false;
    let generation = 0;
    let controller: AbortController | null = null;

    const interrompreLecture = () => {
      generation += 1;
      controller?.abort();
      controller = null;
      window.removeEventListener('beforeunload', quitterDocument);
    };
    const quitterDocument = () => {
      suspendue = true;
      interrompreLecture();
    };
    const charger = async () => {
      interrompreLecture();
      const generationCourante = generation;
      const controleurCourant = new AbortController();
      controller = controleurCourant;
      const lectureActive = () => active && !suspendue
        && generation === generationCourante && !controleurCourant.signal.aborted;
      // WebKit peut rejeter les fetch avant pagehide. Ne garder ce listener
      // que pendant la requête, sans prompt ni prévention du départ.
      window.addEventListener('beforeunload', quitterDocument);
      try {
        const { data, error } = await supabase
          .from('etablissements')
          .select('contrat_service_signe')
          .eq('id', etablissementId)
          .abortSignal(controleurCourant.signal)
          .maybeSingle();
        if (!lectureActive()) return;
        // Le RIB n'est plus exigé pour publier (demandé plus tard, au 1er paiement/prélèvement).
        // Seul le contrat de service signé est nécessaire ici.
        setLecture({ etablissementId, pathname: location.pathname, show: !error && !!data && !data.contrat_service_signe });
      } catch {
        if (lectureActive()) setLecture(null);
      } finally {
        if (controller === controleurCourant) {
          controller = null;
          window.removeEventListener('beforeunload', quitterDocument);
        }
      }
    };
    const reprendreLecture = () => {
      if (!active || !suspendue || document.visibilityState === 'hidden') return;
      suspendue = false;
      void charger();
    };
    const restaurerDocument = (event: PageTransitionEvent) => {
      if (event.persisted) suspendue = true;
      reprendreLecture();
    };
    window.addEventListener('pagehide', quitterDocument);
    window.addEventListener('pageshow', restaurerDocument);
    // Reprise d'un départ interrompu sans temporisation pendant la navigation.
    window.addEventListener('focus', reprendreLecture);
    window.addEventListener('pointerdown', reprendreLecture);
    window.addEventListener('keydown', reprendreLecture);
    void charger();
    return () => {
      active = false;
      interrompreLecture();
      window.removeEventListener('pagehide', quitterDocument);
      window.removeEventListener('pageshow', restaurerDocument);
      window.removeEventListener('focus', reprendreLecture);
      window.removeEventListener('pointerdown', reprendreLecture);
      window.removeEventListener('keydown', reprendreLecture);
    };
  }, [etablissementId, location.pathname, resolved, scopeError]);

  if (!resolved || scopeError || location.pathname === '/etablissement/activer'
    || lecture?.etablissementId !== etablissementId || lecture?.pathname !== location.pathname || !lecture?.show) return null;

  const detail = 'Signez le contrat de service pour publier des missions.';

  return (
    <div
      data-testid="onboarding-etab-banner"
      className="bg-warning/10 border-b border-warning/30 px-4 py-3 flex items-center justify-between gap-3"
    >
      <div className="flex items-center gap-2 text-sm text-amber-800 dark:text-warning">
        <AlertTriangle className="h-4 w-4 shrink-0" />
        <span className="font-medium">Votre inscription n'est pas finalisée.</span>
        <span className="text-muted-foreground hidden sm:inline">{detail}</span>
      </div>
      <button
        onClick={() => navigate('/etablissement/activer')}
        className="shrink-0 text-sm font-semibold text-primary-dark hover:text-primary-dark/80 transition-colors"
      >
        Compléter maintenant
      </button>
    </div>
  );
}
