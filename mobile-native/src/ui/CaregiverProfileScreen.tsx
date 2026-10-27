import { useEffect, useRef, useState } from 'react';
import { Keyboard, KeyboardAvoidingView, Platform, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { getProfessionLabel } from '../data/presentation';
import type { MissionReadContext } from '../data/types';
import { calculerCompletionProfil, identityLocked, profileChanges, type CaregiverProfile, type ProfileChanges, type ProfileGateway } from '../caregiver/profile';
import { ActionButton, ErrorNotice, LabelValue, ModeNotice, StatusPanel } from './components';
import { colors, shared } from './theme';
import { useMissionResource } from './useMissionResource';

export function CaregiverProfileScreen({ context, gateway, onSaved, onSignOut }: {
  context: MissionReadContext; gateway: ProfileGateway; onSaved: () => void; onSignOut: () => void;
}) {
  const resource = useMissionResource(`profile:${context.userId}`, signal => gateway.read(context, signal),
    'Votre profil ne peut pas être chargé. Vérifiez votre connexion puis réessayez.');
  return <SafeAreaView style={shared.screen} edges={['left', 'right']}>
    <KeyboardAvoidingView style={shared.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined} keyboardVerticalOffset={96}>
      <ScrollView keyboardShouldPersistTaps="handled" keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'on-drag'}
        testID="caregiver-profile-scroll" contentContainerStyle={styles.content}
        refreshControl={<RefreshControl refreshing={resource.loading && resource.data !== null} onRefresh={resource.refresh} />}>
        <View style={[shared.content, styles.body]}>
          <ModeNotice mode={gateway.mode === 'demo' ? 'demo' : 'staging'} />
          {resource.error ? <ErrorNotice message={resource.error} onRetry={resource.refresh} /> : null}
          {resource.data ? <ProfileForm key={context.userId} profile={resource.data} context={context} gateway={gateway} onSaved={onSaved} />
            : <StatusPanel loading={resource.loading} title={resource.loading ? 'Chargement du profil' : 'Profil indisponible'} />}
          <ActionButton secondary label="Se déconnecter" onPress={onSignOut} testID="profile-sign-out" />
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  </SafeAreaView>;
}

