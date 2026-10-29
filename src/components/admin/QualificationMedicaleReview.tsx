import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { SelectSpecialiteMedicale } from '@/components/SelectSpecialiteMedicale';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { extraireMessageErreur } from '@/lib/erreurs';

type Proof = { id: string; nom_fichier: string; statut: string; empreinte: string; s3_bucket: string; s3_cle: string };
type Review = {
  soignant_id: string; numero_rpps: string | null; rpps_verifie: boolean;
  documents: Proof[]; decision_id: string | null; decision_invalidee: boolean;
  qualification: { decision_id: string; specialite_code: string; specialite_label: string } | null;
};

/** The administrative decision is distinct from the generic document verdict. */
export function QualificationMedicaleReview({ soignantId }: { soignantId: string }) {
  const [review, setReview] = useState<Review | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [proofId, setProofId] = useState('');
  const [opened, setOpened] = useState('');
  const [specialty, setSpecialty] = useState('');
  const [rpps, setRpps] = useState('');
  const [registered, setRegistered] = useState(false);
  const [qualified, setQualified] = useState(false);
  const [revoke, setRevoke] = useState(false);
  const [reason, setReason] = useState('');
  const epoch = useRef(0);
  const proof = review?.documents.find(row => row.id === proofId);
  const resetConfirmation = () => { setOpened(''); setRegistered(false); setQualified(false); setRevoke(false); };
  const load = useCallback(async (generation: number) => {
    const { data, error } = await supabase.rpc('fn_admin_lire_qualification_medicale', { p_soignant_id: soignantId });
    if (epoch.current !== generation) return null;
    if (error || !data || (data as unknown as Review).soignant_id !== soignantId) throw error || new Error('Revue indisponible.');
    const next = data as unknown as Review;
    setReview(next); resetConfirmation();
    return next;
  }, [soignantId]);
  useEffect(() => {
    const generation = ++epoch.current;
    setReview(null); setBusy(true); setMessage(''); setProofId(''); setSpecialty(''); setRpps(''); setReason('');
    void load(generation).catch(error => {
      if (epoch.current === generation) setMessage(extraireMessageErreur(error));
    }).finally(() => { if (epoch.current === generation) setBusy(false); });
    return () => { ++epoch.current; };
  }, [load]);
  const refresh = async () => {
    const generation = epoch.current; setBusy(true); setMessage('');
    try { await load(generation); } catch (error) { if (epoch.current === generation) setMessage(extraireMessageErreur(error)); }
    finally { if (epoch.current === generation) setBusy(false); }
  };
  const viewProof = async () => {
    // Storage source and fingerprint must come from the same server snapshot.
    if (!proof?.s3_bucket || !proof.s3_cle) { setMessage('Rechargez la revue pour consulter cette preuve.'); return; }
    const preview = window.open('about:blank', '_blank');
    if (!preview) { setMessage('Autorisez l’ouverture de la pièce dans un nouvel onglet.'); return; }
    preview.opener = null;
    const generation = epoch.current; setBusy(true); setMessage('');
    try {
      const { data, error } = await supabase.storage.from(proof.s3_bucket).createSignedUrl(proof.s3_cle, 300);
      if (epoch.current !== generation) { preview.close(); return; }
      if (error || !data?.signedUrl) throw error || new Error('Pièce indisponible.');
      preview.location.replace(data.signedUrl); setOpened(proof.empreinte);
    } catch (error) { preview.close(); if (epoch.current === generation) setMessage(extraireMessageErreur(error)); }
    finally { if (epoch.current === generation) setBusy(false); }
  };
  const decide = async (action: 'approve' | 'revoke') => {
    if (!review || busy || (action === 'approve' && !proof) || (action === 'revoke' && !review.decision_id)) return;
    const generation = epoch.current; setBusy(true); setMessage('');
    try {
      const result = action === 'approve'
        ? await supabase.rpc('fn_admin_decider_qualification_medicale', {
          p_soignant_id: soignantId, p_document_id: proofId, p_preuve_empreinte: proof!.empreinte,
          p_decision_attendue: review.decision_id, p_specialite_code: specialty, p_numero_rpps_lu: rpps.trim(),
          p_inscription_confirmee: registered, p_qualification_confirmee: qualified, p_motif: reason.trim(),
        })
        : await supabase.rpc('fn_admin_revoquer_qualification_medicale', {
          p_soignant_id: soignantId, p_decision_id: review.decision_id!, p_motif: reason.trim(),
        });
      if (epoch.current !== generation) return;
      if (result.error) throw result.error;
      const fresh = await load(generation);
      if (!fresh) return;
      if (action === 'approve' && fresh.qualification?.specialite_code !== specialty
        || action === 'revoke' && fresh.decision_id !== null) throw new Error('Le résultat n’est pas confirmé par la relecture. Actualisez la revue.');
      setMessage(action === 'approve' ? 'Qualification enregistrée et relue. Le parcours a été mis à jour.' : 'Décision révoquée et état relu.');
    } catch (error) {
      if (epoch.current === generation) {
        resetConfirmation();
        setMessage(`${extraireMessageErreur(error)} Rechargez la revue avant toute autre décision.`);
      }
    } finally { if (epoch.current === generation) setBusy(false); }
  };
  const canApprove = !busy && review?.rpps_verifie && proof?.statut === 'VERIFIE'
    && opened === proof?.empreinte && registered && qualified && specialty && rpps.trim()
    && reason.trim().length >= 20 && reason.trim().length <= 1000;
  return <section className="rounded-xl border border-border bg-card p-4 space-y-4" aria-label="Qualification après internat">
    <div className="flex flex-wrap justify-between gap-2"><h3 className="font-semibold">Qualification après internat</h3>
      <BoutonY2K variant="secondary" size="sm" disabled={busy} onClick={() => void refresh()}>Actualiser la revue</BoutonY2K></div>
    <p className="text-sm text-muted-foreground">Vérifiez une attestation actuelle d’inscription au tableau de l’Ordre précisant la qualification du médecin. Le RPPS vérifié ou une carte d’étudiant seuls ne permettent pas cette décision.</p>
    {review?.qualification && <p role="status" className="text-sm">Qualification confirmée : {review.qualification.specialite_label}.</p>}
    {review?.decision_invalidee && <p role="alert" className="text-sm">La preuve ou l’identité a changé. L’ancienne décision est conservée mais n’ouvre plus le parcours de médecin qualifié.</p>}
    {message && <p role="status" className="text-sm break-words">{message}</p>}
    {review && <fieldset disabled={busy} className="space-y-4">
      <label className="block space-y-1"><span className="text-sm">Attestation examinée</span>
        <select className="input-base w-full min-h-11" value={proofId} onChange={event => { setProofId(event.target.value); resetConfirmation(); }}>
          <option value="">Choisir la pièce</option>{review.documents.map(doc => <option key={doc.id} value={doc.id}>{doc.nom_fichier} — {doc.statut}</option>)}
        </select></label>
      {review.documents.length === 0 && <p className="text-sm">Ajoutez une attestation d’inscription à l’Ordre ci-dessous, puis faites-la vérifier dans Modération.</p>}
      <BoutonY2K variant="secondary" disabled={!proof} onClick={() => void viewProof()}>Consulter l’attestation</BoutonY2K>
      <label className="block space-y-1"><span className="text-sm">RPPS lu sur l’attestation</span><Input value={rpps} onChange={event => setRpps(event.target.value)} inputMode="numeric" autoComplete="off" /></label>
      <div className="space-y-1"><p className="text-sm">Qualification exacte portée par l’attestation</p><SelectSpecialiteMedicale value={specialty} onChange={setSpecialty} professionParent="MEDECIN" disabled={busy} /></div>
      <label className="flex min-h-11 items-start gap-3 text-sm"><input type="checkbox" className="mt-1 h-5 w-5 shrink-0" checked={registered} onChange={event => setRegistered(event.target.checked)} />J’ai contrôlé l’inscription actuelle au tableau de l’Ordre et la concordance d’identité et de RPPS.</label>
      <label className="flex min-h-11 items-start gap-3 text-sm"><input type="checkbox" className="mt-1 h-5 w-5 shrink-0" checked={qualified} onChange={event => setQualified(event.target.checked)} />L’attestation établit la qualification sélectionnée, au-delà du statut d’étudiant ou de la licence de remplacement.</label>
      <label className="block space-y-1"><span className="text-sm">Motif documenté de la décision (20 à 1 000 caractères)</span><Textarea value={reason} onChange={event => setReason(event.target.value)} maxLength={1000} /></label>
      <BoutonY2K disabled={!canApprove} onClick={() => void decide('approve')}>Confirmer la qualification après internat</BoutonY2K>
      {review.decision_id && <div className="space-y-2 border-t pt-3">
        <label className="flex min-h-11 items-start gap-3 text-sm"><input type="checkbox" className="mt-1 h-5 w-5 shrink-0" checked={revoke} onChange={event => setRevoke(event.target.checked)} />Je confirme la révocation de cette décision, avec le motif saisi ci-dessus.</label>
        <BoutonY2K variant="destructive" disabled={!revoke || reason.trim().length < 20} onClick={() => void decide('revoke')}>Révoquer la décision de qualification</BoutonY2K>
      </div>}
    </fieldset>}
  </section>;
}
