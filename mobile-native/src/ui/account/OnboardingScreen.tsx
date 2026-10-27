import { useEffect, useState } from 'react';
import { Linking, Text, View } from 'react-native';
import { PROFESSIONS, PROFESSIONS_RPPS_REQUIS, PROFESSIONS_SANS_RPPS, TYPES_ETABLISSEMENT } from '../../../../src/lib/constantes';
import { modeExerciceSelectionne, modifierPreferenceModeExercice } from '../../../../src/lib/preferencesModesExercice';
import type { NativeAccountGateway, NativeAccountType, NativeOnboardingContext, NativeRegistrationForm } from '../../account/types';
import { restoreRegistrationForm, studentFormations } from '../../account/registration';
import { ActionButton } from '../components';
import { shared } from '../theme';
import { AccountCheck, AccountChoice, AccountField, AccountLayout, useAccountAction } from './components';

export function OnboardingScreen({ gateway, context, onComplete, onSignOut, onRefresh }: {
  gateway: NativeAccountGateway; context: NativeOnboardingContext;
  onComplete: () => void; onSignOut: () => void; onRefresh?: () => void;
}) {
  const initialValues = () => context.parcours?.donnees ?? { profession: context.suggestedRegistration?.profession ?? '', nom: context.suggestedRegistration?.nom ?? '' };
  const [form, setForm] = useState(() => restoreRegistrationForm(initialValues()));
  const [type, setType] = useState<NativeAccountType>(context.parcours?.type_compte ?? context.suggestedRegistration?.type ?? 'SOIGNANT');
  const [cgu, setCgu] = useState(false);
  const [cgv, setCgv] = useState(false);
  const [saved, setSaved] = useState(false);
  const [retry, setRetry] = useState(0);
  const [exercise, setExercise] = useState<{ profession: string; values: string[] | null; unavailable: boolean } | null>(null);
  const [student, setStudent] = useState<{ key: string; values: string[] | null } | null>(null);
  const action = useAccountAction();
  const kind = context.parcours?.type_compte ?? type;
  const update = <K extends keyof NativeRegistrationForm>(key: K, value: NativeRegistrationForm[K]) => {
    setSaved(false);
    setForm(current => {
      const next = { ...current, [key]: value };
      if (key === 'profession') {
        next.typesContrat = next.typesContrat.filter(v => v !== 'LIBERAL');
        if (!studentFormations(next.profession).some(f => f.valeur === next.scolariteFormation)) { next.scolariteFormation = ''; next.scolariteAnnee = ''; }
        if (PROFESSIONS_SANS_RPPS.includes(next.profession) && next.profession !== 'AS') next.rpps = '';
      }
      if (key === 'scolariteFormation') next.scolariteAnnee = '';
      return next;
    });
  };
  useEffect(() => {
    setForm(restoreRegistrationForm(initialValues()));
    setType(context.parcours?.type_compte ?? context.suggestedRegistration?.type ?? 'SOIGNANT');
    setSaved(false); setCgu(false); setCgv(false);
    // Same-user refreshes must not overwrite text currently being edited.
  }, [context.userId]);
  useEffect(() => {
    if (kind !== 'SOIGNANT' || !form.profession) return;
    const abort = new AbortController();
    const profession = form.profession;
    setExercise(null);
    void gateway.getExerciseTypes(profession, abort.signal).then(values => {
      if (!abort.signal.aborted) setExercise({ profession, values, unavailable: false });
    }, () => { if (!abort.signal.aborted) setExercise({ profession, values: null, unavailable: true }); });
    return () => abort.abort();
  }, [gateway, kind, form.profession, retry]);
  const studentKey = form.estEtudiant && form.scolariteFormation && form.scolariteFormation !== 'MEDECINE_DES' && /^[1-9]$/.test(form.scolariteAnnee)
    ? `${form.scolariteFormation}:${form.scolariteAnnee}` : '';
  useEffect(() => {
    if (!studentKey) return;
    const abort = new AbortController();
    void gateway.getStudentProfessions(form.scolariteFormation, Number(form.scolariteAnnee), abort.signal).then(values => {
      if (!abort.signal.aborted) setStudent({ key: studentKey, values });
    }, () => { if (!abort.signal.aborted) setStudent({ key: studentKey, values: null }); });
    return () => abort.abort();
  }, [gateway, studentKey, form.scolariteFormation, form.scolariteAnnee]);
  const types = exercise?.profession === form.profession ? exercise.values : null;
  const salarie = !types || types.some(v => v === 'SALARIE' || v === 'MIXTE');
  const liberal = !!types?.some(v => v === 'LIBERAL' || v === 'MIXTE');
  const studentResult = student?.key === studentKey ? student : null;
  const field = (key: keyof NativeRegistrationForm, label: string, keyboardType: 'default' | 'phone-pad' | 'number-pad' | 'email-address' = 'default', placeholder?: string) =>
    <AccountField key={key} label={label} value={String(form[key])} onChangeText={value => update(key, value)} editable={!action.busy} keyboardType={keyboardType}
      autoCapitalize={keyboardType === 'email-address' ? 'none' : 'sentences'} placeholder={placeholder} testID={`onboarding-${key}`} />;

  if (!context.emailConfirmed) return <AccountLayout title="Confirmez votre email" mode={gateway.mode}>
    <Text style={shared.body}>Ouvrez le lien envoyé à {context.email ?? 'votre adresse email'}, puis revenez ici. Votre compte ne donne pas encore accès à un espace professionnel.</Text>
    {onRefresh ? <ActionButton label="Vérifier la confirmation" onPress={onRefresh} testID="onboarding-refresh-email" /> : null}
    <ActionButton label="Se déconnecter" secondary onPress={onSignOut} />
  </AccountLayout>;

  return <AccountLayout title={context.parcours ? 'Compléter mon profil' : 'Reprendre mon inscription'} mode={gateway.mode}>
    <Text style={shared.small}>{context.email}</Text>
    {!context.parcours ? <>
      <AccountChoice label="Votre espace" value={type} choices={[{ valeur: 'SOIGNANT', label: 'Soignant' }, { valeur: 'ETABLISSEMENT', label: 'Établissement' }]}
        onChange={v => setType(v as NativeAccountType)} disabled={action.busy} testID="onboarding-type" />
      {type === 'SOIGNANT' ? <AccountChoice label="Profession" value={form.profession} choices={PROFESSIONS} onChange={v => update('profession', v)} disabled={action.busy} testID="onboarding-profession" /> : field('nom', 'Nom de l’établissement')}
      <AccountCheck label="J’accepte les conditions générales d’utilisation et la politique de confidentialité" checked={cgu} onChange={setCgu} disabled={action.busy} testID="onboarding-cgu" />
      <ActionButton label="Lire les conditions d’utilisation" secondary onPress={() => { void action.run(async () => { await Linking.openURL('https://jolene.app/cgu'); }); }} />
      <ActionButton label="Lire la politique de confidentialité" secondary onPress={() => { void action.run(async () => { await Linking.openURL('https://jolene.app/confidentialite'); }); }} />
      {type === 'ETABLISSEMENT' ? <><AccountCheck label="J’accepte les conditions générales de vente" checked={cgv} onChange={setCgv} disabled={action.busy} testID="onboarding-cgv" />
        <ActionButton label="Lire les conditions de vente" secondary onPress={() => { void action.run(async () => { await Linking.openURL('https://jolene.app/cgv'); }); }} /></> : null}
      {action.Error}
      <ActionButton label="Continuer mon inscription" busy={action.busy} testID="onboarding-start" onPress={() => { void action.run(async () => {
        await gateway.startRegistration(context.userId, { type, profession: form.profession, nom: form.nom, cgu, cgv });
        if (action.mounted.current) onRefresh?.();
      }); }} />
    </> : <>
      {kind === 'SOIGNANT' ? <>
        {field('prenom', 'Prénom')}{field('nom', 'Nom')}{field('telephone', 'Téléphone', 'phone-pad')}
        {field('dateNaissance', 'Date de naissance · AAAA-MM-JJ', 'default', '1997-05-12')}
        <AccountChoice label="Profession" value={form.profession} choices={PROFESSIONS} onChange={v => update('profession', v)} disabled={action.busy} testID="onboarding-profession" />
        <AccountCheck label="Je suis étudiant en santé" checked={form.estEtudiant} onChange={v => update('estEtudiant', v)} disabled={action.busy} testID="onboarding-student" />
        {form.estEtudiant ? <View style={{ gap: 14 }}>
          <AccountChoice label={form.profession === 'MEDECIN' ? 'Cycle d’études en médecine' : 'Formation'} value={form.scolariteFormation} choices={studentFormations(form.profession)}
            onChange={v => update('scolariteFormation', v)} disabled={action.busy} testID="onboarding-formation" />
          {form.scolariteFormation === 'MEDECINE_DES' ? <Text style={shared.body} testID="onboarding-internat-notice">Interne ou docteur junior : votre cycle d’études sera enregistré dans votre profil. Votre droit au remplacement n’est pas validé à cette étape.</Text> : <>
            <AccountField label="Dernière année validée" value={form.scolariteAnnee} onChangeText={v => update('scolariteAnnee', v.replace(/\D/g, '').slice(0, 1))} keyboardType="number-pad" editable={!action.busy} testID="onboarding-study-year" />
            <Text style={shared.small}>Admis(e) en 2e année : indiquez 1. Une attestation détaillée et une revue humaine restent nécessaires avant toute candidature.</Text>
            {studentKey ? <Text style={shared.small}>{!studentResult ? 'Vérification des possibilités d’emploi temporaire…' : studentResult.values === null
              ? 'Vérification indisponible : votre niveau reste enregistré, aucune équivalence n’est confirmée.'
              : studentResult.values.includes('AS') ? 'Pré-éligibilité aide-soignant détectée, sous réserve des preuves et de leur revue. Votre profession ne change pas automatiquement.'
              : 'Aucune pré-éligibilité aide-soignant n’est confirmée pour ce niveau.'}</Text> : null}
            {studentResult?.values?.includes('AS') && form.profession !== 'AS' ? <ActionButton label="Choisir le profil aide-soignant" secondary disabled={action.busy} onPress={() => update('profession', 'AS')} /> : null}
          </>}
        </View> : null}
        <Text style={shared.sectionTitle}>Modes d’exercice recherchés</Text>
        <Text style={shared.small}>Le mode salarié inclut les CDD et les CDD courts.</Text>
        {(['SALARIE', 'LIBERAL'] as const).filter(mode => (mode === 'SALARIE' ? salarie : liberal) || modeExerciceSelectionne(form.typesContrat, mode)).map(mode =>
          <AccountCheck key={mode} label={mode === 'SALARIE' ? 'Salarié (CDD compris)' : 'Libéral'} checked={modeExerciceSelectionne(form.typesContrat, mode)}
            disabled={action.busy || (!modeExerciceSelectionne(form.typesContrat, mode) && !(mode === 'SALARIE' ? salarie : liberal))}
            onChange={v => update('typesContrat', modifierPreferenceModeExercice(form.typesContrat, mode, v))} testID={`onboarding-mode-${mode}`} />)}
        {exercise?.unavailable ? <><Text style={shared.small}>Vérification temporairement indisponible. L’ajout du libéral nécessite une vérification ; vos choix sont conservés.</Text>
          <ActionButton label="Réessayer les modes d’exercice" secondary onPress={() => setRetry(v => v + 1)} /></> : !types ? <Text style={shared.small}>Vérification des modes d’exercice…</Text> : null}
        {(!PROFESSIONS_SANS_RPPS.includes(form.profession) || form.profession === 'AS') && form.profession ? <>
          <AccountField label={`Numéro RPPS${PROFESSIONS_RPPS_REQUIS.includes(form.profession) ? ' · obligatoire' : ' · optionnel'}`} value={form.rpps}
            onChangeText={v => update('rpps', v.replace(/\D/g, '').slice(0, 11))} keyboardType="number-pad" editable={!action.busy} testID="onboarding-rpps" />
          <Text style={shared.small}>Le serveur vérifiera l’identité et la profession associées au RPPS lors de la finalisation. Une déclaration ou un numéro saisi ne constitue pas une validation.</Text>
        </> : null}
      </> : <>
        {field('nom', 'Nom de l’établissement')}{field('siret', 'SIRET · 14 chiffres', 'number-pad')}
        <AccountChoice label="Type d’établissement" value={form.type} choices={TYPES_ETABLISSEMENT} onChange={v => update('type', v)} disabled={action.busy} testID="onboarding-establishment-type" />
        {field('ville', 'Ville')}{field('finess', 'FINESS · facultatif à cette étape', 'number-pad')}
        <Text style={shared.small}>La création de votre profil ne valide pas encore votre établissement. Le contrat et les preuves de vérification restent nécessaires avant publication.</Text>
      </>}
      {action.Error}
      {saved ? <Text style={shared.body} accessibilityLiveRegion="polite">{gateway.mode === 'demo' ? 'Brouillon de démonstration conservé en mémoire.' : 'Brouillon enregistré sur votre compte.'}</Text> : null}
      <ActionButton label="Enregistrer et reprendre plus tard" secondary busy={action.busy} testID="onboarding-save" onPress={() => { void action.run(async () => {
        await gateway.saveDraft(context.userId, form); if (action.mounted.current) setSaved(true);
      }); }} />
      <ActionButton label="Terminer mon profil" busy={action.busy} testID="onboarding-complete" onPress={() => { void action.run(async () => {
        await gateway.completeRegistration(context, form); if (action.mounted.current) onComplete();
      }); }} />
    </>}
    <ActionButton label="Se déconnecter" secondary onPress={onSignOut} testID="onboarding-sign-out" />
  </AccountLayout>;
}
