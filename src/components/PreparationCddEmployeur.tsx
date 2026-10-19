import { useState, type FormEvent } from 'react';
import { validerDonneesCdd, type DonneesCdd } from '../../supabase/functions/_shared/cdd-employeur';

type Props = { enCours: boolean; erreur: string | null; onPreparer: (donnees: DonneesCdd) => Promise<void> };

export function PreparationCddEmployeur({ enCours, erreur, onPreparer }: Props) {
  const [valeurs, setValeurs] = useState<Record<string, string>>({});
  const [confirme, setConfirme] = useState(false);
  const [erreurLocale, setErreurLocale] = useState<string | null>(null);
  const changer = (champ: string, value: string) => {
    setValeurs(v => ({ ...v, [champ]: value }));
    setConfirme(false);
    setErreurLocale(null);
  };
  const texte = (champ: string, label: string, aide?: string) => (
    <label className="block space-y-1" key={champ}>
      <span className="text-sm font-medium">{label}</span>
      <textarea className="w-full rounded-md border border-border bg-background p-2 text-base md:text-sm"
        required rows={champ === 'texte_employeur' ? 12 : 2} maxLength={champ === 'texte_employeur' ? 60000 : 4000}
        value={valeurs[champ] || ''} onChange={e => changer(champ, e.target.value)} />
      {aide && <span className="block text-xs text-muted-foreground">{aide}</span>}
    </label>
  );
  const choix = (champ: string, label: string, options: readonly (readonly [string, string])[]) => (
    <label className="block space-y-1" key={champ}>
      <span className="text-sm font-medium">{label}</span>
      <select className="w-full rounded-md border border-border bg-background p-2 text-base md:text-sm"
        required value={valeurs[champ] || ''} onChange={e => changer(champ, e.target.value)}>
        <option value="">Choisir explicitement</option>
        {options.map(([value, titre]) => <option key={value} value={value}>{titre}</option>)}
      </select>
    </label>
  );
  const ouiNon = [['OUI', 'Oui'], ['NON', 'Non']] as const;
  const soumettre = async (event: FormEvent) => {
    event.preventDefault();
    const resultat = validerDonneesCdd({ ...valeurs, confirme });
    if (!resultat.donnees) {
      setErreurLocale('Complétez les informations et confirmez-les avant de préparer le document.');
      return;
    }
    await onPreparer(resultat.donnees);
  };

  return <form onSubmit={soumettre} className="card-base mb-4 space-y-4" aria-labelledby="preparation-cdd-titre">
    <h2 id="preparation-cdd-titre" className="font-bold">Préparer le contrat salarié</h2>
    <p className="text-sm text-muted-foreground">Renseignez les conditions exactes de l’employeur. Elles seront figées dans le document présenté aux deux parties avant signature. Aucun essai ni motif ne sera ajouté par défaut.</p>
    <fieldset disabled={enCours} className="space-y-4">
      <legend className="sr-only">Informations contractuelles de l’employeur</legend>
      {choix('cadre', 'Document à préparer', [
        ['PRIVE_TERME_PRECIS', 'CDD de droit privé à terme précis'],
        ['TEXTE_EMPLOYEUR', 'Texte complet de l’employeur : droit public ou autre cadre'],
      ])}
      {texte('representant_nom', 'Nom du représentant de l’employeur')}
      {texte('representant_qualite', 'Qualité du représentant de l’employeur')}
      {valeurs.cadre === 'TEXTE_EMPLOYEUR' && <>
        {texte('cadre_declare', 'Cadre juridique déclaré par l’employeur', 'Précisez le régime et le fondement applicables à cet engagement ; ils ne sont pas déduits de la profession ou de l’établissement.')}
        {texte('texte_employeur', 'Texte intégral du contrat fourni par l’employeur', 'Incluez les parties, le motif et les mentions propres à cet engagement, les dates ou la durée minimale et le terme, le poste, le temps de travail et la rémunération. Aucune clause du modèle privé Jolene ne sera ajoutée. Vérifiez la concordance avec la mission.')}
      </>}
      {valeurs.cadre === 'PRIVE_TERME_PRECIS' && <>
        {choix('motif_type', 'Cas de recours déclaré', [['REMPLACEMENT', 'Remplacement'], ['ACCROISSEMENT', 'Accroissement temporaire d’activité'], ['AUTRE', 'Autre cas précis confirmé par l’employeur']])}
        {texte('motif_precis', 'Motif précis du CDD', 'Décrivez les faits correspondant au cas de recours, sans information médicale sur la personne remplacée.')}
        {valeurs.motif_type === 'REMPLACEMENT' && <>
          {texte('remplace_nom', 'Prénom et nom de la personne remplacée')}
          {texte('remplace_qualification', 'Qualification professionnelle de la personne remplacée')}
        </>}
        {texte('poste', 'Poste de travail')}
        {texte('qualification', 'Qualification du salarié pour ce poste')}
        {texte('lieu_travail', 'Lieu de travail et adresse')}
        {choix('risques', 'Poste présentant des risques particuliers', ouiNon)}
        {valeurs.risques === 'OUI' && texte('risques_precisions', 'Risques particuliers du poste')}
        {texte('renouvellement', 'Renouvellement éventuel', 'Indiquez les conditions convenues ou explicitement qu’aucun renouvellement n’est prévu.')}
        {choix('temps_partiel', 'Engagement à temps partiel', ouiNon)}
        {valeurs.temps_partiel === 'OUI' && texte('temps_partiel_conditions', 'Conditions du temps partiel', 'Précisez la durée hebdomadaire ou mensuelle, sa répartition, les cas et modalités de modification, la communication des horaires et les limites des heures complémentaires applicables.')}
        {texte('convention_collective', 'Intitulé exact de la convention collective applicable', 'Ajoutez sa référence IDCC si disponible, ou confirmez explicitement son absence d’application pour ce contrat.')}
        {choix('essai', 'Période d’essai expressément convenue', [['AUCUN', 'Aucune période d’essai'], ['CONVENU', 'Une période d’essai est convenue']])}
        {valeurs.essai === 'CONVENU' && <>
          {texte('essai_duree', 'Durée exacte de l’essai et unité')}
          {texte('essai_conditions', 'Conditions et référence applicables à l’essai', 'Confirmez la durée applicable à cet engagement et les dispositions conventionnelles éventuelles. Aucune durée n’est calculée automatiquement.')}
        </>}
        {texte('remuneration_accessoires', 'Rémunération, primes, indemnités et accessoires', 'Détaillez le salaire et toutes ses composantes applicables, y compris les primes et indemnités, en cohérence avec le taux et les montants de la mission. N’indiquez « aucun » que pour une composante réellement absente.')}
        {texte('retraite_nom', 'Nom de la caisse de retraite complémentaire')}
        {texte('retraite_adresse', 'Adresse de la caisse de retraite complémentaire')}
        {choix('prevoyance', 'Prévoyance applicable à cet engagement', ouiNon)}
        {valeurs.prevoyance === 'OUI' && <>
          {texte('prevoyance_nom', 'Nom de l’organisme de prévoyance')}
          {texte('prevoyance_adresse', 'Adresse de l’organisme de prévoyance')}
        </>}
      </>}
      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" required checked={confirme} onChange={e => setConfirme(e.target.checked)} />
        <span>Je confirme pour l’employeur l’exactitude et la complétude des conditions de ce contrat, leur concordance avec la mission et le cadre applicable. Le document sera figé avant les signatures.</span>
      </label>
      {(erreurLocale || erreur) && <p role="alert" className="text-sm text-destructive">{erreurLocale || erreur}</p>}
      <button type="submit" className="btn-primary w-full" disabled={!confirme || enCours}>
        {enCours ? 'Préparation du document…' : 'Confirmer ces informations et préparer le document'}
      </button>
      <p className="text-xs text-muted-foreground">La saisie reste dans cette page jusqu’à la préparation. Vérifiez le document obtenu avant de le signer.</p>
    </fieldset>
  </form>;
}
