/**
 * Lot 5, T11 — messagerie de l'établissement démo (`docs/mobile-swift/LOT5_PLAN.md` §3 T11, fixture
 * `demo-etab-messagerie.json`), écrite par `export-demo-fixtures.mjs` (job « Cœur » : sortie diffée).
 *
 * Deux conversations vues par le compte établissement démo (`utilisateur.id` de `demo-etablissement.json`), dérivées de
 * `demo-etab-missions.json` (missions, soignants assignés, intitulés et statuts : jamais ressaisis) :
 *   - mission M4 (assignée, soignant démo principal) : un message d'un collègue de l'équipe (`demo-etab-collegue`,
 *     bulle « Équipe établissement ») et deux messages non lus du soignant — autant que `messages_non_lus` de
 *     `demo-etab-dashboard.json` ;
 *   - mission M8 (terminée) : conversation archivée (composeur désactivé).
 * Colonnes de `conversations` et clés de `fn_lister_conversations_messagerie` (supabase/schema/public.sql), sans les
 * colonnes dérivées des messages (la gateway démo les calcule, comme le SQL). `mission_statut` est propre à la démo
 * (anti-fuite simulé). Aucun contenu ne porte de coordonnée (pas de faux positif anti-fuite).
 */

const COLLEGUE = 'demo-etab-collegue';

/**
 * @param {{ now: Date, utilisateurId: string, missions: { etablissement_id: string, missions: object[], soignants: object[] } }} entree
 */
export function buildDemoEtabMessagerie({ now, utilisateurId, missions }) {
  const iso = (minutes) => new Date(now.getTime() + minutes * 60_000).toISOString();
  const mission = (id) => {
    const ligne = missions.missions.find((m) => m.id === id);
    if (!ligne || !ligne.soignant_assigne_id) throw new Error(`Mission assignée ${id} absente de demo-etab-missions.json`);
    return ligne;
  };
  const soignant = (id) => {
    const ligne = missions.soignants.find((s) => s.id === id);
    if (!ligne) throw new Error(`Soignant ${id} absent de demo-etab-missions.json`);
    return ligne;
  };
  const jour = 24 * 60;
  const conversation = (id, m, archiveeIl) => ({
    id,
    participant_1_id: m.soignant_assigne_id,
    participant_2_id: utilisateurId,
    mission_id: m.id,
    etablissement_id: missions.etablissement_id,
    soignant_id: m.soignant_assigne_id,
    cree_le: iso(-3 * jour),
    archived_at: archiveeIl == null ? null : iso(-archiveeIl),
    autre_id: m.soignant_assigne_id,
    mission_intitule: m.intitule,
    mission_statut: m.statut,
  });
  const m4 = mission('demo-etab-m04');
  const m8 = mission('demo-etab-m08');
  const conversations = [conversation('demo-etab-conv-001', m4, null), conversation('demo-etab-conv-002', m8, 2 * jour)];
  const interlocuteur = (c) => {
    const s = soignant(c.soignant_id);
    return { conversation_id: c.id, participant_id: s.id, prenom: s.prenom, nom: s.nom, avatar_url: null, est_jolene: false };
  };
  let numero = 0;
  const message = (conversationId, auteurId, contenu, minutes, lu) => ({
    id: `demo-etab-message-${String(++numero).padStart(3, '0')}`,
    conversation_id: conversationId,
    auteur_id: auteurId,
    contenu,
    lu,
    est_admin: false,
    cree_le: iso(minutes),
  });
  return {
    fixed_now: now.toISOString(),
    conversations,
    interlocuteurs: conversations.map(interlocuteur),
    presences: [
      { user_id: m4.soignant_assigne_id, status: 'ONLINE', last_seen_at: iso(-1) },
      { user_id: m8.soignant_assigne_id, status: 'OFFLINE', last_seen_at: iso(-3 * jour) },
    ],
    messages: [
      message('demo-etab-conv-001', m4.soignant_assigne_id, 'Bonjour, je confirme ma présence pour la nuit.', -5 * 60, true),
      message('demo-etab-conv-001', COLLEGUE, "Bonjour, l'équipe de nuit vous accueillera à l'accueil principal.", -4 * 60, true),
      message('demo-etab-conv-001', m4.soignant_assigne_id, 'Merci, faut-il un badge pour entrer ?', -40, false),
      message('demo-etab-conv-001', m4.soignant_assigne_id, 'Je peux arriver un peu en avance si besoin.', -35, false),
      message('demo-etab-conv-002', utilisateurId, 'Merci pour votre mission.', -6 * jour, true),
      message('demo-etab-conv-002', m8.soignant_assigne_id, 'Merci à vous, bonne continuation.', -6 * jour + 10, true),
    ],
    reponse_demo: { contenu: 'Bien reçu, merci.' },
  };
}
