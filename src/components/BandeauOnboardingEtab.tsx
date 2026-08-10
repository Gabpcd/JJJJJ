import { useEffect, useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { AlertTriangle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';

export function BandeauOnboardingEtab() {
  const { etablissementId, resolved, error: scopeError } = useEtablissementScope();
  const navigate = useNavigate();
  const location = useLocation();
  const [show, setShow] = useState(false);

  useEffect(() => {
    if (!resolved || scopeError || !etablissementId) {
      setShow(false);
      return;
    }
    if (location.pathname === '/etablissement/activer') return;
    (async () => {
      const { data, error } = await supabase
        .from('etablissements')
        .select('contrat_service_signe')
        .eq('id', etablissementId)
        .maybeSingle();
      if (error || !data) {
        setShow(false);
        return;
      }
      // Le RIB n'est plus exigé pour publier (demandé plus tard, au 1er paiement/prélèvement).
      // Seul le contrat de service signé est nécessaire ici.
      setShow(!(data as any).contrat_service_signe);
    })();
  }, [etablissementId, location.pathname, resolved, scopeError]);

  if (!show) return null;

  const detail = 'Signez le contrat de service pour publier des missions.';

  return (
    <div className="bg-warning/10 border-b border-warning/30 px-4 py-3 flex items-center justify-between gap-3">
      <div className="flex items-center gap-2 text-sm text-warning-foreground">
        <AlertTriangle className="h-4 w-4 text-warning shrink-0" />
        <span className="font-medium">Votre inscription n'est pas finalisée.</span>
        <span className="text-muted-foreground hidden sm:inline">{detail}</span>
      </div>
      <button
        onClick={() => navigate('/etablissement/activer')}
        className="shrink-0 text-sm font-semibold text-primary hover:text-primary/80 transition-colors"
      >
        Compléter maintenant
      </button>
    </div>
  );
}
