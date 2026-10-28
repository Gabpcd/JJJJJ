export const DOCUMENT_CAPTURES = Object.freeze([
  'documents-statuts', 'documents-revue-humaine', 'documents-remplacement-annule',
  'documents-remplacement-confirme', 'documents-envoi-incertain', 'documents-envoi-reconcilie',
  'documents-retrait-confirme', 'documents-reprise', 'documents-envoi-sans-enregistrement',
]);
export const CONTRACT_CAPTURES = Object.freeze([
  'contrats-liste', 'contrats-original', 'contrats-otp-simule', 'contrats-reprise',
  'contrats-signature-incertaine', 'contrats-signature-relue', 'contrats-lecture-seule', 'contrats-deux-signatures',
]);
const EXTRA_CONSULTATION_CAPTURES = [
  'mission-annulee', 'candidature-confirmee', 'mes-missions', 'dossier-relu', 'profil-relu',
  'etablissement-accueil', 'etablissement-missions', 'etablissement-planning', 'etablissement-retour',
  'etablissement-acces', 'inscription-internat', 'inscription-terminee',
];

/** Fail before starting any tool if the named synthetic scenario is ambiguous or incompatible. */
export function selectNativeScenario(env, platform, family = 'iphone') {
  if (!['ios', 'android'].includes(platform) || !['iphone', 'ipad'].includes(family)) throw new Error('Format natif invalide.');
  const name = env.NATIVE_PILOT_SCENARIO || 'consultation';
  if (!['consultation', 'documents', 'contracts', 'input-reference'].includes(name)) throw new Error('Scénario natif invalide.');
  if (env.EXPO_PUBLIC_JOLENE_MODE && env.EXPO_PUBLIC_JOLENE_MODE !== 'demo') throw new Error('Ces scénarios sont exclusivement fictifs.');
  if (name !== 'contracts' && (env.EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO === '1' || env.NATIVE_CONTRACTS_ORIENTATION)) {
    throw new Error('La préparation Contrats exige son scénario explicite.');
  }
  if (name === 'input-reference') {
    if (platform !== 'ios' || family !== 'iphone' || env.NATIVE_INPUT_REFERENCE_PROJECT !== '1'
      || (env.NATIVE_IOS_HOST && env.NATIVE_IOS_HOST !== 'expo-go')
      || env.EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO === '1' || env.NATIVE_DOCUMENTS_ORIENTATION) {
      throw new Error('Le témoin RN exige son projet synthétique séparé et Expo Go sur iPhone.');
    }
    return { name, flowFile: null, documentScenarioFlag: '0', contractScenarioFlag: '0',
      iosTestClass: 'NativeInputReferenceTests', orientations: ['portrait'] };
  }
  if (name === 'contracts') {
    if (env.EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO === '1' || env.NATIVE_DOCUMENTS_ORIENTATION) {
      throw new Error('Les scénarios Contrats et Documents doivent rester isolés.');
    }
    const orientation = env.NATIVE_CONTRACTS_ORIENTATION || 'portrait';
    if (!['portrait', 'landscape'].includes(orientation)
      || (orientation === 'landscape' && (platform !== 'ios' || family !== 'ipad'))) {
      throw new Error('Contrats paysage exige un simulateur iPad distinct.');
    }
    if (env.EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO && env.EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO !== '1') {
      throw new Error('Le scénario Contrats nécessite son injection fictive explicite.');
    }
    return { name, flowFile: 'contracts-run.yaml', documentScenarioFlag: '0', contractScenarioFlag: '1', orientations: [orientation] };
  }
  if (name === 'consultation') {
    if (env.EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO === '1' || env.NATIVE_DOCUMENTS_ORIENTATION) {
      throw new Error('La préparation Documents exige son scénario explicite.');
    }
    return { name, flowFile: 'consultation.yaml', documentScenarioFlag: '0',
      orientations: platform === 'ios' && family === 'ipad' ? ['portrait', 'landscape'] : ['portrait'] };
  }
  const orientation = env.NATIVE_DOCUMENTS_ORIENTATION || 'portrait';
  if (!['portrait', 'landscape'].includes(orientation)
    || (orientation === 'landscape' && (platform !== 'ios' || family !== 'ipad'))) {
    throw new Error('Documents paysage exige un simulateur iPad distinct.');
  }
  if (env.EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO && env.EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO !== '1') {
    throw new Error('Le scénario Documents nécessite son injection fictive explicite.');
  }
  return { name, flowFile: 'documents-run.yaml', documentScenarioFlag: '1', orientations: [orientation] };
}

export function iosTestMethod(selection, family, orientation) {
  if (!selection.orientations.includes(orientation)) throw new Error('Orientation non sélectionnée.');
  if (selection.name === 'input-reference') return 'testFields';
  if (selection.name === 'contracts') {
    return orientation === 'landscape' ? 'testContractsIpadLandscape'
      : family === 'ipad' ? 'testContractsIpadPortrait' : 'testContractsIphonePortrait';
  }
  if (selection.name === 'documents') {
    return orientation === 'landscape' ? 'testDocumentsIpadLandscape'
      : family === 'ipad' ? 'testDocumentsIpadPortrait' : 'testDocumentsIphonePortrait';
  }
  return orientation === 'landscape' ? 'testLandscapeConsultation'
    : family === 'ipad' ? 'testPortraitConsultation' : 'testIphoneConsultation';
}

export function scenarioCaptureNames(selection, platform, family, orientation) {
  if (!selection.orientations.includes(orientation)) throw new Error('Orientation non sélectionnée.');
  if (selection.name === 'input-reference') {
    return ['controlled-styled', 'uncontrolled-styled', 'controlled-basic']
      .flatMap(variant => [`input-reference-${variant}-before`, `input-reference-${variant}-after`]);
  }
  const suffixes = selection.name === 'contracts' ? [...CONTRACT_CAPTURES]
    : selection.name === 'documents' ? [...DOCUMENT_CAPTURES]
    : ['connexion', orientation === 'landscape' ? 'liste' : 'missions', 'detail', 'retour', ...EXTRA_CONSULTATION_CAPTURES];
  if (platform === 'android') return suffixes;
  if (selection.name === 'contracts') suffixes.splice(3, 0, 'contrats-home');
  const prefix = orientation === 'landscape' ? 'ipad-paysage' : `${family}-portrait`;
  return suffixes.map(suffix => `${prefix}-${suffix}`);
}
