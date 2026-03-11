import React from 'react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const LABELS_CONTROLE: Record<string, string> = {
  'REPOS_11H': 'Repos 11h',
  'PLAFOND_48H_HEBDO': 'Plafond 48h hebdomadaire',
  'MOYENNE_44H_12_SEMAINES': 'Moyenne 44h / 12 semaines',
  'PLAFOND_10H_JOUR': 'Durée max 10h/jour',
  'PLAFOND_RIST': 'Plafond Loi Rist',
  'LIMITE_TRAVAIL_NUIT': 'Limite travail de nuit',
  'VALIDITE_DOCUMENTS': 'Validité documents',
};

const ICONE_RESULTAT: Record<string, { icone: string; classe: string }> = {
  'CONFORME': { icone: '✅', classe: 'text-success' },
  'VIOLATION_BLOQUEE': { icone: '❌', classe: 'text-destructive' },
  'VIOLATION_ALERTEE': { icone: '⚠️', classe: 'text-warning' },
  'DEROGATION_AUTORISEE': { icone: '🔓', classe: 'text-info' },
};

interface CarteConformiteProps {
  controle: any;
}

export function CarteConformite({ controle }: CarteConformiteProps) {
  const c = controle;
  const config = ICONE_RESULTAT[c.resultat] || { icone: '❓', classe: 'text-muted-foreground' };

  return (
    <div className="flex items-start gap-3 py-2">
      <span className="text-base mt-0.5">{config.icone}</span>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-xs text-muted-foreground">
            {format(new Date(c.controle_le), "HH:mm", { locale: fr })}
          </span>
          <span className="text-xs font-semibold text-foreground">
            {LABELS_CONTROLE[c.type_controle] || c.type_controle}
          </span>
          <span className={`text-xs font-medium ${config.classe}`}>
            — {c.resultat.replace(/_/g, ' ')}
          </span>
        </div>
        {c.missions && (
          <p className="text-xs text-muted-foreground mt-0.5">
            Mission "{c.missions.intitule}" ({c.missions.etablissements?.nom})
          </p>
        )}
        {c.details_violation && c.resultat !== 'CONFORME' && (
          <p className="text-xs text-muted-foreground mt-0.5">
            {typeof c.details_violation === 'object'
              ? Object.entries(c.details_violation).map(([k, v]) => `${k}: ${v}`).join(' · ')
              : String(c.details_violation)}
          </p>
        )}
      </div>
    </div>
  );
}
