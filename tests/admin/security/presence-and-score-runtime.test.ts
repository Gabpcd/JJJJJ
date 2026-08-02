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

describe('état du système administrateur', () => {
  it('calcule le dernier run de tous les crons en un seul scan exact', () => {
    const migration = read(
      'supabase/migrations/20260801230000_accelerer_admin_health_check.sql',
    );

    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.fn_check_crons_health()');
    expect(migration).toContain('WITH latest_ids AS MATERIALIZED');
    expect(migration).toMatch(/SELECT r\.jobid, pg_catalog\.max\(r\.runid\) AS runid/);
    expect(migration).toContain('LEFT JOIN cron.job_run_details d ON d.runid = l.runid');
    expect(migration).not.toMatch(/ORDER BY\s+end_time\s+DESC\s+LIMIT\s+1/i);
    expect(migration).not.toMatch(/CREATE\s+(?:UNIQUE\s+)?INDEX/i);
    expect(migration).not.toMatch(/SET\s+(?:LOCAL\s+)?statement_timeout/i);
    expect(migration).toContain("i.signature = 'fn_check_crons_health()'");
  });
});
