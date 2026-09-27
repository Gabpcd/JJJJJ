import { act, render, screen } from '@testing-library/react';
import { beforeEach, expect, it, vi } from 'vitest';
import ContratMission from './ContratMission';
const mocks = vi.hoisted(() => ({ id: 'contrat-a', demandes: new Map<string, (v: any) => void>(), notifier: vi.fn() }));
vi.mock('react-router-dom', async importOriginal => ({ ...(await importOriginal<any>()), useParams: () => ({ id: mocks.id }), useNavigate: () => vi.fn() }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'soignant-recette' } }) }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => ({ role: 'SOIGNANT' }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: mocks.notifier }) }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/ChargementPage', () => ({ ChargementPage: () => <p>Chargement de recette</p> }));
vi.mock('@/components/Countdown72hSignature', () => ({ Countdown72hSignature: () => null }));
vi.mock('@/components/SignerContratOtp', () => ({ SignerContratOtp: ({ contratId }: any) => <p>Signer {contratId}</p> }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: {
  rpc: vi.fn(async () => ({ data: { nom: 'Établissement de recette' }, error: null })),
  from: (table: string) => {
    let id = '';
    const query: any = { select: () => query, eq: (key: string, value: string) => { if (key === 'id') id = value; return query; },
      single: () => new Promise(resolve => { mocks.demandes.set(id, resolve); }),
      maybeSingle: async () => ({ data: table === 'soignants' ? { prenom: 'Camille', nom: 'Recette', est_compte_test: false } : table === 'etablissements' ? { id, est_compte_test: false } : {}, error: null }) };
    return query;
  },
} }));
const contrat = (id: string) => ({ id, mission_id: 'mission-recette', soignant_id: 'soignant-recette', etablissement_id: 'etab-recette', numero_contrat: id, type_contrat: 'LIBERAL', statut: 'EN_ATTENTE_SIGNATURES', cree_le: new Date().toISOString(), signature_soignant: false, signature_etablissement: false, hash_document: id, storage_path: 'recette.pdf', contenu_html: '<p>Contrat fictif de recette</p>' });
beforeEach(() => { mocks.id = 'contrat-a'; mocks.demandes.clear(); mocks.notifier.mockReset(); });
it('ignore une ancienne lecture arrivée après le contrat sélectionné ensuite', async () => {
  const { rerender } = render(<ContratMission />);
  expect(mocks.demandes.has('contrat-a')).toBe(true);
  mocks.id = 'contrat-b'; rerender(<ContratMission />);
  await act(async () => mocks.demandes.get('contrat-b')!({ data: contrat('contrat-b'), error: null }));
  expect(await screen.findByRole('heading', { name: 'Contrat contrat-b' })).toBeInTheDocument();
  await act(async () => mocks.demandes.get('contrat-a')!({ data: contrat('contrat-a'), error: null }));
  expect(screen.getByRole('heading', { name: 'Contrat contrat-b' })).toBeInTheDocument();
  expect(screen.queryByText('Signer contrat-a')).not.toBeInTheDocument();
  expect(screen.getByText('Signer contrat-b')).toBeInTheDocument();
});
