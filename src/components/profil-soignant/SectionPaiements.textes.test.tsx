import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { SectionPaiements } from './SectionPaiements';

// HARD STOP n°4 (revue B8 de #1142, DECISIONS_LOT3 TJ6) : deux phrases inexactes retirées des coordonnées bancaires.
// - « Il n'est jamais partagé avec l'établissement » : le RIB vérifié, qui porte l'IBAN enregistré
//   (fn_lier_iban_verifie_document), est remis à l'établissement quand un partage est actif
//   (fn_consulter_rib_soignant_internal_20260801).
// - « L'ancien IBAN est conservé dans ton historique… » : l'IBAN ne vit que dans soignants.iban_virement,
//   sans historique (fn_consulter_mon_iban).

const mocks = vi.hoisted(() => ({ rpc: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: mocks.rpc, functions: { invoke: vi.fn() } },
}));
vi.mock('sonner', () => ({ toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }) }));

const TEXTES_RETIRES = /jamais partagé|partagé avec l.établissement|historique|ancien IBAN/i;

const ETATS = {
  'aucun IBAN': { iban_renseigne: false, iban_verifie: false },
  'IBAN enregistré et vérifié': {
    iban_renseigne: true, iban_verifie: true, verification_requise: false, iban_last4: '0189', iban_titulaire: 'Marie Lefèvre',
  },
  'IBAN renseigné sans RIB vérifié': {
    iban_renseigne: true, iban_verifie: false, verification_requise: true, iban_last4: '0189', iban_titulaire: 'Marie Lefèvre',
  },
} as const;

function rendre() {
  return render(
    <MemoryRouter>
      <SectionPaiements
        userId="soignant-1"
        typeExercice="SALARIE"
        mandatFacturationSigne={null}
        mandatFacturationSigneLe={null}
        estCompteTest={false}
      />
    </MemoryRouter>,
  );
}

describe('SectionPaiements — coordonnées bancaires sans les deux affirmations inexactes (HARD STOP n°4)', () => {
  beforeEach(() => mocks.rpc.mockReset());

  it.each(Object.entries(ETATS))('état « %s » : ni partage nié ni historique annoncé', async (_nom, etat) => {
    mocks.rpc.mockResolvedValue({ data: etat, error: null });
    rendre();
    expect(await screen.findByRole('button', { name: /Enregistrer l'IBAN|Mettre à jour/ })).toBeInTheDocument();
    expect(mocks.rpc).toHaveBeenCalledWith('fn_consulter_mon_iban');

    expect(screen.getByText('Ton IBAN est utilisé pour le versement de tes primes de parrainage.')).toBeInTheDocument();
    expect(document.body.textContent).not.toMatch(TEXTES_RETIRES);
  });

  it('état « RIB vérifié requis » : le titre et l’action restent, sans texte d’explication', async () => {
    mocks.rpc.mockResolvedValue({ data: ETATS['IBAN renseigné sans RIB vérifié'], error: null });
    rendre();
    const titre = await screen.findByText('RIB vérifié requis');
    const bloc = titre.parentElement as HTMLElement;
    expect(bloc).toContainElement(screen.getByRole('button', { name: 'Téléverser mon RIB' }));
    expect(bloc.querySelectorAll('p')).toHaveLength(1);
    expect(bloc.textContent).toBe('RIB vérifié requisTéléverser mon RIB');
  });
});
