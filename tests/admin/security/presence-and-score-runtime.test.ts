import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(path, 'utf8');

describe('présence messagerie et score établissement', () => {
  it('appelle la RPC de score avec son argument réel', () => {
    const badge = read('src/components/BadgeScoreEtabPublic.tsx');

    expect(badge).toContain("supabase.rpc('fn_score_etab_public', { p_etab_id: etablissementId })");
    expect(badge).not.toContain('p_etablissement_id: etablissementId');
  });

  it('permet la lecture RLS sans exposer le helper private', () => {
    const migration = read(
      'supabase/migrations/20260801222000_reparer_lecture_presence_messagerie.sql',
    );

    expect(migration).toContain('CREATE POLICY pol_presence_status_select');
    expect(migration).toContain('user_id = (SELECT auth.uid())');
    expect(migration).toContain('c.participant_1_id');
    expect(migration).toContain('c.participant_2_id');
    expect(migration).toContain('c.soignant_id');
    expect(migration).toContain('public.fn_conversation_accessible(c.id)');
    expect(migration).not.toContain('GRANT EXECUTE ON FUNCTION private.');
    expect(migration).not.toMatch(/USING \([\s\S]*private\.fn_interlocuteur_operationnel_actif/);
  });

  it('ne modifie jamais les accusés de lecture pendant une observation admin', () => {
    const detail = read('src/pages/DetailMission.tsx');
    const chat = read('src/components/ChatConversation.tsx');
    const migration = read(
      'supabase/migrations/20260801222000_reparer_lecture_presence_messagerie.sql',
    );
    expect(detail).toContain('marquerCommeLu={!isAdmin}');
    expect(chat).toContain('marquerCommeLu = true');
    expect(chat).toContain('if (marquerCommeLu)');
    expect(chat).toContain('if (marquerCommeLu && msg.auteur_id !== user?.id)');
    expect(migration).toContain('IF public.est_admin() THEN');
    expect(migration).toContain('AND v_uid IN (v_conv.participant_1_id, v_conv.participant_2_id)');
    expect(migration).toContain('AND auteur_id <> v_uid');
    expect(migration).toMatch(/IF public\.est_admin\(\) THEN[\s\S]*?RETURN;[\s\S]*?IF v_conv\.etablissement_id/);
  });
});
