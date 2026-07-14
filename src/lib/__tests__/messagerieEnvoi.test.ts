import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  invoke: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    functions: { invoke: mocks.invoke },
  },
}));

import { envoyerMessageAvecAntiFuite } from '@/lib/messagerieEnvoi';

describe('envoyerMessageAvecAntiFuite', () => {
  beforeEach(() => {
    mocks.invoke.mockReset();
  });

  it('effectue un seul appel Edge avec le texte littéral', async () => {
    mocks.invoke.mockResolvedValue({
      data: { success: true, message_id: 'message-1' },
      error: null,
    });

    await expect(envoyerMessageAvecAntiFuite(
      'conversation-1',
      'A & B et 1 < 2',
    )).resolves.toEqual({
      success: true,
      messageId: 'message-1',
      error: undefined,
      detectedType: undefined,
    });
    expect(mocks.invoke).toHaveBeenCalledTimes(1);
    expect(mocks.invoke).toHaveBeenCalledWith('messagerie-validate', {
      body: {
        conversation_id: 'conversation-1',
        content: 'A & B et 1 < 2',
      },
    });
  });

  it('refuse un succès sans identifiant de message confirmé', async () => {
    mocks.invoke.mockResolvedValue({
      data: { success: true },
      error: null,
    });

    await expect(envoyerMessageAvecAntiFuite(
      'conversation-1',
      'Bonjour',
    )).resolves.toMatchObject({
      success: false,
      error: 'REPONSE_ENVOI_INVALIDE',
    });
  });

  it('lit le JSON de FunctionsHttpError lorsque context est une Response', async () => {
    const context = new Response(JSON.stringify({
      success: false,
      error: 'ANTI_LEAK_REFUSE',
      detected_type: 'TELEPHONE',
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
    mocks.invoke.mockResolvedValue({
      data: null,
      error: { name: 'FunctionsHttpError', context },
    });

    const result = await envoyerMessageAvecAntiFuite(
      'conversation-1',
      'Appelez-moi au 06 12 34 56 78',
    );

    expect(result.success).toBe(false);
    expect(result.error).toBe('ANTI_LEAK_REFUSE');
    expect(result.detectedType).toBe('TELEPHONE');
    expect(context.bodyUsed).toBe(false);
  });

  it('retourne une erreur stable quand le transport ne fournit aucun JSON', async () => {
    const transportError = new Error('network down');
    mocks.invoke.mockResolvedValue({ data: null, error: transportError });

    await expect(envoyerMessageAvecAntiFuite(
      'conversation-1',
      'Bonjour',
    )).resolves.toMatchObject({
      success: false,
      error: 'VALIDATION_INDISPONIBLE',
      transportError,
    });
  });
});
