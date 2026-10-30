export const DOCUMENT_CAPTURES = Object.freeze([
  'documents-statuts', 'documents-revue-humaine', 'documents-remplacement-annule',
  'documents-remplacement-confirme', 'documents-envoi-incertain', 'documents-envoi-reconcilie',
  'documents-retrait-confirme', 'documents-reprise', 'documents-envoi-sans-enregistrement',
]);
export const CONTRACT_CAPTURES = Object.freeze([
  'contrats-liste', 'contrats-original', 'contrats-otp-simule', 'contrats-reprise',
  'contrats-signature-incertaine', 'contrats-signature-relue', 'contrats-lecture-seule', 'contrats-deux-signatures',
]);
export const PRESENCE_CAPTURES = Object.freeze([
  'presences-liste', 'presences-mission-avant', 'presences-auth-refusee', 'presences-confirmation-incertaine', 'presences-reprise',
  'presences-arrivee-relue', 'presences-ouverte', 'presences-code-obsolete', 'presences-depart-relu', 'presences-cloturee',
  'presences-code-initial', 'presences-code-renouvele', 'presences-retour-etablissement',
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
  if (!['consultation', 'documents', 'contracts', 'presence'].includes(name)) throw new Error('Scénario natif invalide.');
  if (env.EXPO_PUBLIC_JOLENE_MODE && env.EXPO_PUBLIC_JOLENE_MODE !== 'demo') throw new Error('Ces scénarios sont exclusivement fictifs.');
  if (name !== 'presence' && (env.EXPO_PUBLIC_JOLENE_PRESENCE_SCENARIO === '1' || env.NATIVE_PRESENCE_ORIENTATION)) {
    throw new Error('La préparation Pointage exige son scénario explicite.');
  }
  if (name === 'presence') {
    if (env.EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO === '1' || env.NATIVE_DOCUMENTS_ORIENTATION
      || env.EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO === '1' || env.NATIVE_CONTRACTS_ORIENTATION) {
      throw new Error('Le scénario Pointage doit rester isolé des autres injections fictives.');
    }
    const orientation = env.NATIVE_PRESENCE_ORIENTATION || 'portrait';
    if (!['portrait', 'landscape'].includes(orientation)
      || (orientation === 'landscape' && (platform !== 'ios' || family !== 'ipad'))) {
      throw new Error('Pointage paysage exige un simulateur iPad distinct.');
    }
    if (env.EXPO_PUBLIC_JOLENE_PRESENCE_SCENARIO && env.EXPO_PUBLIC_JOLENE_PRESENCE_SCENARIO !== '1') {
      throw new Error('Le scénario Pointage nécessite son injection fictive explicite.');
    }
    return { name, flowFile: 'presence-run.yaml', documentScenarioFlag: '0', contractScenarioFlag: '0',
      presenceScenarioFlag: '1', orientations: [orientation] };
  }
  if (name !== 'contracts' && (env.EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO === '1' || env.NATIVE_CONTRACTS_ORIENTATION)) {
    throw new Error('La préparation Contrats exige son scénario explicite.');
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
  if (selection.name === 'presence') {
    return orientation === 'landscape' ? 'testPresenceIpadLandscape'
      : family === 'ipad' ? 'testPresenceIpadPortrait' : 'testPresenceIphonePortrait';
  }
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
  const suffixes = selection.name === 'presence' ? [...PRESENCE_CAPTURES]
    : selection.name === 'contracts' ? [...CONTRACT_CAPTURES]
    : selection.name === 'documents' ? [...DOCUMENT_CAPTURES]
    : ['connexion', orientation === 'landscape' ? 'liste' : 'missions', 'detail', 'retour', ...EXTRA_CONSULTATION_CAPTURES];
  if (platform === 'android') return suffixes;
  if (selection.name === 'contracts') suffixes.splice(3, 0, 'contrats-home');
  const prefix = orientation === 'landscape' ? 'ipad-paysage' : `${family}-portrait`;
  return suffixes.map(suffix => `${prefix}-${suffix}`);
}
