import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const lire = (chemin: string) => readFileSync(
  resolve(process.cwd(), chemin),
  'utf8',
);

describe('présence et saisie temps réel de la messagerie', () => {
  it('accorde seulement la lecture Realtime aux comptes authentifiés', () => {
    const migration = lire(
      'supabase/migrations/20260714093000_durcir_presence_messagerie.sql',
    );

    expect(migration).toContain(
      'GRANT SELECT ON TABLE public.typing_status, public.presence_status',
    );
    expect(migration).toContain(
      'public.fn_conversation_accessible(conversation_id)',
    );
    expect(migration).toContain(
      'c.id = typing_status.conversation_id',
    );
    expect(migration).toContain(
      'AND public.fn_conversation_accessible(c.id)',
    );
    expect(migration).toContain(
      "ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_status",
    );
    expect(migration).toContain(
      "ALTER PUBLICATION supabase_realtime ADD TABLE public.presence_status",
    );
    expect(migration).toContain("cron.schedule(");
    expect(migration).toContain("'messagerie-cleanup'");
  });

  it('revalide la conversation et le compte dans les RPC privilégiées', () => {
    const migration = lire(
      'supabase/migrations/20260714093000_durcir_presence_messagerie.sql',
    );

    expect(migration).toContain(
      'public.fn_compte_auth_actif() IS NOT TRUE',
    );
    expect(migration).toContain(
      'public.fn_conversation_accessible(p_conversation_id) IS NOT TRUE',
    );
    expect(migration).toContain("SET search_path TO ''");
    expect(migration).toContain(
      'DROP POLICY IF EXISTS pol_typing_status_upsert',
    );
    expect(migration).toContain(
      'DROP POLICY IF EXISTS pol_presence_status_update',
    );
  });

  it('réinitialise le hook et récupère une saisie déjà commencée', () => {
    const hook = lire('src/hooks/useConversationRealtime.ts');

    expect(hook).toContain("setPresence('OFFLINE')");
    expect(hook).toContain('setLastSeen(null)');
    expect(hook).toContain('setTyping(false)');
    expect(hook).toContain(".from('typing_status' as any)");
    expect(hook).toContain(".eq('user_id', autreUserId)");
    expect(hook).toContain(".gt('started_at', seuil)");
    expect(hook).toContain("status === 'CHANNEL_ERROR'");
  });

  it('partage le flux sécurisé InputMessage dans la page principale', () => {
    const page = lire('src/pages/PageMessagerie.tsx');
    const input = lire('src/components/messagerie/InputMessage.tsx');
    const inline = lire('src/components/ChatConversation.tsx');

    expect(page).toContain('useConversationRealtime({');
    expect(page).toContain('<InputMessage');
    expect(page).toContain('key={selectedConv.id}');
    expect(page).toContain('conversationId={selectedConv.id}');
    expect(page).toContain("Est en train d'écrire…");
    expect(page).not.toContain("rpc('fn_envoyer_message'");
    expect(page).not.toContain('envoyerMessageAvecAntiFuite');
    expect(page).toContain('const selectedConvId = convParam');
    expect(page).toContain('const showMobileChat = !!selectedConv');
    expect(page).toContain(".order('cree_le', { ascending: false })");
    expect(page).toContain('messagesRecents =');
    expect(page).toContain('confirmerMessageEnvoye');
    expect(page).toContain('.reverse()');
    expect(page).toContain('.limit(99)');
    expect(inline).toContain('key={convId}');
    expect(inline).toContain(".order('cree_le', { ascending: false })");
    expect(inline).toContain('setConvId(null)');
    expect(inline).toContain('setMessages([])');
    expect(inline).toContain('onSent={confirmerMessageEnvoye}');
    expect(input).toContain('TYPING_REFRESH_MS');
    expect(input).toContain('lastTypingSentAtRef');
    expect(input).toContain('envoiRef.current');
    expect(input).toContain('e.nativeEvent.isComposing');
  });

  it('sérialise la dernière revalidation avant insertion du message', () => {
    const migration = lire(
      'supabase/migrations/20260714090000_borner_creation_conversations.sql',
    );
    const debut = migration.indexOf(
      'CREATE OR REPLACE FUNCTION private.fn_envoyer_message_interne',
    );
    const fin = migration.indexOf(
      'REVOKE ALL ON FUNCTION private.fn_envoyer_message_interne',
      debut,
    );
    const fonctionEnvoi = migration.slice(debut, fin);

    expect(debut).toBeGreaterThanOrEqual(0);
    expect(fonctionEnvoi).toContain('FOR UPDATE');
    expect(fonctionEnvoi).toContain('FOR SHARE');
    expect(fonctionEnvoi.indexOf('FOR UPDATE'))
      .toBeLessThan(fonctionEnvoi.indexOf('INSERT INTO public.messages_chat'));
    expect(fonctionEnvoi.indexOf('FOR SHARE'))
      .toBeLessThan(fonctionEnvoi.indexOf('INSERT INTO public.messages_chat'));
  });

  it('ferme les canaux directs historiques sans supprimer leurs données', () => {
    const racine = process.cwd();
    expect(existsSync(resolve(racine, 'src/components/ChatMission.tsx'))).toBe(false);
    expect(existsSync(resolve(
      racine,
      'src/components/admin/AdminMissionChatPanel.tsx',
    ))).toBe(false);

    const fermeture = lire(
      'supabase/migrations/20260714095000_fermer_canal_mission_legacy.sql',
    );
    const rpc = lire(
      'supabase/migrations/20260714096000_securiser_messages_contact_litige.sql',
    );
    const litige = lire('src/components/FilDiscussionLitige.tsx');
    const contact = lire('src/components/ModalContacterJolene.tsx');
    const adminContact = lire('src/pages/admin/AdminMessagesContact.tsx');

    expect(fermeture).toContain('REVOKE ALL ON TABLE public.messages_mission');
    expect(fermeture).toContain('REVOKE INSERT ON TABLE public.messages_litige');
    expect(rpc).toContain('INSERT INTO public.messages_litige');
    expect(rpc).toContain('fn_ajouter_message_litige');
    expect(rpc).toContain("'contrats', l.etablissement_id");
    expect(rpc).toContain("'/soignant/litiges?litige=' || v_litige.id::text");
    expect(rpc).toContain("'/etablissement/litiges?litige=' || v_litige.id::text");
    expect(rpc).not.toContain("'/soignant/mes-missions/'");
    expect(litige).toContain("rpc('fn_ajouter_message_litige'");
    expect(litige).not.toMatch(/from\(['"]messages_litige['"]\)[\s\S]{0,120}\.insert\(/);
    expect(contact).toContain("rpc('fn_envoyer_message_contact'");
    expect(adminContact).toContain("'fn_admin_traiter_message_contact'");
    expect(adminContact).not.toMatch(/from\(['"]messages_contact['"]\)[\s\S]{0,120}\.update\(/);
  });
});
