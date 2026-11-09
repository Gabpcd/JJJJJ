import { act, render, screen } from '@testing-library/react';
import { beforeEach, expect, it, vi } from 'vitest';
import ContratMission from './ContratMission';
import { TYPES_CONTRAT_SALARIES } from '@/lib/typesContrat';

// Mention du pied de page selon le type de contrat (décision de Gabrielle du 08/11/2026,
// HARD STOP n°4) : CDD, SALARIE, CDDU et VACATION sont des contrats salariés.
const mocks = vi.hoisted(() => ({ demandes: new Map<string, (v: any) => void>() }));
vi.mock('react-router-dom', async importOriginal => ({ ...(await importOriginal<any>()), useParams: () => ({ id: 'contrat-mention' }), useNavigate: () => vi.fn() }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'soignant-recette' } }) }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => ({ role: 'SOIGNANT' }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: vi.fn() }) }));
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

const MENTION_SALARIEE = 'Contrat salarié écrit — art. L.1242-12 du Code du travail.';
const MENTION_LIBERALE = 'Contrat de prestation entre l’établissement et le professionnel libéral.';
const contrat = (type: string) => ({ id: 'contrat-mention', mission_id: 'mission-recette', soignant_id: 'soignant-recette', etablissement_id: 'etab-recette', numero_contrat: 'contrat-mention', type_contrat: type, statut: 'EN_ATTENTE_SIGNATURES', cree_le: new Date().toISOString(), signature_soignant: false, signature_etablissement: false, hash_document: 'contrat-mention', storage_path: 'recette.pdf', contenu_html: '<p>Contrat fictif de recette</p>' });

beforeEach(() => { mocks.demandes.clear(); });

async function afficher(type: string) {
  render(<ContratMission />);
  await act(async () => mocks.demandes.get('contrat-mention')!({ data: contrat(type), error: null }));
  await screen.findByRole('heading', { name: 'Contrat contrat-mention' });
}

it('CDDU et VACATION sont des types salariés, comme CDD et SALARIE', () => {
  expect([...TYPES_CONTRAT_SALARIES].sort()).toEqual(['CDD', 'CDDU', 'SALARIE', 'VACATION']);
});

it.each(['CDD', 'SALARIE', 'CDDU', 'VACATION'])('un contrat %s porte la mention salariée, jamais la mention libérale', async type => {
  await afficher(type);
  expect(screen.getByText(content => content.includes(MENTION_SALARIEE))).toBeInTheDocument();
  expect(screen.queryByText(content => content.includes(MENTION_LIBERALE))).not.toBeInTheDocument();
});

it('un remplacement libéral garde la mention de prestation libérale', async () => {
  await afficher('REMPLACEMENT_LIBERAL');
  expect(screen.getByText(content => content.includes(MENTION_LIBERALE))).toBeInTheDocument();
  expect(screen.queryByText(content => content.includes(MENTION_SALARIEE))).not.toBeInTheDocument();
});
