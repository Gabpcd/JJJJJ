import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import AdminEmails from './AdminEmails';
import AdminGroupes from './AdminGroupes';
import AdminEquipe from './AdminEquipe';
import AdminConfig from './AdminConfig';
import AdminTemplatesContrats from './AdminTemplatesContrats';
import AdminContrats from './AdminContrats';
import AdminSales from './AdminSales';
const m = vi.hoisted(() => ({ rpc: vi.fn(), query: vi.fn(), invoke: vi.fn(), success: vi.fn(), error: vi.fn(), notification: vi.fn() }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'admin-fictif' } }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: m.notification }) }));
vi.mock('@/components/LayoutAdmin', () => ({ LayoutAdmin: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/BreadcrumbAdmin', () => ({ BreadcrumbAdmin: () => null }));
vi.mock('@/components/admin/EditeurEquivalencesScolarite', () => ({ EditeurEquivalencesScolarite: () => null }));
vi.mock('@/components/ui/TableOuCartes', () => ({ TableOuCartes: ({ donnees, colonnes, renduCellule, getId }: any) => <div>{donnees.map((d: any) => <div key={getId(d)}>{colonnes.map((c: any) => <div key={c.cle}>{renduCellule(d, c)}</div>)}</div>)}</div> }));
vi.mock('sonner', () => ({ toast: { success: m.success, error: m.error } }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: m.rpc, functions: { invoke: m.invoke }, from: (table: string) => {
  const q: any = { then: (resolve: any, reject: any) => Promise.resolve(m.query(table)).then(resolve, reject) };
  for (const method of ['select', 'eq', 'in', 'is', 'order', 'limit', 'maybeSingle', 'range']) q[method] = () => q;
  return q;
} } }));
const afficher = (node: React.ReactNode) => render(<MemoryRouter>{node}</MemoryRouter>);
beforeEach(() => { vi.clearAllMocks(); m.query.mockResolvedValue({ data: [], error: null }); m.rpc.mockResolvedValue({ data: null, error: { message: '503' } }); });

describe('envois administrateur contrôlés', () => {
  it('libère le bouton après rejet réseau et réutilise sa clé au réessai', async () => {
    m.invoke.mockRejectedValueOnce(new TypeError('Failed to fetch')).mockResolvedValue({ data: { success: true }, error: null });
    afficher(<AdminEmails />);
    const bouton = screen.getByRole('button', { name: 'Envoyer un email test pour BIENVENUE_SOIGNANT' });
    fireEvent.click(bouton);
    await waitFor(() => expect(m.error).toHaveBeenCalled());
    expect(bouton).toBeEnabled();
    expect(m.success).not.toHaveBeenCalled();
    fireEvent.click(bouton);
    await waitFor(() => expect(m.success).toHaveBeenCalledWith('Email test envoyé à votre adresse'));
    expect(m.invoke.mock.calls[0][1].body.idempotency_key).toBe(m.invoke.mock.calls[1][1].body.idempotency_key);
    expect(m.invoke.mock.calls[1][1].body.destinataire_id).toBe('admin-fictif');
  });
  it.each([{ success: true, pending: true }, { success: true, skipped: true, reason: 'preference_user_off' }, { success: false }, null])('ne promet pas un email avec réponse %j', async data => {
    m.invoke.mockResolvedValue({ data, error: null });
    afficher(<AdminEmails />);
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer un email test pour BIENVENUE_SOIGNANT' }));
    await waitFor(() => expect(m.error).toHaveBeenCalled());
    expect(m.success).not.toHaveBeenCalled();
  });
  it('conserve le brouillon du groupe et reprend uniquement le destinataire non confirmé', async () => {
    m.query.mockImplementation((table: string) => ({ data: table === 'groupes_sante' ? [{ id: 'g', nom: 'Groupe test' }] : table === 'etablissements' ? ['a', 'b'].map(id => ({ id, nom: id, groupe_sante_id: 'g', email_contact: `${id}@example.invalid` })) : [], error: null }));
    m.invoke.mockResolvedValueOnce({ data: { success: true }, error: null }).mockResolvedValueOnce({ data: null, error: { message: '503' } }).mockResolvedValue({ data: { success: true }, error: null });
    afficher(<AdminGroupes />);
    fireEvent.click(await screen.findByRole('button', { name: 'Email au groupe' }));
    fireEvent.change(screen.getByLabelText('Sujet de l’email au groupe Groupe test'), { target: { value: 'Sujet conservé' } });
    fireEvent.change(screen.getByLabelText('Contenu de l’email au groupe Groupe test'), { target: { value: 'Contenu conservé' } });
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('1 envoi(s) confirmé(s) sur 2');
    expect(screen.getByLabelText('Contenu de l’email au groupe Groupe test')).toHaveValue('Contenu conservé');
    expect(m.success).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer' }));
    await waitFor(() => expect(m.success).toHaveBeenCalledWith('Email envoyé à 2 destinataire(s)'));
    expect(m.invoke.mock.calls.map(c => c[1].body.destinataire_email)).toEqual(['a@example.invalid', 'b@example.invalid', 'b@example.invalid']);
    expect(m.invoke.mock.calls[1][1].body.idempotency_key).toBe(m.invoke.mock.calls[2][1].body.idempotency_key);
  });
});
describe('lectures administrateur récupérables', () => {
  it.each([
    ['équipe', AdminEquipe, []], ['configuration', AdminConfig, []],
    ['templates', AdminTemplatesContrats, { success: true, templates: [] }],
    ['contrats', AdminContrats, { success: true, contrats: [], total: 0 }],
  ] as const)('%s : distingue 503 et liste réellement vide', async (_nom, Component, resultat) => {
    m.query.mockResolvedValue({ data: null, error: { message: '503' } });
    afficher(<Component />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Chargement impossible');
    m.query.mockResolvedValue({ data: [], error: null });
    m.rpc.mockResolvedValue({ data: resultat, error: null });
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await waitFor(() => expect(screen.queryByRole('alert')).toBeNull());
    await waitFor(() => expect(screen.queryByText('Chargement…')).toBeNull());
  });
  it('historique email : panne visible et réessai', async () => {
    m.query.mockResolvedValue({ data: null, error: { message: '503' } });
    afficher(<AdminEmails />);
    expect(await screen.findByRole('alert')).toHaveTextContent('historique');
    m.query.mockResolvedValue({ data: [], error: null });
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await waitFor(() => expect(screen.queryByRole('alert')).toBeNull());
  });
});


describe('copie commerciale', () => {
  it('attend le presse-papier, annonce le refus puis permet de réessayer', async () => {
    let refuser!: (raison: unknown) => void;
    const writeText = vi.fn().mockImplementationOnce(() => new Promise((_resolve, reject) => { refuser = reject; })).mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText } });
    m.rpc.mockImplementation((nom: string) => Promise.resolve({ data: nom === 'fn_admin_generer_posts' ? [{ profession: 'IDE', nb: 2, villes: 'Paris' }] : null, error: null }));
    render(<MemoryRouter initialEntries={['/admin/fondateur/sales?tab=posts']}><AdminSales /></MemoryRouter>);
    const boutons = await screen.findAllByRole('button', { name: 'Copier' });
    m.error.mockClear();
    fireEvent.click(boutons[0]);
    expect(writeText).toHaveBeenCalledTimes(1);
    expect(m.success).not.toHaveBeenCalled();
    refuser(new DOMException('Permission denied', 'NotAllowedError'));
    await waitFor(() => expect(m.error).toHaveBeenCalledWith('Impossible de copier le post. Réessayez ou sélectionnez le texte.'));
    expect(m.success).not.toHaveBeenCalled();
    fireEvent.click(boutons[0]);
    await waitFor(() => expect(m.success).toHaveBeenCalledWith('Post copié — collez-le dans le groupe.'));
  });
});
