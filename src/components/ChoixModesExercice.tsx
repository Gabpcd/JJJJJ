import { modeExerciceSelectionne, modifierPreferenceModeExercice } from '@/lib/preferencesModesExercice';

interface Props {
  valeur: string[];
  onChange: (valeur: string[]) => void;
  typesAutorises: string[] | null;
  loading: boolean;
  indisponible: boolean;
  reessayer: () => void;
}

/** Préférences de recherche uniquement : ne modifie pas le statut d’exercice déclaré. */
export function ChoixModesExercice({ valeur, onChange, typesAutorises, loading, indisponible, reessayer }: Props) {
  const connus = Array.isArray(typesAutorises);
  const salarieAutorise = !connus || typesAutorises.some(type => type === 'SALARIE' || type === 'MIXTE');
  const liberalAutorise = !!typesAutorises?.some(type => type === 'LIBERAL' || type === 'MIXTE');
  const salarieSelectionne = modeExerciceSelectionne(valeur, 'SALARIE');
  const liberalSelectionne = modeExerciceSelectionne(valeur, 'LIBERAL');
  const modes = [
    { valeur: 'SALARIE' as const, label: 'Salarié (CDD compris)', autorise: salarieAutorise, selectionne: salarieSelectionne },
    { valeur: 'LIBERAL' as const, label: 'Libéral', autorise: liberalAutorise, selectionne: liberalSelectionne },
  ];

  return (
    <fieldset className="border-0 p-0 m-0">
      <legend className="text-sm font-medium text-foreground mb-1.5">Modes d’exercice recherchés</legend>
      <p className="text-xs text-muted-foreground mb-3">Le mode salarié inclut les CDD et les CDD courts. Vous pouvez sélectionner les deux modes si votre profession le permet.</p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
        {modes.filter(mode => mode.autorise || mode.selectionne).map(mode => (
          <label key={mode.valeur} className="flex min-h-11 items-center gap-3 cursor-pointer rounded-lg border border-input px-3 py-2.5 hover:bg-accent/50 transition-colors has-[:checked]:border-primary has-[:checked]:bg-primary/5">
            <input
              type="checkbox"
              checked={mode.selectionne}
              onChange={event => onChange(modifierPreferenceModeExercice(valeur, mode.valeur, event.target.checked))}
              className="h-4 w-4 shrink-0 rounded border-border accent-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
            />
            <span className="text-sm text-foreground">{mode.label}</span>
          </label>
        ))}
      </div>
      {loading && <p className="text-xs text-muted-foreground mt-2" role="status">Vérification des modes d’exercice autorisés…</p>}
      {indisponible && <div className="mt-2 space-y-1">
        <p className="text-xs text-muted-foreground" role="status">Vérification temporairement indisponible. Le mode salarié reste accessible. Vos choix sont conservés ; l’ajout du libéral nécessite une vérification.</p>
        <button type="button" onClick={reessayer} className="min-h-11 text-sm text-primary underline underline-offset-4">Réessayer la vérification</button>
      </div>}
      {connus && !liberalAutorise && <p className="text-xs text-muted-foreground mt-2">Le mode libéral n’est pas proposé pour votre profession sur Jolene. Le mode salarié comprend les CDD et les CDD courts.</p>}
      {connus && ((!liberalAutorise && liberalSelectionne) || (!salarieAutorise && salarieSelectionne)) && <p className="text-xs text-destructive mt-2">Une ancienne préférence n’est plus autorisée pour votre profession. Décochez-la pour actualiser vos choix.</p>}
      {!valeur.length && <p className="text-xs text-muted-foreground mt-2">Sélectionnez au moins un mode d’exercice.</p>}
    </fieldset>
  );
}
