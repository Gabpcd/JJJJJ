import { readFileSync } from 'node:fs';
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

  it('garde le RPC strictement limité aux participants et sans accès anonyme', () => {
    const migration = readFileSync(
      resolve(
        process.cwd(),
        'supabase/migrations/20260713165631_resoudre_interlocuteurs_messagerie.sql',
      ),
      'utf8',
    );

    expect(migration).toContain('c.participant_1_id = v_uid');
    expect(migration).toContain('c.participant_2_id = v_uid');
    expect(migration).toContain('OR public.est_admin()');
    expect(migration).toContain("IF v_uid IS NULL THEN");
    expect(migration).toContain('IF NOT public.fn_compte_auth_actif() THEN');
    expect(migration).toContain('e0.id = p.participant_id');
    expect(migration).toContain(
      'REVOKE ALL ON FUNCTION public.fn_interlocuteurs_conversations(uuid[]) FROM PUBLIC, anon, service_role;',
    );
    expect(migration).toContain(
      'GRANT EXECUTE ON FUNCTION public.fn_interlocuteurs_conversations(uuid[]) TO authenticated;',
    );
    expect(migration).toContain('IF cardinality(p_conversation_ids) > 100 THEN');
  });
});
