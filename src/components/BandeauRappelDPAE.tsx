import { AlertTriangle, ExternalLink, CheckCircle } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface BandeauRappelDPAEProps {
  contratId?: string;
  dpaeEffectuee?: boolean;
  dpaeEffectueeLe?: string | null;
  typeContrat?: string;
}

export function BandeauRappelDPAE({ dpaeEffectuee, dpaeEffectueeLe, typeContrat }: BandeauRappelDPAEProps) {
  // Afficher uniquement pour les contrats CDD (salarié)
  // Compat lecture : on accepte aussi 'CDDU' legacy au cas où des contrats
  // pré-migration PR 1 traînent encore.
  if (typeContrat !== 'CDD' && typeContrat !== 'CDDU') return null;

  if (dpaeEffectuee) {
    return (
      <div className="bg-success/10 border border-success/30 rounded-xl p-4 flex items-start gap-3">
        <CheckCircle className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-success">
            ✅ DPAE effectuée{dpaeEffectueeLe ? ` le ${format(new Date(dpaeEffectueeLe), 'd MMMM yyyy', { locale: fr })}` : ''}
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-warning/10 border border-warning/30 rounded-xl p-4 flex items-start gap-3">
      <AlertTriangle className="h-5 w-5 text-warning flex-shrink-0 mt-0.5" />
      <div className="flex-1">
        <p className="text-sm font-semibold text-warning">
          ⚠️ Rappel légal : effectuez la Déclaration Préalable à l'Embauche (DPAE) sur net-entreprises.fr avant le début de la mission.
        </p>
        <p className="text-xs text-muted-foreground mt-1">
          La DPAE est obligatoire pour les contrats CDD. Pour les remplacements libéraux, elle n'est pas requise.
        </p>
        <p className="text-xs text-muted-foreground mt-2">
          Une fois la DPAE soumise, saisissez le numéro URSSAF retourné dans la section <strong>DPAE</strong> ci-dessus pour preuve légale.
        </p>
        <div className="flex flex-wrap items-center gap-3 mt-2">
          <a
            href="https://www.net-entreprises.fr"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-xs text-primary hover:underline"
          >
            Accéder à net-entreprises.fr <ExternalLink className="h-3 w-3" />
          </a>
        </div>
      </div>
    </div>
  );
}
