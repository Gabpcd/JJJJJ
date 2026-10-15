export const CONTROLE_RPPS_SANS_SOURCE = {
  titre: 'Contrôle RPPS enregistré',
  source: 'Source de vérification non disponible dans le profil.',
};

// Seule la réponse courante porte une provenance. Le profil rechargé ne la
// conserve pas : ne jamais la déduire du numéro ou du type de compte.
export function presenterControleRpps(source?: unknown) {
  if (source === 'Mode test contrôlé') {
    return {
      titre: 'Contrôle RPPS de test — aucune vérification officielle',
      source: 'Source : mode test contrôlé.',
    };
  }
  if (source === 'FHIR Annuaire Santé v2') {
    return {
      titre: 'RPPS vérifié dans l’Annuaire Santé',
      source: 'Source : Annuaire Santé (ANS).',
    };
  }
  return CONTROLE_RPPS_SANS_SOURCE;
}
