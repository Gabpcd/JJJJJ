import React from 'react';
import { renderHook, waitFor, cleanup } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useActivationSoignant } from './ChecklistActivation';

const mocks = vi.hoisted(() => ({
  auth: { user: { id: 'fixture-specialite' } },
  from: vi.fn(), eq: vi.fn(),
  profession: 'IADE',
  diplomes: [] as Record<string, unknown>[],
  error: null as unknown,
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => mocks.auth }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mocks.from } }));

beforeEach(() => {
  vi.clearAllMocks(); mocks.profession = 'IADE'; mocks.diplomes = []; mocks.error = null;
  mocks.from.mockImplementation((table: string) => {
    const result = table === 'soignants' ? { data: { adeli_verifie: false }, error: null }
      : table === 'documents_requis_par_profession' ? { data: [{ profession: mocks.profession, type_document: 'DIPLOME', est_critique: true, type_exercice_requis: 'TOUS' }], error: null }
        : { data: mocks.diplomes, error: mocks.error };
    const q: Record<string, any> = {};
    q.select = () => q;
    q.eq = (name: string, value: unknown) => { mocks.eq(name, value); return q; };
    q.is = () => q;
    q.maybeSingle = () => Promise.resolve(result);
    q.then = (resolve: (r: unknown) => unknown, reject: (e: unknown) => unknown) => Promise.resolve(result).then(resolve, reject);
    return q;
  });
});
afterEach(cleanup);

function afficher() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } });
  const wrapper = ({ children }: { children: React.ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return renderHook(() => useActivationSoignant({
    soignant: { profession: mocks.profession, type_exercice: 'SALARIE', rpps_verifie: true, tous_documents_valides: true },
    documents: [{ type_document: 'DIPLOME', statut_verification: 'VERIFIE', valide_jusqua: null }],
    hasStripeConnect: false, aRib: true,
  }), { wrapper });
}

describe('Activation — diplôme spécialisé malgré cache historique et RPPS valide', () => {
  it.each(['IADE', 'IBODE'])('%s sans preuve exacte garde la reprise documents, sans perdre le RPPS', async profession => {
    mocks.profession = profession;
    mocks.diplomes = [{ statut_verification: 'VERIFIE', profession_certifiee: 'IDE', valide_jusqua: null }];
    const { result } = afficher();
    await waitFor(() => expect(result.current.etapes.find(e => e.id === 'documents')?.detail).toContain('Il te reste 1 document'));
    expect(result.current.etapes.find(e => e.id === 'rpps')?.faite).toBe(true);
    expect(result.current.etapes.find(e => e.id === 'documents')).toMatchObject({ faite: false, destination: '/soignant/mes-documents' });
    expect(mocks.eq).toHaveBeenCalledWith('soignant_id', 'fixture-specialite');
  });
  it.each(['IADE', 'IBODE'])('%s avec la preuve spécialisée vérifiée conserve la validation', async profession => {
    mocks.profession = profession;
    mocks.diplomes = [{ statut_verification: 'VERIFIE', profession_certifiee: profession, valide_jusqua: null }];
    const { result } = afficher();
    await waitFor(() => expect(result.current.etapes.find(e => e.id === 'documents')?.faite).toBe(true));
  });
  it('une panne de lecture ne confirme pas le cache historique', async () => {
    mocks.error = new Error('503');
    const { result } = afficher();
    await waitFor(() => expect(result.current.etapes.find(e => e.id === 'documents')?.detail).toContain('Il te reste 1 document'));
    expect(result.current.etapes.find(e => e.id === 'documents')?.faite).toBe(false);
  });
  it('IDE conserve sa dispense sans nouvelle lecture de diplôme', async () => {
    mocks.profession = 'IDE';
    const { result } = afficher();
    await waitFor(() => expect(result.current.etapes.find(e => e.id === 'documents')?.faite).toBe(true));
    expect(mocks.from).not.toHaveBeenCalledWith('documents_soignants');
  });
});
