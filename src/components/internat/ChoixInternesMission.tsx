export function ChoixInternesMission({ checked, onChange, disabled, specialiteCode, error }: {
  checked: boolean; onChange: (value: boolean) => void; disabled?: boolean;
  specialiteCode: string; error: string | null;
}) {
  return <fieldset className="rounded-xl border border-border p-3 space-y-2" disabled={disabled}>
    <legend className="px-1 text-sm font-semibold">Accueil des internes en médecine</legend>
    <label className="flex min-h-11 cursor-pointer items-start gap-3 py-2">
      <input type="checkbox" className="mt-0.5 h-5 w-5 shrink-0" checked={checked}
        onChange={event => onChange(event.target.checked)} aria-describedby="internes-mission-description"
        data-testid="mission-accepte-internes" />
      <span className="text-sm">Accepter des internes dont la licence vérifiée autorise la spécialité de cette mission</span>
    </label>
    <p id="internes-mission-description" className="text-xs text-muted-foreground">
      {checked ? 'Seule la spécialité autorisée par une preuve valide sera acceptée. Une spécialité déclarée ou l’option « non spécialisé » ne remplace pas cette vérification.'
        : 'Les candidatures d’internes ne seront pas acceptées pour cette mission.'}
    </p>
    {checked && specialiteCode && <p className="text-xs text-foreground">L’accueil porte uniquement sur la spécialité sélectionnée ci-dessus.</p>}
    {error && <p role="alert" className="text-xs text-destructive">{error}</p>}
  </fieldset>;
}
