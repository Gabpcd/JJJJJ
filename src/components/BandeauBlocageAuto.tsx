import { useState } from 'react';
import { Ban, AlertCircle, RefreshCw } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface Raisons {
  paiements_retard_nb?: number;
  paiements_retard_montant?: number;
  factures_retard_nb?: number;
  factures_retard_montant?: number;
  seuil_jours?: number;
}

interface Props {
  raisons: Raisons | null | undefined;
  bloque_le: string;
}

export function BandeauBlocageAuto({ raisons, bloque_le }: Props) {
  const navigate = useNavigate();
  const [verification, setVerification] = useState(false);

  const reverifier = async () => {
    setVerification(true);
    try {
      const { data, error } = await supabase.rpc('fn_reverifier_blocage_etab' as any);
      if (error) { toast.error(error.message); return; }
      if ((data as any)?.debloque) {
        toast.success('Compte réactivé ! Vous pouvez à nouveau publier des missions.');
        window.location.reload();
      } else {
        toast.info((data as any)?.message || 'Des obligations restent en retard.');
      }
    } finally {
      setVerification(false);
    }
  };

  const paiementsNb = raisons?.paiements_retard_nb ?? 0;
  const paiementsMontant = raisons?.paiements_retard_montant ?? 0;
  const facturesNb = raisons?.factures_retard_nb ?? 0;
  const facturesMontant = raisons?.factures_retard_montant ?? 0;
  const total = paiementsMontant + facturesMontant;

  const dateBlocage = bloque_le
    ? format(new Date(bloque_le), "d MMMM yyyy", { locale: fr })
    : '';

  const eur = (v: number) =>
    new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);

  return (
    <div className="rounded-xl border-2 border-destructive bg-destructive/5 p-4 mb-4">
      <div className="flex items-start gap-3">
        <Ban className="h-6 w-6 text-destructive flex-shrink-0 mt-0.5" aria-hidden="true" />
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-destructive text-base">
            Publication de missions suspendue
          </h3>
          {dateBlocage && (
            <p className="text-xs text-muted-foreground mt-0.5">
              Depuis le {dateBlocage}
            </p>
          )}

          <div className="mt-3 space-y-1.5 text-sm">
            {paiementsNb > 0 && (
              <div className="flex items-start gap-2">
                <AlertCircle className="h-4 w-4 text-destructive shrink-0 mt-0.5" aria-hidden="true" />
                <p className="text-foreground">
                  <strong>{paiementsNb}</strong> paiement(s) soignant(s) en retard — <strong>{eur(paiementsMontant)}</strong>
                </p>
              </div>
            )}
            {facturesNb > 0 && (
              <div className="flex items-start gap-2">
                <AlertCircle className="h-4 w-4 text-destructive shrink-0 mt-0.5" aria-hidden="true" />
                <p className="text-foreground">
                  <strong>{facturesNb}</strong> facture(s) commission impayée(s) — <strong>{eur(facturesMontant)}</strong>
                </p>
              </div>
            )}
            {total > 0 && (
              <p className="text-sm font-semibold text-foreground pt-1">
                Total dû : {eur(total)}
              </p>
            )}
          </div>

          <p className="text-xs text-muted-foreground mt-3">
            Une fois vos obligations régularisées, cliquez sur « J'ai régularisé » pour réactiver
            votre compte immédiatement (sinon réactivation automatique sous 1 h).
          </p>

          <div className="flex flex-col sm:flex-row gap-2 mt-4">
            {paiementsNb > 0 && (
              <button
                onClick={() => navigate('/etablissement/facturation')}
                className="btn-primary text-sm flex-1"
              >
                Déclarer paiements soignants
              </button>
            )}
            {facturesNb > 0 && (
              <button
                onClick={() => navigate('/etablissement/facturation')}
                className="btn-secondary text-sm flex-1"
              >
                Payer factures commission
              </button>
            )}
            <button
              onClick={reverifier}
              disabled={verification}
              className="btn-secondary text-sm flex-1 inline-flex items-center justify-center gap-2 disabled:opacity-50"
            >
              <RefreshCw className={`h-4 w-4 ${verification ? 'animate-spin' : ''}`} />
              {verification ? 'Vérification…' : 'J\'ai régularisé — réactiver'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
