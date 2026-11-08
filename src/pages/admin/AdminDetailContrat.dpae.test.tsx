import { render, screen } from '@testing-library/react';
import { beforeEach, expect, it, vi } from 'vitest';
import AdminDetailContrat from './AdminDetailContrat';

// Carte DPAE du détail admin d'un contrat : CDDU et VACATION sont des contrats
// salariés (DPAE obligatoire, C. trav. art. L.1221-10), le remplacement libéral
// n'en a pas. Décision du 08/11/2026.
const mocks = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('react-router-dom', async importOriginal => ({ ...(await importOriginal<any>()), useParams: () => ({ id: 'contrat-admin' }), useNavigate: () => vi.fn() }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: vi.fn() }) }));
vi.mock('@/components/LayoutAdmin', () => ({ LayoutAdmin: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/admin/ChargementAdmin', () => ({ ChargementAdmin: () => <p>Chargement admin</p> }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));

const detail = (type: string, dpae: { numero: string | null; le: string | null }) => ({
  id: 'contrat-admin', numero_contrat: `SIM-ADMIN-${type}`, mission_id: 'mission-admin', mission_intitule: 'Mission fictive',
  mission_debut_le: '2026-09-24T07:00:00Z', mission_fin_le: '2026-09-24T15:00:00Z', soignant_id: 'soignant-admin',
  soignant_nom: 'Camille Recette', soignant_email: 'soignant@example.invalid', soignant_rpps: null,
  etablissement_id: 'etab-admin', etablissement_nom: 'Clinique Simulation', etablissement_siret: null,
  type_contrat: type, statut: 'SIGNE_COMPLET', mode_signature: 'OTP', hash_document: null,
  signature_soignant: true, signature_soignant_le: null, signature_ip_soignant: null, signature_navigateur_soignant: null,
  signature_etablissement: true, signature_etablissement_le: null, signature_ip_etablissement: null, signature_navigateur_etablissement: null,
  dpae_effectuee: !!dpae.numero, dpae_effectuee_le: dpae.le, dpae_numero: dpae.numero,
  storage_path: null, pdf_cle_s3: null, cree_le: '2026-09-24T06:55:00Z',
});

beforeEach(() => { mocks.rpc.mockReset(); });

async function afficher(type: string, dpae = { numero: null as string | null, le: null as string | null }) {
  mocks.rpc.mockResolvedValue({ data: { success: true, contrat: detail(type, dpae), signatures: [], audit_trail: [] }, error: null });
  render(<AdminDetailContrat />);
  await screen.findByRole('heading', { name: `SIM-ADMIN-${type}` });
  expect(mocks.rpc).toHaveBeenCalledWith('fn_admin_detail_contrat', { p_contrat_id: 'contrat-admin' });
}

it.each(['CDD', 'SALARIE', 'CDDU', 'VACATION'])('un contrat %s affiche la carte DPAE en attente', async type => {
  await afficher(type);
  expect(screen.getByRole('heading', { name: 'DPAE', level: 2 })).toBeInTheDocument();
  expect(screen.getByText('⏳ DPAE non encore transmise / numéro non saisi.')).toBeInTheDocument();
});

it.each(['CDDU', 'VACATION'])('un contrat %s déclaré affiche le numéro URSSAF', async type => {
  await afficher(type, { numero: '2026ABC123', le: '2026-09-24T08:00:00Z' });
  expect(screen.getByText('DPAE validée le 24 sept. 2026')).toBeInTheDocument();
  expect(screen.getByText('N° URSSAF : 2026ABC123')).toBeInTheDocument();
});

it('un remplacement libéral n’affiche pas de carte DPAE', async () => {
  await afficher('REMPLACEMENT_LIBERAL');
  expect(screen.queryByRole('heading', { name: 'DPAE', level: 2 })).not.toBeInTheDocument();
  expect(screen.queryByText(/DPAE/)).not.toBeInTheDocument();
});
