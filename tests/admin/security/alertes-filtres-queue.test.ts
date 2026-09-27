import { beforeEach, describe, expect, it, vi } from 'vitest';
import { traiterAlerteFiltres, resultatEnvoiEmail } from '../../../supabase/functions/_shared/alertes-filtres-queue';

const email = { id: 'queue-1', type: 'NOUVEAUX_SOIGNANTS_FILTRE', destinataire_id: 'membre-rh', data: { count: 1, nom_filtre: 'IDE Paris', soignants: [{ id: 'profil-exact', prenom: 'Emma' }] } };
let rpc: ReturnType<typeof vi.fn>;
let update: ReturnType<typeof vi.fn>;
let sb: any;
beforeEach(() => {
 rpc = vi.fn().mockResolvedValue({ data: true, error: null });
 update = vi.fn().mockImplementation(() => {
  const q: any = { eq: vi.fn(() => q), select: vi.fn(() => q), maybeSingle: vi.fn().mockResolvedValue({ data: { id: email.id }, error: null }), then: (ok: any) => Promise.resolve({ error: null }).then(ok) };
  return q;
 });
 sb = { rpc, from: vi.fn(() => ({ update })) };
});
describe('transport durable des alertes filtrées', () => {
 it('envoie le lot exact sans recalculer un aperçu historique et marque le succès', async () => {
  const send = vi.fn().mockResolvedValue('sent');
  expect(await traiterAlerteFiltres(sb, email, send)).toBe('envoye');
  expect(send).toHaveBeenCalledWith({ type: email.type, destinataire_id: email.destinataire_id, destinataire_email: undefined, data: email.data });
  expect(rpc).toHaveBeenCalledTimes(1);
  expect(update).toHaveBeenCalledWith(expect.objectContaining({ statut: 'ENVOYE', envoye: true }));
 });
 it('planifie un réessai après panne transport, puis conserve le même contenu', async () => {
  const send = vi.fn().mockRejectedValueOnce(new Error('503')).mockResolvedValueOnce('sent');
  expect(await traiterAlerteFiltres(sb, email, send)).toBe('erreur');
  expect(rpc).toHaveBeenCalledWith('fn_reporter_echec_alerte_filtre', { p_email_id: email.id });
  expect(update).toHaveBeenCalledWith(expect.objectContaining({ statut: 'ERREUR' }));
  expect(await traiterAlerteFiltres(sb, email, send)).toBe('envoye');
  expect(send.mock.calls[0]).toEqual(send.mock.calls[1]);
 });
 it('garde pending sans faux succès et reprend après acquittement', async () => {
  const send = vi.fn().mockResolvedValueOnce('pending').mockResolvedValueOnce('sent');
  expect(await traiterAlerteFiltres(sb, email, send)).toBe('pending');
  expect(update).not.toHaveBeenCalled();
  expect(await traiterAlerteFiltres(sb, email, send)).toBe('envoye');
 });
 it('annule un destinataire ou résultat devenu interdit sans envoyer', async () => {
  rpc.mockResolvedValue({ data: false }); const send=vi.fn();
  expect(await traiterAlerteFiltres(sb, email, send)).toBe('annule');
  expect(send).not.toHaveBeenCalled(); expect(update).toHaveBeenCalledWith(expect.objectContaining({ statut: 'ANNULE' }));
 });
 it.each([{ error: { message: '503' } }, { data: null }])('ne confond pas panne de validation et annulation %j', async (result) => {
  rpc.mockResolvedValue(result); const send=vi.fn();
  await expect(traiterAlerteFiltres(sb,email,send)).rejects.toThrow('Validation');
  expect(send).not.toHaveBeenCalled();expect(update).not.toHaveBeenCalled();
 });
 it('ne classe pas en ERREUR un envoi confirmé dont le marquage a échoué', async () => {
  const q: any={ eq:()=>q,select:()=>q,maybeSingle:async()=>({error:{message:'503'}}) }; update.mockReturnValue(q);
  await expect(traiterAlerteFiltres(sb,email,vi.fn().mockResolvedValue('sent'))).rejects.toThrow('même identité');
  expect(update).toHaveBeenCalledTimes(1);
  expect(rpc).not.toHaveBeenCalledWith('fn_reporter_echec_alerte_filtre', expect.anything());
 });
});


describe('un transport ignoré ne compte pas comme un email envoyé',()=>{
 it.each(['preference_user_off','compte_test_e2e','test_source'])('ignore %s sans faux ENVOYE',async reason=>{
  const outcome=resultatEnvoiEmail({success:true,skipped:true,reason});
  expect(await traiterAlerteFiltres(sb,email,vi.fn().mockResolvedValue(outcome))).toBe('annule');
  expect(update).toHaveBeenCalledWith(expect.objectContaining({statut:'ANNULE',envoye:false,envoye_le:null}));
  expect(update).not.toHaveBeenCalledWith(expect.objectContaining({statut:'ENVOYE'}));
 });
 it('acquitte un email déjà envoyé par la même identité',async()=>{
  const outcome=resultatEnvoiEmail({success:true,skipped:true,reason:'idempotency_already_sent'});
  expect(await traiterAlerteFiltres(sb,email,vi.fn().mockResolvedValue(outcome))).toBe('envoye');
  expect(update).toHaveBeenCalledWith(expect.objectContaining({statut:'ENVOYE',envoye:true}));
 });
 it('ne traite pas une réponse sans succès comme un envoi',()=>{
  expect(()=>resultatEnvoiEmail({skipped:true})).toThrow();
 });
});
