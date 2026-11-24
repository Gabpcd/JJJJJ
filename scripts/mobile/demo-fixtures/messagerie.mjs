/**
 * Fixtures démo du domaine « messagerie » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T7a.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-conversations.json` : trois conversations du compte démo (`demo-soignant`), lues par `DemoMessagerieGateway` —
 * un établissement (mission encore ouverte : l'anti-fuite s'y applique), la plateforme, une conversation archivée.
 * Colonnes de `conversations` et clés de `fn_lister_conversations_messagerie` (supabase/schema/public.sql) ; les
 * colonnes dérivées des messages (`dernier_message_le`, `dernier_contenu`, `non_lus`, `ordre_le`) ne sont PAS écrites :
 * la gateway démo les dérive de `demo-messages.json`, comme le SQL, pour qu'elles ne puissent pas diverger.
 * `mission_statut` est propre à la démo : statut de la mission liée, lu par l'anti-fuite simulé (coordonnées admises
 * dès ASSIGNEE, comme `supabase/functions/messagerie-validate/index.ts`). `interlocuteurs` : lignes de
 * `fn_interlocuteurs_conversations` ; `etablissements` : interlocuteur opérationnel de chaque établissement démo
 * (`fn_user_id_pour_etablissement`) ; `presences` : lignes `presence_status`.
 *
 * `demo-messages.json` : lignes de `messages_chat` (deux non lues dans la conversation de l'établissement) et la
 * réponse que l'établissement démo émet sur le flux entrant après la relecture d'un message envoyé (`reponse_demo`).
 * Aucun contenu ne porte de coordonnée (pas de faux positif anti-fuite).
 *
 * Les missions et établissements démo sont ceux de l'exporteur (une seule source) : import cyclique sans effet tant
 * que ces liaisons ne sont lues qu'à l'appel de `fixtures()` (même règle que swipe.mjs).
 */
import { buildDemoMissions, DEMO_ETABLISSEMENTS } from '../export-demo-fixtures.mjs';

export const SOIGNANT_DEMO = 'demo-soignant';
export const PLATEFORME_DEMO = 'demo-jolene';
const interlocuteur = (etablissementId) => `demo-interlocuteur-${etablissementId.replace('demo-', '')}`;

/**
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  const minute = 60_000;
  const iso = (decalageMinutes) => new Date(contexte.now.getTime() + decalageMinutes * minute).toISOString();
  const jour = 24 * 60;
  const missionOuverte = buildDemoMissions(contexte.now).find((mission) => mission.id === 'demo-mission-004');
  const etablissements = DEMO_ETABLISSEMENTS.map((etab) => ({ id: etab.id, nom: etab.nom, interlocuteur_id: interlocuteur(etab.id) }));
  // Établissement de la mission ouverte (candidature en attente du compte démo) et un second pour la conversation archivée.
  const republique = etablissements.find((etab) => etab.id === missionOuverte.etablissement_id);
  const lilas = etablissements.find((etab) => etab.id !== republique.id);

  const conversations = [
    {
      id: 'demo-conv-001',
      participant_1_id: SOIGNANT_DEMO,
      participant_2_id: republique.interlocuteur_id,
      mission_id: missionOuverte.id,
      etablissement_id: republique.id,
      soignant_id: SOIGNANT_DEMO,
      cree_le: iso(-3 * jour),
      archived_at: null,
      autre_id: republique.interlocuteur_id,
      mission_intitule: missionOuverte.intitule,
      mission_statut: missionOuverte.statut,
    },
    {
      id: 'demo-conv-002',
      participant_1_id: PLATEFORME_DEMO,
      participant_2_id: SOIGNANT_DEMO,
      mission_id: null,
      etablissement_id: null,
      soignant_id: null,
      cree_le: iso(-10 * jour),
      archived_at: null,
      autre_id: PLATEFORME_DEMO,
      mission_intitule: null,
      mission_statut: null,
    },
    {
      id: 'demo-conv-003',
      participant_1_id: SOIGNANT_DEMO,
      participant_2_id: lilas.interlocuteur_id,
      mission_id: 'demo-terminee-002',
      etablissement_id: lilas.id,
      soignant_id: SOIGNANT_DEMO,
      cree_le: iso(-40 * jour),
      archived_at: iso(-5 * jour),
      autre_id: lilas.interlocuteur_id,
      mission_intitule: 'Démonstration · Mission terminée 2',
      mission_statut: 'TERMINEE',
    },
  ];

  const message = (numero, conversationId, auteurId, contenu, decalageMinutes, lu, estAdmin = false) => ({
    id: `demo-message-${String(numero).padStart(3, '0')}`,
    conversation_id: conversationId,
    auteur_id: auteurId,
    contenu,
    lu,
    est_admin: estAdmin,
    cree_le: iso(decalageMinutes),
  });

  return {
    'demo-conversations.json': {
      fixed_now: contexte.now.toISOString(),
      conversations,
      interlocuteurs: [
        { conversation_id: 'demo-conv-001', participant_id: republique.interlocuteur_id, prenom: republique.nom, nom: '', avatar_url: null, est_jolene: false },
        { conversation_id: 'demo-conv-002', participant_id: PLATEFORME_DEMO, prenom: 'Jolene', nom: '', avatar_url: null, est_jolene: true },
        { conversation_id: 'demo-conv-003', participant_id: lilas.interlocuteur_id, prenom: lilas.nom, nom: '', avatar_url: null, est_jolene: false },
      ],
      etablissements,
      presences: [
        { user_id: republique.interlocuteur_id, status: 'ONLINE', last_seen_at: iso(-2) },
        { user_id: lilas.interlocuteur_id, status: 'OFFLINE', last_seen_at: iso(-6 * jour) },
      ],
    },
    'demo-messages.json': {
      fixed_now: contexte.now.toISOString(),
      messages: [
        message(1, 'demo-conv-001', SOIGNANT_DEMO, 'Bonjour, je suis disponible pour cette mission.', -26 * 60, true),
        message(2, 'demo-conv-001', republique.interlocuteur_id, 'Bonjour Camille, merci pour votre candidature.', -3 * 60, false),
        message(3, 'demo-conv-001', republique.interlocuteur_id, 'Pouvez-vous nous préciser votre expérience en médecine polyvalente ?', -170, false),
        message(4, 'demo-conv-002', PLATEFORME_DEMO, 'Bienvenue sur Jolene. Cette conversation vous relie à notre équipe.', -10 * jour + 5, true, true),
        message(5, 'demo-conv-003', lilas.interlocuteur_id, 'Merci pour votre mission, à bientôt.', -36 * jour, true),
        message(6, 'demo-conv-003', SOIGNANT_DEMO, 'Merci à vous, bonne continuation.', -36 * jour + 10, true),
      ],
      reponse_demo: { contenu: 'Bien reçu, merci pour votre message.' },
    },
  };
}
