interface IntroductionMissionProps {
  enPreparation: boolean;
  brouillon: Record<string, unknown> | null;
}

const texte = (valeur: unknown) => typeof valeur === 'string' ? valeur.trim() : '';

/** Le compte ou le marqueur de brouillon seuls ne constituent pas une mission saisie. */
export function IntroductionMission({ enPreparation, brouillon }: IntroductionMissionProps) {
  const formulaire = brouillon?.missionFormulaire as Record<string, unknown> | undefined;
  const details = [texte(formulaire?.intitule), texte(brouillon?.missionVille), texte(brouillon?.missionDate)].filter(Boolean);
  const contenuFormulaire = ['intitule', 'description', 'profession', 'service', 'tauxHoraire'].some(cle => texte(formulaire?.[cle]));
  const repris = Boolean(brouillon && (details.length || contenuFormulaire
    || texte(brouillon.missionProfession)
    || (Array.isArray(formulaire?.creneaux) && formulaire.creneaux.length > 0)));
  if (!enPreparation && !repris) return null;

  return (
    <div className="mb-4 rounded-xl bg-primary/5 px-3 py-2.5 text-sm" data-testid="introduction-mission">
      {repris && <p className="font-medium">Brouillon repris{details.length > 0 ? ` — ${details.join(' · ')}` : ''}</p>}
      <p className={repris ? 'mt-1 text-muted-foreground' : 'text-muted-foreground'}>
        {enPreparation
          ? 'Préparez votre mission. Votre dossier vous sera demandé pour la publier.'
          : 'Vérifiez les horaires et les conditions avant publication.'}
      </p>
    </div>
  );
}
