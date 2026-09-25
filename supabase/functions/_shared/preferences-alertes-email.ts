interface ClientPreferences {
  rpc: (nom: string, params: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }>;
}

/** La ligne ETAB historique de l'UI utilise l'événement mission. Un refus dans
 * l'une des deux clés prévaut ; l'UI synchronise les clés à un nouveau choix.
 */
export async function verifierPreferencesEvenementsEmail(
  client: ClientPreferences, destinataireId: string, typeEmail: string, evenement: string,
): Promise<boolean> {
  const evenements = typeEmail === 'NOUVEAUX_SOIGNANTS_FILTRE'
    ? ['NOUVEAU_SOIGNANT_MATCHANT_FILTRE', 'NOUVELLE_MISSION_MATCHANT_FILTRE']
    : [evenement];
  for (const type of evenements) {
    const { data, error } = await client.rpc('fn_doit_notifier', {
      p_utilisateur_id: destinataireId, p_type_evenement: type, p_canal: 'EMAIL',
    });
    if (error || typeof data !== 'boolean') throw new Error('Vérification des préférences indisponible');
    if (!data) return false;
  }
  return true;
}
