import { useState } from 'react';
import { Linking, Text } from 'react-native';
import { PROFESSIONS } from '../../../../src/lib/constantes';
import type { NativeAccountGateway, NativeAccountType } from '../../account/types';
import { ActionButton } from '../components';
import { shared } from '../theme';
import { AccountCheck, AccountChoice, AccountField, AccountLayout, useAccountAction } from './components';

export function RegistrationScreen({ gateway, onBack, onContinue }: { gateway: NativeAccountGateway; onBack: () => void; onContinue: () => void }) {
  const [type, setType] = useState<NativeAccountType>('SOIGNANT');
  const [email, setEmail] = useState(gateway.mode === 'demo' ? 'inscription@demo.invalid' : '');
  const [password, setPassword] = useState(gateway.mode === 'demo' ? 'demonstration' : '');
  const [profession, setProfession] = useState('');
  const [nom, setNom] = useState('');
  const [cgu, setCgu] = useState(false);
  const [cgv, setCgv] = useState(false);
  const [confirmation, setConfirmation] = useState<string | null>(null);
  const action = useAccountAction();
  const submit = () => { void action.run(async () => {
    const result = await gateway.createAccount({ type, email, password, profession, nom, cgu, cgv });
    if (!action.mounted.current) return;
    setPassword('');
    if (result.status === 'confirmation') setConfirmation(result.email);
    else onContinue();
  }); };
  return <AccountLayout title="Créer mon compte" mode={gateway.mode} onBack={onBack}>
    {confirmation ? <>
      <Text style={shared.sectionTitle}>Confirmez votre adresse email</Text>
      <Text style={shared.body}>Un lien de confirmation a été demandé pour {confirmation}. Ouvrez le lien reçu puis revenez dans Jolene. Votre profil professionnel sera complété ensuite.</Text>
      <ActionButton label="J’ai confirmé mon email · me connecter" onPress={onBack} testID="registration-confirmed" />
    </> : <>
      <AccountChoice label="Votre espace" value={type} choices={[{ valeur: 'SOIGNANT', label: 'Je suis soignant' }, { valeur: 'ETABLISSEMENT', label: 'Je représente un établissement' }]}
        onChange={value => setType(value as NativeAccountType)} disabled={action.busy} testID="registration-type" />
      <AccountField label="Adresse email" value={email} onChangeText={setEmail} autoCapitalize="none" keyboardType="email-address" autoComplete="email" editable={!action.busy} testID="registration-email" />
      <AccountField label="Mot de passe · 8 caractères minimum" value={password} onChangeText={setPassword} secureTextEntry autoCapitalize="none" autoCorrect={false} autoComplete="new-password" editable={!action.busy} testID="registration-password" />
      {type === 'SOIGNANT' ? <AccountChoice label="Profession" value={profession} choices={PROFESSIONS} onChange={setProfession} disabled={action.busy} testID="registration-profession" />
        : <AccountField label="Nom de l’établissement" value={nom} onChangeText={setNom} editable={!action.busy} testID="registration-establishment-name" />}
      <AccountCheck label="J’accepte les conditions générales d’utilisation et la politique de confidentialité" checked={cgu} onChange={setCgu} disabled={action.busy} testID="registration-cgu" />
      <ActionButton label="Lire les conditions d’utilisation" secondary onPress={() => { void action.run(async () => { await Linking.openURL('https://jolene.app/cgu'); }); }} />
      <ActionButton label="Lire la politique de confidentialité" secondary onPress={() => { void action.run(async () => { await Linking.openURL('https://jolene.app/confidentialite'); }); }} />
      {type === 'ETABLISSEMENT' ? <>
        <AccountCheck label="J’accepte les conditions générales de vente" checked={cgv} onChange={setCgv} disabled={action.busy} testID="registration-cgv" />
        <ActionButton label="Lire les conditions de vente" secondary onPress={() => { void action.run(async () => { await Linking.openURL('https://jolene.app/cgv'); }); }} />
      </> : null}
      {action.Error}
      <ActionButton label={action.busy ? 'Création en cours…' : 'Créer mon compte'} onPress={submit} busy={action.busy} testID="registration-submit" />
      <Text style={shared.small}>{type === 'SOIGNANT' ? 'Votre dossier professionnel et les vérifications se complètent ensuite.' : 'Les vérifications de votre établissement restent nécessaires avant la publication d’une mission.'}</Text>
    </>}
  </AccountLayout>;
}
