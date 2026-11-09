import { act, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ContratMission from './ContratMission';

// Bloc DPAE et rappel DPAE de /contrat/:id selon le type de contrat : CDDU et
// VACATION sont des contrats salariés (DPAE obligatoire, C. trav. art. L.1221-10),
// le remplacement libéral n'en a pas. Décision du 08/11/2026.
const mocks = vi.hoisted(() => ({
  demandes: new Map<string, (v: any) => void>(),
  role: 'ADMIN_ETABLISSEMENT' as string,
  userId: 'etab-recette',
}));
vi.mock('react-router-dom', async importOriginal => ({ ...(await importOriginal<any>()), useParams: () => ({ id: 'contrat-dpae' }), useNavigate: () => vi.fn() }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: mocks.userId } }) }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => ({ role: mocks.role }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: vi.fn() }) }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/ChargementPage', () => ({ ChargementPage: () => <p>Chargement de recette</p> }));
vi.mock('@/components/Countdown72hSignature', () => ({ Countdown72hSignature: () => null }));
vi.mock('@/components/CertificatSignature', () => ({ CertificatSignature: () => null }));
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

const BLOC_DPAE = 'DPAE obligatoire — Mission salariée';
const RAPPEL_DPAE = /^⚠️ Rappel légal : effectuez la Déclaration Préalable à l'Embauche \(DPAE\)/;
const contrat = (type: string, signeParEtablissement: boolean) => ({
  id: 'contrat-dpae', mission_id: 'mission-recette', soignant_id: 'soignant-recette', etablissement_id: 'etab-recette',
  numero_contrat: 'contrat-dpae', type_contrat: type, cree_le: new Date().toISOString(),
  statut: signeParEtablissement ? 'SIGNE_ETABLISSEMENT' : 'EN_ATTENTE_SIGNATURES',
  signature_soignant: false, signature_etablissement: signeParEtablissement,
  dpae_effectuee: false, dpae_numero: null, hash_document: 'contrat-dpae', storage_path: 'recette.pdf',
  contenu_html: '<p>Contrat fictif de recette</p>',
});

beforeEach(() => { mocks.demandes.clear(); mocks.role = 'ADMIN_ETABLISSEMENT'; mocks.userId = 'etab-recette'; });

async function afficher(type: string, signeParEtablissement = false) {
  render(<ContratMission />);
  await act(async () => mocks.demandes.get('contrat-dpae')!({ data: contrat(type, signeParEtablissement), error: null }));
  await screen.findByRole('heading', { name: 'Contrat contrat-dpae' });
}

describe('établissement', () => {
  it.each(['CDD', 'CDDU', 'VACATION'])('un contrat %s propose la préparation DPAE avant signature', async type => {
    await afficher(type);
    expect(screen.getByText(BLOC_DPAE)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Préparer les données DPAE' })).toBeInTheDocument();
    expect(screen.queryByText(RAPPEL_DPAE)).not.toBeInTheDocument();
  });

  it.each(['CDD', 'CDDU', 'VACATION'])('un contrat %s signé par l’établissement affiche aussi le rappel DPAE', async type => {
    await afficher(type, true);
    expect(screen.getByText('✅ Vous avez déjà signé ce contrat')).toBeInTheDocument();
    expect(screen.getByText(BLOC_DPAE)).toBeInTheDocument();
    expect(screen.getByText(RAPPEL_DPAE)).toBeInTheDocument();
  });

  it.each([false, true])('un remplacement libéral n’affiche ni bloc ni rappel DPAE (signé : %s)', async signe => {
    await afficher('REMPLACEMENT_LIBERAL', signe);
    expect(screen.queryByText(BLOC_DPAE)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Préparer les données DPAE' })).not.toBeInTheDocument();
    expect(screen.queryByText(RAPPEL_DPAE)).not.toBeInTheDocument();
    expect(screen.queryByText(/DPAE/)).not.toBeInTheDocument();
  });
});

describe('soignant', () => {
  it.each(['CDDU', 'VACATION'])('un contrat %s ne lui confie ni la préparation ni le rappel DPAE de l’employeur', async type => {
    mocks.role = 'SOIGNANT';
    mocks.userId = 'soignant-recette';
    await afficher(type);
    expect(screen.queryByText(BLOC_DPAE)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Préparer les données DPAE' })).not.toBeInTheDocument();
    expect(screen.queryByText(RAPPEL_DPAE)).not.toBeInTheDocument();
    expect(screen.getByText(content => content.includes('Contrat salarié écrit — art. L.1242-12 du Code du travail.'))).toBeInTheDocument();
  });
});
