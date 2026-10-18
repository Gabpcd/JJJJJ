/** Petit drain de clôture : même générateur et numérotation que la facturation quotidienne. */
export async function traiterDemandesHonoraires(supabase: any) {
  const { data, error } = await supabase.rpc('fn_prendre_demandes_facturation_honoraires', { p_limit: 3 });
  if (error) throw new Error('HONORAIRES_DEMANDES_LECTURE_IMPOSSIBLE');
  if (!Array.isArray(data) || data.length > 3) throw new Error('HONORAIRES_DEMANDES_REPONSE_INVALIDE');
  const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
  const missions = new Set<string>();
  // Valider le lot entier avant tout appel au générateur.
  for (const entry of data) {
    const body = entry?.body;
    const keys = body && typeof body === 'object' && !Array.isArray(body) ? Object.keys(body).sort().join(',') : '';
    if (!uuid.test(entry?.mission_id ?? '') || !uuid.test(entry?.token ?? '')
      || body?.mission_id !== entry.mission_id || keys !== 'mission_id' || missions.has(entry.mission_id)) {
      throw new Error('HONORAIRES_DEMANDE_SCOPE_INVALIDE');
    }
    missions.add(entry.mission_id);
  }
  const results: Array<{ mission_id: string; success: boolean; skipped: boolean }> = [];
  for (const entry of data) {
    let skipped = false;
    // La classification est aussi relue juste avant l'effet Edge, comme dans
    // le passage quotidien. Aucun profil TEST n'est reclassé par le drain.
    const { data: real, error: classificationError } = await supabase.rpc('fn_mission_est_reelle_pour_service', {
      p_mission_id: entry.mission_id,
    });
    if (!classificationError && real === true) {
      try {
        // Un seul appel par bail. 409, 500 ou réponse perdue ne suffisent ni à
        // acquitter ni à créer une seconde pièce : le constat SQL fait foi.
        await supabase.functions.invoke('generate-invoice', {
          body: { ...entry.body, service_role_reason: 'cron_auto_generation' },
        });
      } catch { /* Le constat ci-dessous conserve une reprise durable. */ }
    } else {
      skipped = !classificationError && real === false;
    }
    const { data: observed, error: observationError } = await supabase.rpc('fn_constater_demande_facturation_honoraires', {
      p_mission_id: entry.mission_id, p_token: entry.token,
    });
    results.push({ mission_id: entry.mission_id, success: !observationError && observed?.success === true, skipped });
  }
  return {
    total: results.length,
    ok: results.filter(r => r.success).length,
    failed: results.filter(r => !r.success && !r.skipped).length,
    skipped: results.filter(r => r.skipped).length,
    details: results,
  };
}
