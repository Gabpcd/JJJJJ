import { beforeEach, describe, expect, it, vi } from 'vitest';
import { etatRetourConnect, lireSuiviRemboursementConnect, presentationRemboursementConnect, validerSuiviRemboursementConnect } from './suiviRemboursementConnect';

const mock = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mock.rpc } }));
const session = 'cs_test_exacte';
const suivi = () => ({ facture_honoraire_id: 'fh', mission_id: 'mission', checkout_session_id_filtre: session,
  source: 'CONNECT_AVANT_TRANSFERT', visibilite_montants: 'TOTAL_ETABLISSEMENT', paiement_statut: 'ECHOUE', lecture_complete: true,
  operations: [{ id: 'op', checkout_session_id: session, statut: 'REVIEW', montant_honoraires_centimes: 8000, montant_commission_centimes: 1200,
    montant_total_centimes: 9200, cree_le: '2026-10-01T12:00:00Z', mis_a_jour_le: null, succeeded_at: '2026-10-01T12:05:00Z', review_code: 'RETURNED' }],
});

describe('Suivi exact du remboursement Connect', () => {
  beforeEach(() => vi.resetAllMocks());
  it('une confirmation ancienne ne masque jamais le retour bancaire courant', () => {
    const lu = validerSuiviRemboursementConnect(suivi(), 'fh', session);
    expect(etatRetourConnect(lu)).toBe('REMBOURSEMENT');
    expect(presentationRemboursementConnect(lu.operations[0])).toEqual(expect.objectContaining({ ton: 'incident', titre: 'Vérification nécessaire' }));
  });
  it.each(['READY', 'PENDING', 'REQUIRES_ACTION', 'FAILED', 'CANCELED', 'REVIEW'])('ne présente pas %s comme remboursé, même avec une ancienne date de succès', statut => {
    const brut = suivi(); brut.operations[0].statut = statut;
    const lu = validerSuiviRemboursementConnect(brut, 'fh', session);
    expect(presentationRemboursementConnect(lu.operations[0]).ton).not.toBe('succes');
    expect(etatRetourConnect(lu)).toBe('REMBOURSEMENT');
  });
  it.each([
    (v: any) => { v.facture_honoraire_id = 'autre'; },
    (v: any) => { v.checkout_session_id_filtre = 'cs_test_autre'; },
    (v: any) => { v.operations[0].checkout_session_id = 'cs_test_autre'; },
    (v: any) => { v.lecture_complete = false; },
    (v: any) => { v.operations.push({ ...v.operations[0], id: 'autre' }); },
    (v: any) => { v.operations[0].montant_total_centimes = 9199; },
    (v: any) => { v.operations[0].montant_honoraires_centimes = '8000'; },
    (v: any) => { v.operations[0].statut = 'CONNU_NULLE_PART'; },
    (v: any) => { v.operations[0].statut = 'SUCCEEDED'; v.operations[0].succeeded_at = null; },
    (v: any) => { v.operations[0].statut = 'SUCCEEDED'; v.operations[0].review_code = 'BANK_RETURN'; },
    (v: any) => { v.visibilite_montants = 'HONORAIRES'; },
  ])('refuse une réponse incohérente avant affichage %#', modifier => {
    const brut = suivi(); modifier(brut);
    expect(() => validerSuiviRemboursementConnect(brut, 'fh', session)).toThrow('incomplet ou incohérent');
  });
  it('accepte les honoraires seuls sans transformer le champ commission masqué en zéro', () => {
    const brut: any = suivi(); brut.visibilite_montants = 'HONORAIRES';
    brut.operations[0].montant_commission_centimes = null; brut.operations[0].montant_total_centimes = null;
    const lu = validerSuiviRemboursementConnect(brut, 'fh', session);
    expect(lu.operations[0].montant_honoraires_centimes).toBe(8000);
    expect(lu.operations[0].montant_total_centimes).toBeNull();
  });
  it('une lecture historique sans Session ne confirme pas le retour d’un paiement', () => {
    const brut: any = suivi(); brut.checkout_session_id_filtre = null; brut.paiement_statut = null;
    expect(etatRetourConnect(validerSuiviRemboursementConnect(brut, 'fh'))).toBe('A_VERIFIER');
    brut.paiement_statut = 'PAYE';
    expect(() => validerSuiviRemboursementConnect(brut, 'fh')).toThrow();
  });
  it('un ancien statut REMBOURSE sans opération vérifiée reste à vérifier', () => {
    const brut = suivi(); brut.operations = []; brut.paiement_statut = 'REMBOURSE';
    expect(etatRetourConnect(validerSuiviRemboursementConnect(brut, 'fh', session))).toBe('A_VERIFIER');
  });
  it('ne consulte que la RPC en lecture avec les références exactes', async () => {
    mock.rpc.mockResolvedValue({ data: suivi(), error: null });
    await lireSuiviRemboursementConnect('fh', session);
    expect(mock.rpc).toHaveBeenCalledTimes(1);
    expect(mock.rpc).toHaveBeenCalledWith('fn_suivi_remboursements_connect_facture', { p_facture_honoraire_id: 'fh', p_checkout_session_id: session });
  });
  it('ne transforme ni une erreur RLS ni un payload vide en absence de remboursement', async () => {
    mock.rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } }).mockResolvedValueOnce({ data: null, error: null });
    await expect(lireSuiviRemboursementConnect('fh', session)).rejects.toMatchObject({ code: '42501' });
    await expect(lireSuiviRemboursementConnect('fh', session)).rejects.toThrow();
  });
});
