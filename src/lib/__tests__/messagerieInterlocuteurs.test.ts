import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  cleInterlocuteur,
  indexerInterlocuteurs,
  type InterlocuteurConversation,
} from '@/lib/messagerieInterlocuteurs';

const lignes: InterlocuteurConversation[] = [
  {
    conversation_id: 'conversation-1',
    participant_id: 'soignant-auth-id',
    prenom: 'Marie',
    nom: 'Lefèvre',
    avatar_url: 'https://example.test/marie.png',
    est_jolene: false,
  },
  {
    conversation_id: 'conversation-1',
    participant_id: 'etablissement-auth-id',
    prenom: 'Clinique Jolene',
    nom: '',
    avatar_url: 'https://example.test/clinique.png',
    est_jolene: false,
  },
];

describe('résolution des interlocuteurs de messagerie', () => {
  it('distingue le profil soignant de l’utilisateur Auth établissement', () => {
    const index = indexerInterlocuteurs(lignes);

    expect(index.get(cleInterlocuteur('conversation-1', 'soignant-auth-id'))).toMatchObject({
      prenom: 'Marie',
      nom: 'Lefèvre',
    });
    expect(index.get(cleInterlocuteur('conversation-1', 'etablissement-auth-id'))).toMatchObject({
      prenom: 'Clinique Jolene',
      nom: '',
    });
  });

  it('ne mélange pas un même participant entre deux conversations', () => {
    const index = indexerInterlocuteurs([
      ...lignes,
      { ...lignes[1], conversation_id: 'conversation-2', prenom: 'Autre établissement' },
    ]);

    expect(index.get(cleInterlocuteur('conversation-1', 'etablissement-auth-id'))?.prenom)
      .toBe('Clinique Jolene');
    expect(index.get(cleInterlocuteur('conversation-2', 'etablissement-auth-id'))?.prenom)
      .toBe('Autre établissement');
  });

  it('revalide la relation et interdit les mutations directes des conversations', () => {
    const migration = readFileSync(
      resolve(
        process.cwd(),
        'supabase/migrations/20260714090000_borner_creation_conversations.sql',
      ),
      'utf8',
    );

    expect(migration).toContain('private.fn_relation_messagerie_autorisee');
    expect(migration).toContain('public.fn_conversation_accessible(c.id)');
    expect(migration).toContain('DROP POLICY IF EXISTS pol_conv_insert');
    expect(migration).toContain('DROP POLICY IF EXISTS pol_conv_update');
    expect(migration).toContain('REVOKE INSERT, UPDATE ON TABLE public.conversations');
    expect(migration).toContain('REVOKE INSERT, UPDATE ON TABLE public.messages_chat');
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.fn_obtenir_conversation(uuid, uuid)',
    );
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.fn_obtenir_conversation(uuid, uuid)',
    );
    expect(migration).not.toMatch(
      /GRANT EXECUTE ON FUNCTION public\.fn_obtenir_conversation\(uuid, uuid\)[\s\S]{0,80}service_role/,
    );
    expect(migration).toContain('IF cardinality(p_conversation_ids) > 100 THEN');
  });

  it('borne le resolver aux candidatures acceptées et aux rôles opérationnels', () => {
    const migration = readFileSync(
      resolve(
        process.cwd(),
        'supabase/migrations/20260714083447_corriger_resolution_interlocuteur_etablissement.sql',
      ),
      'utf8',
    );

    expect(migration).toContain("AND c.statut = 'ACCEPTEE'");
    expect(migration).toContain("m.role IN ('PROPRIETAIRE', 'ADMIN_GROUPE', 'RH')");
    expect(migration).toContain('AND NOT EXISTS (');
  });

  it('conserve les redirections de chat sur un vrai identifiant de conversation', () => {
    const detail = readFileSync(
      resolve(process.cwd(), 'src/pages/DetailMission.tsx'),
      'utf8',
    );
    const historique = readFileSync(
      resolve(process.cwd(), 'src/pages/HistoriqueMissions.tsx'),
      'utf8',
    );

    expect(detail).toContain('ouvrirConv(m.soignant_assigne_id, m.id)');
    expect(detail).not.toContain('ouvrirConv(m.soignant_assigne_id, m.id, isAdmin)');
    expect(historique).toContain("'fn_obtenir_conversation'");
    expect(historique).toContain('p_mission_id: missionId');
    expect(historique).toContain('messagerie?conv=${conversationId}');
    expect(historique).not.toContain('messagerie?dest=');
  });

  it('valide côté utilisateur avant toute lecture privilégiée et insère atomiquement', () => {
    const edge = readFileSync(
      resolve(process.cwd(), 'supabase/functions/messagerie-validate/index.ts'),
      'utf8',
    );
    const verificationUtilisateur = edge.indexOf('.from("conversations")');
    const creationClientAdmin = edge.indexOf('const supabaseAdmin = createClient');

    expect(verificationUtilisateur).toBeGreaterThan(-1);
    expect(creationClientAdmin).toBeGreaterThan(verificationUtilisateur);
    expect(edge).toContain('"fn_envoyer_message_valide"');
    expect(edge).toContain('p_detected_type: detection.blocked ? detection.type : null');
    expect(edge).not.toMatch(/from\(["']messages_chat["']\)[\s\S]{0,160}\.insert\(/);
  });

  it('rend la notification d’acceptation idempotente et correctement routée', () => {
    const edge = readFileSync(
      resolve(
        process.cwd(),
        'supabase/functions/notif-candidature-acceptee/index.ts',
      ),
      'utf8',
    );
    const migration = readFileSync(
      resolve(
        process.cwd(),
        'supabase/migrations/20260714094000_transactionnaliser_notification_candidature.sql',
      ),
      'utf8',
    );

    expect(edge).toContain('cand.statut !== "ACCEPTEE"');
    expect(edge).toContain('"fn_notifier_candidature_acceptee"');
    expect(edge).not.toMatch(/\.from\(["']notifications["']\)/);
    expect(migration).toContain("AND c.statut = 'ACCEPTEE'");
    expect(migration).toContain("'CANDIDATURE_ACCEPTEE'");
    expect(migration).toContain("'mission',");
    expect(migration).toContain("'/soignant/messagerie?conv='");
    expect(migration).toContain('pg_advisory_xact_lock');
  });

  it('ferme tous les anciens INSERT directs sans supprimer leur historique', () => {
    const migrationLegacy = readFileSync(
      resolve(
        process.cwd(),
        'supabase/migrations/20260714095000_fermer_canal_mission_legacy.sql',
      ),
      'utf8',
    );
    const migrationSupport = readFileSync(
      resolve(
        process.cwd(),
        'supabase/migrations/20260714096000_securiser_messages_contact_litige.sql',
      ),
      'utf8',
    );
    const migrationQuotas = readFileSync(
      resolve(
        process.cwd(),
        'supabase/migrations/20260714097000_borner_flood_messages.sql',
      ),
      'utf8',
    );
    const detail = readFileSync(
      resolve(process.cwd(), 'src/pages/DetailMission.tsx'),
      'utf8',
    );
    const adminSupport = readFileSync(
      resolve(process.cwd(), 'src/pages/admin/AdminMessagesContact.tsx'),
      'utf8',
    );

    expect(migrationLegacy).toContain('REVOKE ALL ON TABLE public.messages_mission');
    expect(migrationLegacy).toContain('DROP POLICY IF EXISTS pol_messages_litige_insert');
    expect(migrationSupport).toContain('DROP POLICY IF EXISTS messages_contact_insert_self');
    expect(migrationSupport).toContain('fn_admin_traiter_message_contact');
    expect(migrationSupport).toContain('p_litige_id, v_uid, v_type_auteur, v_contenu');
    expect(migrationQuotas).toContain('pg_advisory_xact_lock');
    expect(migrationQuotas).toContain('dec_borner_flood_message_contact');
    expect(migrationQuotas).toContain('dec_borner_flood_message_litige');
    expect(detail).not.toContain('ChatMission');
    expect(existsSync(resolve(process.cwd(), 'src/components/ChatMission.tsx'))).toBe(false);
    expect(adminSupport).toContain("'fn_admin_traiter_message_contact'");
    expect(adminSupport).not.toContain(".from('messages_contact' as any)\n      .update");
  });
});
