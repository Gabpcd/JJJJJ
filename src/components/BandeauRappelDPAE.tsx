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
  // Le modèle historique utilise tantôt CDD, tantôt SALARIE pour le même
  // parcours employeur. Les deux doivent donc déclencher le rappel DPAE.
  if (!typeContrat || !['CDD', 'SALARIE'].includes(typeContrat)) return null;

  if (dpaeEffectuee) {
    return (
      <div className="bg-success/10 border border-success/30 rounded-xl p-4 flex items-start gap-3">
        <CheckCircle className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-success">
            ✅ DPAE déclarée comme effectuée par l'établissement{dpaeEffectueeLe ? ` le ${format(new Date(dpaeEffectueeLe), 'd MMMM yyyy', { locale: fr })}` : ''}
          </p>
          <p className="text-xs text-muted-foreground mt-1">
            Jolene conserve ce suivi interne ; la preuve opposable reste l'accusé transmis par l'Urssaf.
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
          La DPAE est obligatoire pour ce contrat salarié. Pour une mission libérale directe, elle n'est pas requise.
        </p>
        <p className="text-xs text-muted-foreground mt-2">
          Une fois la DPAE transmise, saisissez le numéro URSSAF retourné dans la section <strong>DPAE</strong> du contrat afin d'en conserver la traçabilité interne.
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
