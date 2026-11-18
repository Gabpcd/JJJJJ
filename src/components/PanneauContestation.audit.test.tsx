import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PanneauContestation } from './PanneauContestation';

// D13 (docs/mobile-swift/DECISIONS_LOT2.md ; RGPD art. 5 §1 c et e) :
// l'audit PRESENCE_CONTESTATION ne porte jamais le motif libre, seulement
// motif_longueur et litige_id, comme le natif (SupabaseContestationGateway).

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  maybeSingle: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => {
  const builder: Record<string, unknown> = {};
  for (const methode of ['select', 'eq', 'order', 'limit']) builder[methode] = () => builder;
  builder.maybeSingle = mocks.maybeSingle;
  return { supabase: { from: vi.fn(() => builder), rpc: mocks.rpc } };
});
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'utilisateur-1' } }) }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => ({ role: 'SOIGNANT' }) }));
vi.mock('@/lib/sentry', () => ({ capturerErreurSentry: vi.fn() }));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

// Accents et emoji : 49 points de code (50 unités UTF-16), comme les
// scalaires Unicode comptés par le natif.
const MOTIF = 'Arrivée à 7 h, départ à 19 h : 2 h non comptées 🙁';

function rendre(role: 'SOIGNANT' | 'ETABLISSEMENT') {
  return render(
    <PanneauContestation
      presenceId="presence-1"
      missionId="mission-1"
      etablissementId="etab-1"
      soignantId="soignant-1"
      presenceValideeLe={new Date(Date.now() - 3600 * 1000).toISOString()}
      role={role}
    />,
  );
}

describe('PanneauContestation — audit sans le motif libre (D13)', () => {
  beforeEach(() => {
    mocks.rpc.mockReset();
    mocks.maybeSingle.mockReset();
    mocks.maybeSingle.mockResolvedValue({ data: null, error: null });
    mocks.rpc.mockImplementation((nom: string) => {
      if (nom === 'fn_fenetre_contestation_ouverte') return Promise.resolve({ data: true, error: null });
      if (nom === 'fn_ouvrir_litige_rate_limited') {
        return Promise.resolve({
          data: { success: true, litige_id: 'litige-1', est_informatif: false, facture_id: null },
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: null });
    });
  });

  it.each([
    ['SOIGNANT', 'SOIGNANT'],
    ['ETABLISSEMENT', 'ADMIN_ETABLISSEMENT'],
  ] as const)('rôle %s : p_details = { motif_longueur, litige_id }, aucun fragment du motif', async (role, typeActeur) => {
    rendre(role);
    fireEvent.click(await screen.findByRole('button', { name: /Contester cette présence/ }));
    fireEvent.change(screen.getByRole('textbox'), { target: { value: MOTIF } });
    fireEvent.click(screen.getByRole('button', { name: /Envoyer la contestation/ }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_ecrire_audit_safe', expect.anything()));

    // Le motif part toujours au serveur pour le litige (litiges.motif).
    expect(mocks.rpc).toHaveBeenCalledWith('fn_ouvrir_litige_rate_limited', {
      p_mission_id: 'mission-1',
      p_type_litige: 'DESACCORD_HEURES_POINTAGE',
      p_motif: MOTIF,
    });

    const appelsAudit = mocks.rpc.mock.calls.filter(([nom]) => nom === 'fn_ecrire_audit_safe');
    expect(appelsAudit).toHaveLength(1);
    const audit = appelsAudit[0][1];
    expect(audit.p_action).toBe('PRESENCE_CONTESTATION');
    expect(audit.p_type_ressource).toBe('presence');
    expect(audit.p_id_ressource).toBe('presence-1');
    expect(audit.p_type_acteur).toBe(typeActeur);

    // Exactement les deux clés du natif, même forme (longueur en chaîne).
    expect(audit.p_details).toEqual({ motif_longueur: '49', litige_id: 'litige-1' });
    expect(Object.keys(audit.p_details).sort()).toEqual(['litige_id', 'motif_longueur']);
    expect(audit.p_details).not.toHaveProperty('motif');

    const corps = JSON.stringify(audit);
    expect(corps).not.toContain(MOTIF);
    for (const fragment of ['Arrivée', 'départ', 'comptées', '🙁']) {
      expect(corps).not.toContain(fragment);
    }
  });
});