function ProfileForm({ profile: original, context, gateway, onSaved }: {
  profile: CaregiverProfile; context: MissionReadContext; gateway: ProfileGateway; onSaved: () => void;
}) {
  const [profile, setProfile] = useState(original);
  const [form, setForm] = useState(() => profileChanges(original));
  const [dirty, setDirty] = useState(false);
  const dirtyRef = useRef(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const request = useRef<AbortController | null>(null);
  const focused = useIsFocused();
  useEffect(() => {
    setProfile(original);
    if (!dirtyRef.current) setForm(profileChanges(original));
  }, [original]);
  useEffect(() => () => { request.current?.abort(); request.current = null; }, []);
  useEffect(() => {
    if (!focused) { request.current?.abort(); request.current = null; setBusy(false); }
  }, [focused]);
  const update = <K extends keyof ProfileChanges>(key: K, value: ProfileChanges[K]) => {
    dirtyRef.current = true;
    setForm(previous => ({ ...previous, [key]: value })); setDirty(true); setSaved(false);
  };
  const save = async () => {
    if (request.current || !focused) return;
    Keyboard.dismiss();
    const abort = new AbortController(); request.current = abort;
    setBusy(true); setError(null); setSaved(false);
    try {
      const result = await gateway.save(context, form, abort.signal);
      if (abort.signal.aborted) return;
      dirtyRef.current = false;
      setProfile(result); setForm(profileChanges(result)); setDirty(false); setSaved(true); onSaved();
    } catch (reason) {
      if (!abort.signal.aborted) setError(reason instanceof Error ? reason.message : 'Enregistrement non confirmé. Actualisez pour vérifier votre profil.');
    } finally {
      if (request.current === abort) { request.current = null; setBusy(false); }
    }
  };
  const completion = calculerCompletionProfil(profile);
  const locked = identityLocked(profile);
  return <>
    <View style={styles.heading}>
      <Text style={shared.title} accessibilityRole="header" testID="caregiver-profile-title">Mon profil</Text>
      <Text style={shared.subtitle}>{getProfessionLabel(profile.profession ?? '')}</Text>
      {profile.rpps_verifie === true ? <Text style={styles.verified}>RPPS Vérifié</Text> : profile.identite_verifiee === true ? <Text style={styles.verified}>Identité vérifiée</Text> : null}
      <Text style={shared.small}>Profil complété à {completion.pourcentage}%</Text>
    </View>
    <View style={[shared.card, styles.fields]}>
      <Text style={shared.sectionTitle}>Mes informations</Text>
      <LabelValue label="Email" value={profile.email ?? context.email ?? 'Non renseigné'} />
      {locked ? <>
        <LabelValue label="Prénom et nom vérifiés" value={[profile.prenom, profile.nom].filter(Boolean).join(' ')} />
        <LabelValue label="Date de naissance" value={profile.date_naissance ?? 'Non renseignée'} />
      </> : <>
        <Field editable={!busy} label="Prénom" value={form.prenom} onChangeText={value => update('prenom', value)} testID="profile-first-name" />
        <Field editable={!busy} label="Nom" value={form.nom} onChangeText={value => update('nom', value)} testID="profile-last-name" />
        <Field editable={!busy} label="Date de naissance (AAAA-MM-JJ)" value={form.dateNaissance} onChangeText={value => update('dateNaissance', value)} testID="profile-birth-date" />
      </>}
      <Field editable={!busy} label="Téléphone" value={form.telephone} onChangeText={value => update('telephone', value)} keyboardType="phone-pad" testID="profile-phone" />
      <LabelValue label="RPPS" value={profile.numero_rpps ?? 'Non renseigné'} />
    </View>
    <View style={[shared.card, styles.fields]}>
      <Text style={shared.sectionTitle}>À propos de moi</Text>
      <Field editable={!busy} label="Présentation" value={form.bio} onChangeText={value => update('bio', value)} multiline testID="profile-bio" />
      <Field editable={!busy} label="Années d’expérience" value={Number.isFinite(form.anneesExperience) ? String(form.anneesExperience) : ''}
        onChangeText={value => update('anneesExperience', value.trim() ? Number(value.replace(',', '.')) : Number.NaN)} keyboardType="decimal-pad" testID="profile-experience" />
      <Field editable={!busy} label="Ville de recherche" value={form.ville} onChangeText={value => update('ville', value)} testID="profile-city" />
      <Field editable={!busy} label="Rayon de recherche (km)" value={Number.isFinite(form.rayon) ? String(form.rayon) : ''}
        onChangeText={value => update('rayon', value.trim() ? Number(value.replace(',', '.')) : Number.NaN)} keyboardType="number-pad" testID="profile-radius" />
    </View>
    {error ? <ErrorNotice message={error} /> : null}
    {saved ? <Text style={styles.verified} accessibilityLiveRegion="polite" testID="profile-saved">{gateway.mode === 'demo' ? 'Profil fictif enregistré pour cette démonstration.' : 'Profil enregistré.'}</Text> : null}
    <ActionButton label="Enregistrer mon profil" onPress={() => { void save(); }} disabled={!dirty} busy={busy} testID="save-profile" />
  </>;
}

function Field({ label, ...props }: React.ComponentProps<typeof TextInput> & { label: string }) {
  return <View style={styles.field}>
    <Text style={shared.small}>{label}</Text>
    <TextInput accessibilityLabel={label} style={[styles.input, props.multiline && styles.multiline]} {...props} />
  </View>;
}
const styles = StyleSheet.create({
  content: { flexGrow: 1, paddingVertical: 20 }, body: { gap: 20 }, heading: { gap: 8 }, fields: { gap: 16 },
  field: { gap: 7 }, input: { minHeight: 50, borderWidth: 1, borderColor: colors.border, borderRadius: 12,
    color: colors.text, paddingHorizontal: 14, paddingVertical: 13, fontSize: 16, backgroundColor: colors.surface },
  multiline: { minHeight: 110, textAlignVertical: 'top' }, verified: { color: colors.success, fontSize: 15, lineHeight: 23, fontWeight: '600' },
});
