import React, { useState, useEffect, useMemo } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { handleErrorSilent } from '@/lib/handleError';
import { useNavigate } from 'react-router-dom';
import { AlertCircle, Camera, Clock, CheckCircle2, RefreshCw, Loader2, Landmark } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { JaugeProgression } from '@/components/JaugeProgression';
import { ModalTeleversement } from '@/components/ModalTeleversement';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { ConfettiMini } from '@/components/ConfettiMini';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { TYPES_DOCUMENTS, TYPES_DOCUMENTS_EXCLUS_UPLOAD, STATUTS_VERIFICATION } from '@/lib/documents';
import { extraireMessageErreur } from '@/lib/erreurs';
import { format, differenceInDays } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

function AttestationSante({ userId }: { userId: string }) {
  const [checkVaccin, setCheckVaccin] = useState(false);
  const [checkMedecine, setCheckMedecine] = useState(false);
  const [signing, setSigning] = useState(false);
  const [signedAt, setSignedAt] = useState<string | null>(null);

  useEffect(() => {
    // Charger l'attestation existante
    supabase.from('soignants')
      .select('attestation_sante_signee_le')
      .eq('id', userId)
      .maybeSingle()
      .then(({ data }) => {
        if (data && (data as any).attestation_sante_signee_le) {
          setSignedAt((data as any).attestation_sante_signee_le);
          setCheckVaccin(true);
          setCheckMedecine(true);
        }
      }).then(undefined, (err) => handleErrorSilent(err, 'DocumentsSoignant.attestation'));
  }, [userId]);

  const signer = async () => {
    setSigning(true);
    const { data, error } = await supabase.rpc('fn_signer_attestation_sante' as any);
    if (error) {
      toast.error('Erreur lors de la signature. Veuillez réessayer.');
      handleErrorSilent(error, 'Signature attestation santé');
    } else {
      setSignedAt(new Date().toISOString());
      toast.success('Attestation signée avec succès !');
      // Audit
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: userId, p_type_acteur: 'SOIGNANT',
        p_action: 'ATTESTATION_SANTE_SIGNEE',
        p_type_ressource: 'soignant', p_id_ressource: userId,
        p_cle_s3: null, p_details: { vaccinations: true, medecine_travail: true },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
    }
    setSigning(false);
  };

  const canSign = checkVaccin && checkMedecine && !signedAt;

  return (
    <div className="card-base mb-6">
      <div className="flex items-center gap-2 mb-3">
        <span className="text-lg">📋</span>
        <h2 className="text-base font-bold text-foreground">Attestation sur l'honneur</h2>
        {signedAt && (
          <span className="ml-auto inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-emerald-100 text-emerald-700 text-xs font-semibold">
            <CheckCircle2 className="h-3.5 w-3.5" /> Signée
          </span>
        )}
      </div>

      <div className="space-y-3 mb-4">
        <label className="flex items-start gap-3 cursor-pointer group">
          <input
            type="checkbox"
            checked={checkVaccin}
            onChange={(e) => !signedAt && setCheckVaccin(e.target.checked)}
            disabled={!!signedAt}
            className="h-4 w-4 rounded border-border text-primary focus:ring-primary accent-primary mt-0.5 shrink-0"
          />
          <span className="text-sm text-foreground leading-snug">
            J'atteste sur l'honneur que mes vaccinations obligatoires sont à jour conformément aux recommandations du calendrier vaccinal en vigueur et aux obligations de mon établissement d'exercice.
          </span>
        </label>

        <label className="flex items-start gap-3 cursor-pointer group">
          <input
            type="checkbox"
            checked={checkMedecine}
            onChange={(e) => !signedAt && setCheckMedecine(e.target.checked)}
            disabled={!!signedAt}
            className="h-4 w-4 rounded border-border text-primary focus:ring-primary accent-primary mt-0.5 shrink-0"
          />
          <span className="text-sm text-foreground leading-snug">
            J'atteste sur l'honneur avoir bénéficié d'une visite d'information et de prévention (médecine du travail) dans les délais réglementaires.
          </span>
        </label>
      </div>

      <p className="text-xs text-muted-foreground mb-4 italic">
        Je reconnais que toute fausse déclaration est passible de poursuites (Art. 441-7 du Code pénal).
      </p>

      {signedAt ? (
        <div className="bg-emerald-50 border border-emerald-200 rounded-xl p-3 text-center">
          <p className="text-sm text-emerald-700 font-medium">
            ✅ Attestation signée le {format(new Date(signedAt), 'd MMMM yyyy', { locale: fr })}
          </p>
        </div>
      ) : (
        <button
          onClick={signer}
          disabled={!canSign || signing}
          className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {signing ? 'Signature en cours…' : '✅ Signer mon attestation'}
        </button>
      )}

      <p className="text-[11px] text-muted-foreground mt-3 leading-relaxed">
        Les documents originaux (carnet de vaccination, attestation de médecine du travail) sont vérifiés par l'établissement lors de votre première mission. Jolene ne stocke aucune donnée de santé.
      </p>
    </div>
  );
}

export default function DocumentsSoignant() {
  usePageTitle('Documents');
  return (
    <LayoutApp role="SOIGNANT">
      <DocumentsSoignantContent />
    </LayoutApp>
  );
}

export function DocumentsSoignantContent() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [soignant, setSoignant] = useState<any>(null);
  const [documentsRequis, setDocumentsRequis] = useState<any[]>([]);
  const [mesDocuments, setMesDocuments] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [reverifyingId, setReverifyingId] = useState<string | null>(null);

  // Modal state
  const [televersementType, setTeleversementType] = useState<string | null>(null);
  const [suppDocId, setSuppDocId] = useState<string | null>(null);

  // Verdict IA inline : ids des documents fraîchement téléversés dont la
  // vérification automatique est en cours (spinner sur la carte + polling léger).
  const [docsEnVerification, setDocsEnVerification] = useState<string[]>([]);
  const [confettiActif, setConfettiActif] = useState(false);

  const charger = async () => {
    if (!user) return;
    const [{ data: sg }, { data: dr }, { data: md }] = await Promise.all([
      supabase.from('soignants').select('profession, prenom, nom, type_exercice, rpps_verifie, adeli_verifie').eq('id', user.id).maybeSingle(),
      supabase.from('documents_requis_par_profession').select('id, profession, type_document, description, a_expiration, duree_validite_mois, est_critique, type_exercice_requis'),
      supabase.from('documents_soignants').select('id, soignant_id, type_document, nom_fichier, statut_verification, valide_depuis, valide_jusqua, televerse_le, motif_rejet, est_critique, s3_cle, s3_bucket, type_mime, taille_octets, libelle').eq('soignant_id', user.id).is('supprime_le', null).order('televerse_le', { ascending: false }),
    ]);
    if (sg) {
      setSoignant(sg);
      // Filtrage par profession ET type_exercice :
      // LIBERAL/MIXTE → inclut les documents LIBERAL_ONLY (RCP/RIB/URSSAF)
      // SALARIE/MIXTE/CDD/autre → inclut les documents SALARIE_ONLY
      // → un MIXTE cumule LES DEUX (obligations salariées + libérales).
      const estLiberal = (sg as any).type_exercice === 'LIBERAL' || (sg as any).type_exercice === 'MIXTE';
      const estSalarie = (sg as any).type_exercice !== 'LIBERAL'; // SALARIE + MIXTE + null/CDD
      const rppsVerifie = !!(sg as any).rpps_verifie;
      const adeliVerifie = !!(sg as any).adeli_verifie;
      const identiteVerifiee = rppsVerifie || adeliVerifie;
      setDocumentsRequis(
        (dr || []).filter((d: any) => {
          if (d.profession !== (sg as any).profession) return false;
          if (TYPES_DOCUMENTS_EXCLUS_UPLOAD.includes(d.type_document)) return false;
          if (identiteVerifiee && d.type_document === 'DIPLOME') return false;
          if (identiteVerifiee && d.type_document === 'RPPS_ADELI') return false;
          const exReq = d.type_exercice_requis || 'TOUS';
          if (exReq === 'LIBERAL_ONLY') return estLiberal;
          if (exReq === 'SALARIE_ONLY') return estSalarie;
          return true; // TOUS
        })
      );
    }
    setMesDocuments(md || []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user]);

  const docsRequis = useMemo(() => documentsRequis.filter(d => d.est_critique), [documentsRequis]);
  const docsValides = useMemo(() => docsRequis.filter(r =>
    mesDocuments.some(d =>
      d.type_document === r.type_document &&
      d.statut_verification === 'VERIFIE' &&
      (!d.valide_jusqua || new Date(d.valide_jusqua) > new Date())
    )
  ), [docsRequis, mesDocuments]);

  const docsManquants = docsRequis.length - docsValides.length;
  // Prochaine étape de la checklist : premier document obligatoire sans version valide
  const prochainDocRequis = useMemo(
    () => docsRequis.find(r => !docsValides.some(v => v.type_document === r.type_document)) ?? null,
    [docsRequis, docsValides]
  );

  // Polling léger pendant la vérification IA : recharge toutes les 5 s, 60 s max.
  const verificationActive = docsEnVerification.length > 0;
  useEffect(() => {
    if (!verificationActive) return;
    const interval = window.setInterval(() => { charger(); }, 5000);
    const timeout = window.setTimeout(() => setDocsEnVerification([]), 60000);
    return () => { window.clearInterval(interval); window.clearTimeout(timeout); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [verificationActive]);

  // Verdict IA inline : dès qu'un document suivi quitte EN_ATTENTE, on arrête son
  // suivi puis on enchaîne sur l'étape suivante (checklist) ou on célèbre le 100 %.
  useEffect(() => {
    if (docsEnVerification.length === 0) return;
    const termines = mesDocuments.filter(d => docsEnVerification.includes(d.id) && d.statut_verification !== 'EN_ATTENTE');
    if (termines.length === 0) return;
    setDocsEnVerification(prev => prev.filter(id => !termines.some(t => t.id === id)));
    if (termines.some(t => t.statut_verification === 'VERIFIE')) {
      const prochain = docsRequis.find(r => !mesDocuments.some(d =>
        d.type_document === r.type_document &&
        d.statut_verification === 'VERIFIE' &&
        (!d.valide_jusqua || new Date(d.valide_jusqua) > new Date())
      ));
      if (!prochain) {
        // Tous les documents obligatoires sont validés : confetti léger
        setConfettiActif(true);
        window.setTimeout(() => setConfettiActif(false), 2500);
      } else {
        // Enchaînement automatique sur le document suivant (si aucune modal ouverte)
        setTeleversementType(prev => prev ?? prochain.type_document);
      }
    }
  }, [mesDocuments, docsEnVerification, docsRequis]);

  const documentsExpirantBientot = useMemo(() => mesDocuments.filter(d =>
    d.valide_jusqua && d.statut_verification === 'VERIFIE' &&
    new Date(d.valide_jusqua) > new Date() &&
    differenceInDays(new Date(d.valide_jusqua), new Date()) < 30
  ), [mesDocuments]);

  // Cross-validation: check name coherence across documents + expiry
  const [incoherenceMessage, setIncoherenceMessage] = useState<string | null>(null);
  useEffect(() => {
    if (!user || mesDocuments.length === 0) return;
    // Check expiry locally
    const issues: string[] = [];
    const rcpDoc = mesDocuments.find(d => d.type_document === 'RCP_ASSURANCE' && d.statut_verification === 'VERIFIE');
    if (rcpDoc?.valide_jusqua && new Date(rcpDoc.valide_jusqua) < new Date()) {
      issues.push('Votre assurance RCP est expirée');
    }
    // Check AI name coherence via RPC
    (supabase.rpc('fn_verifier_coherence_documents' as any) as any).then(({ data }: any) => {
      if (data && !data.coherent && data.problemes?.length > 0) {
        const nameIssues = (data.problemes as string[]).join('. ');
        setIncoherenceMessage([...issues, nameIssues].filter(Boolean).join('. ') || null);
      } else {
        setIncoherenceMessage(issues.length > 0 ? issues.join('. ') + '.' : null);
      }
    }).then(undefined, () => {
      setIncoherenceMessage(issues.length > 0 ? issues.join('. ') + '.' : null);
    });
  }, [user, mesDocuments]);

  const reverifier = async (docId: string) => {
    setReverifyingId(docId);
    try {
      const { data: verifyData, error: verifyError } = await supabase.functions.invoke('verify-document', {
        body: { document_id: docId },
      });
      if (verifyError) {
        toast.error('Erreur lors de la revérification.');
        handleErrorSilent(verifyError, 'Revérification document');
      } else if (verifyData?.verdict === 'VERIFIE') {
        toast.success('✅ Document vérifié automatiquement !');
      } else if (verifyData?.verdict === 'REJETE') {
        toast.error(`❌ Document rejeté : ${verifyData?.analysis?.motif_rejet || 'Non conforme'}`);
      } else {
        toast.info('⏳ Vérification en cours de traitement...');
      }
      await charger();
    } catch (err) {
      handleErrorSilent(err, 'Revérification document');
      toast.error('Erreur lors de la revérification.');
    } finally {
      setReverifyingId(null);
    }
  };

  const televerser = async (fichierOriginal: File, libelle: string) => {
    if (!user || !televersementType) return;

    if (fichierOriginal.size > 10 * 1024 * 1024) {
      toast.error('Fichier trop volumineux. Maximum : 10 Mo.');
      return;
    }

    let fichier = fichierOriginal;
    if (/^image\/hei[cf]$/i.test(fichier.type) || /\.hei[cf]$/i.test(fichier.name)) {
      try {
        const bitmap = await createImageBitmap(fichier);
        const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
        const ctx = canvas.getContext('2d')!;
        ctx.drawImage(bitmap, 0, 0);
        const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality: 0.92 });
        fichier = new File([blob], fichier.name.replace(/\.hei[cf]$/i, '.jpg'), { type: 'image/jpeg' });
        bitmap.close();
      } catch {
        toast.error('Impossible de convertir le fichier HEIC. Merci de le re-prendre en JPEG.');
        return;
      }
    }

    const nomSanitise = fichier.name
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^\w.-]+/g, '-');
    const chemin = `${user.id}/documents/${televersementType}/${Date.now()}-${nomSanitise}`;
    const { error: uploadError } = await supabase.storage
      .from('jolene-documents')
      .upload(chemin, fichier, { contentType: fichier.type || undefined, upsert: false });
    if (uploadError) {
      toast.error(`Téléversement impossible : ${extraireMessageErreur(uploadError)}`);
      return;
    }

    const docReqData = documentsRequis.find(d => d.type_document === televersementType);
    const insertData: any = {
      soignant_id: user.id,
      type_document: televersementType as any,
      libelle: libelle || null,
      s3_bucket: 'jolene-documents',
      s3_cle: chemin,
      nom_fichier: fichier.name,
      type_mime: fichier.type,
      taille_octets: fichier.size,
      // Dates de validité extraites automatiquement par l'IA (verify-document) —
      // plus de saisie manuelle (colonnes nullables).
      valide_depuis: null,
      valide_jusqua: null,
      est_critique: docReqData?.est_critique || false,
      statut_verification: 'EN_ATTENTE',
      verifie_par: null,
      verifie_le: null,
      motif_rejet: null,
    };

    const { data, error } = await supabase.from('documents_soignants').insert(insertData).select().single();

    if (error) {
      await supabase.storage.from('jolene-documents').remove([chemin]);
      toast.error(extraireMessageErreur(error));
      return;
    }

    const docId = (data as any).id;

    const { error: auditError } = await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'SOIGNANT', p_action: 'DOCUMENT_TELEVERSEMENT',
      p_type_ressource: 'document', p_id_ressource: docId, p_cle_s3: chemin,
      p_details: { type_document: televersementType, nom_fichier: fichier.name, taille: fichier.size },
      p_ip: null, p_navigateur: navigator.userAgent,
    });
    if (auditError) handleErrorSilent(auditError, 'Audit téléversement document');

    // Verdict affiché inline sur la carte du document (spinner → Vérifié/Rejeté)
    setDocsEnVerification(prev => [...prev, docId]);

    supabase.functions.invoke('verify-document', {
      body: { document_id: docId },
    }).then(({ error: verifyError }) => {
      if (verifyError) {
        handleErrorSilent(verifyError, 'Vérification automatique document');
        setDocsEnVerification(prev => prev.filter(id => id !== docId));
        toast.info('Document téléversé. Vérification manuelle en attente.');
      }
      charger();
    }).then(undefined, (err: any) => {
      handleErrorSilent(err, 'Vérification automatique document');
      setDocsEnVerification(prev => prev.filter(id => id !== docId));
      toast.info('Document téléversé. Vérification manuelle en attente.');
    });

    toast.success('Document téléversé — vérification en cours (~30 s).');
    setTeleversementType(null);
    charger();
  };

  const voirDocument = async (doc: any) => {
    const previewWindow = window.open('', '_blank');

    try {
      const { data, error } = await supabase.storage
        .from(doc.s3_bucket || 'jolene-documents')
        .createSignedUrl(doc.s3_cle, 3600);

      if (error || !data?.signedUrl) {
        throw error || new Error('Signed URL absente');
      }

      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: 'SOIGNANT', p_action: 'DOCUMENT_CONSULTATION',
        p_type_ressource: 'document', p_id_ressource: doc.id, p_cle_s3: doc.s3_cle,
        p_details: { type_document: doc.type_document }, p_ip: null, p_navigateur: navigator.userAgent,
      });

      if (previewWindow) {
        previewWindow.location.href = data.signedUrl;
        return;
      }

      window.open(data.signedUrl, '_blank');
    } catch (error) {
      if (previewWindow) previewWindow.close();
      toast.error('Impossible d’ouvrir le document');
      handleErrorSilent(error, 'Consultation document');
    }
  };

  const supprimerDocument = async () => {
    if (!suppDocId || !user) return;
    await supabase.from('documents_soignants').update({ supprime_le: new Date().toISOString() } as any).eq('id', suppDocId);
    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'SOIGNANT', p_action: 'DOCUMENT_SUPPRESSION',
      p_type_ressource: 'document', p_id_ressource: suppDocId, p_cle_s3: null,
      p_details: {}, p_ip: null, p_navigateur: navigator.userAgent,
    });
    toast.success('Document supprimé.');
    setSuppDocId(null);
    charger();
  };

  if (loading) return <ChargementPage />;

  // Organize: critiques first, then optionnels
  const typesOrdonnes = [
    ...documentsRequis.filter(d => d.est_critique),
    ...documentsRequis.filter(d => !d.est_critique),
  ];

  return (
    <>
      {/* Bandeau profil incomplet — pas de docs requis si profession inconnue */}
      {!soignant?.profession && (
        <div className="rounded-xl border border-info/30 bg-info/5 p-3 mb-4 flex items-start gap-3">
          <AlertCircle className="h-5 w-5 text-info shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-medium text-foreground">Profession non définie</p>
            <p className="text-xs text-muted-foreground mt-0.5">
              Vérifiez votre RPPS dans votre profil pour voir les documents requis pour votre profession.
            </p>
            <BoutonY2K variant="secondary" size="sm" className="mt-2" onClick={() => navigate('/soignant/profil')}>
              Vérifier mon RPPS →
            </BoutonY2K>
          </div>
        </div>
      )}

      {/* Hero checklist — l'action suivante d'abord (Session E activation) */}
      {soignant?.profession && (docsManquants > 0 ? (
        <div className="rounded-2xl border border-jolene-rose-200/60 bg-gradient-soft p-4 mb-4">
          <h2 className="text-base font-bold text-foreground">
            Il vous reste {docsManquants} document{docsManquants > 1 ? 's' : ''} — ~3 min, une photo suffit
          </h2>
          {prochainDocRequis && (
            <>
              <p className="text-sm text-muted-foreground mt-1">
                Prochaine étape : <span className="font-semibold text-foreground">{TYPES_DOCUMENTS[prochainDocRequis.type_document] || prochainDocRequis.type_document}</span>
              </p>
              <BoutonY2K
                variant="primary"
                size="md"
                className="w-full mt-3"
                iconeGauche={<Camera className="h-4 w-4" />}
                onClick={() => setTeleversementType(prochainDocRequis.type_document)}
              >
                Téléverser — {TYPES_DOCUMENTS[prochainDocRequis.type_document] || prochainDocRequis.type_document}
              </BoutonY2K>
            </>
          )}
          <div className="mt-3">
            <JaugeProgression valeur={docsValides.length} max={docsRequis.length} />
          </div>
          <p className="text-xs text-muted-foreground mt-2">
            Vous pouvez postuler dès maintenant — validez vos documents pour être accepté par les établissements.
          </p>
        </div>
      ) : (
        <div className="relative overflow-hidden rounded-2xl bg-emerald-50 border border-emerald-200 p-4 mb-4 text-center">
          <ConfettiMini active={confettiActif} count={14} />
          <Mascotte etat="celebrating" taille="sm" className="mx-auto" />
          <p className="text-sm font-semibold text-emerald-700 mt-1">Tous vos documents obligatoires sont à jour 🎉</p>
          <p className="text-xs text-emerald-700/80 mt-1">Vous pouvez postuler et être accepté sur toutes les missions.</p>
        </div>
      ))}

      {/* Alertes expiration */}
      {documentsExpirantBientot.map(d => (
        <div key={d.id} className="bg-destructive/5 border border-destructive/20 rounded-xl p-3 mb-3 flex items-start gap-2">
          <Clock className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
          <p className="text-xs text-destructive">
            ⏰ Votre {TYPES_DOCUMENTS[d.type_document] || d.type_document} expire dans {differenceInDays(new Date(d.valide_jusqua), new Date())} jours ({format(new Date(d.valide_jusqua), 'd MMM yyyy', { locale: fr })}).{' '}
            <button onClick={() => setTeleversementType(d.type_document)} className="text-primary font-medium hover:underline">Mettre à jour →</button>
          </p>
        </div>
      ))}

      {/* RCP obligatoire seulement LIBERAL/MIXTE */}
      {(() => {
        const isLiberalOrMixte = soignant?.type_exercice === 'LIBERAL' || soignant?.type_exercice === 'MIXTE';
        if (!isLiberalOrMixte) return null;
        const rcpDoc = mesDocuments.find(d => d.type_document === 'RCP_ASSURANCE');
        const rcpExpired = rcpDoc?.valide_jusqua && new Date(rcpDoc.valide_jusqua) < new Date();
        const rcpMissing = !rcpDoc || rcpDoc.statut_verification !== 'VERIFIE';
        if (rcpExpired) {
          return (
            <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-3 mb-4 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
              <div>
                <p className="text-xs text-destructive font-medium">Votre assurance RCP est expirée. Veuillez la renouveler.</p>
                <p className="text-xs text-destructive mt-0.5">Vous ne pouvez pas postuler aux missions libérales tant que votre RCP n'est pas à jour.</p>
              </div>
            </div>
          );
        }
        if (rcpMissing) {
          return (
            <div className="bg-amber-50 border border-amber-200 rounded-xl p-3 mb-4 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 text-amber-600 shrink-0 mt-0.5" />
              <p className="text-xs text-amber-700">
                L'assurance RCP est obligatoire pour l'exercice libéral et mixte. Veuillez téléverser votre attestation RCP.
              </p>
            </div>
          );
        }
        return null;
      })()}

      {/* Cross-validation banner */}
      {incoherenceMessage && (
        <div className="bg-amber-50 border border-amber-300 rounded-xl p-3 mb-4 flex items-start gap-2">
          <AlertCircle className="h-4 w-4 text-amber-600 shrink-0 mt-0.5" />
          <p className="text-xs text-amber-700">
            ⚠️ Incohérence détectée entre vos documents : {incoherenceMessage} Veuillez vérifier que tous vos documents sont à jour et au même nom.
          </p>
        </div>
      )}

      {/* Liste des documents */}
      <div className="space-y-3">
        {typesOrdonnes.map((requis, idx) => {
          const isCritique = requis.est_critique;
          const doc = mesDocuments.find(d => d.type_document === requis.type_document);
          const estRejete = doc?.statut_verification === 'REJETE';
          // REJETE prime sur EXPIRE : un document rejeté reste rejeté même si
          // l'IA a extrait une date_expiration passée du mauvais fichier.
          const estExpire = !estRejete && doc?.valide_jusqua && new Date(doc.valide_jusqua) < new Date();
          const enVerification = !!doc && (docsEnVerification.includes(doc.id) || reverifyingId === doc.id);

          // Divider avant les optionnels (fix : index sur typesOrdonnes, pas documentsRequis)
          if (idx > 0 && !isCritique && typesOrdonnes[idx - 1]?.est_critique) {
            return (
              <React.Fragment key={requis.type_document}>
                <div className="border-t border-border my-4" />
                <p className="text-xs text-muted-foreground font-semibold uppercase tracking-wide mb-2">Documents optionnels</p>
                {renderCard()}
              </React.Fragment>
            );
          }
          return <React.Fragment key={requis.type_document}>{renderCard()}</React.Fragment>;

          function renderCard() {
            return (
              <div className="card-base">
                <div className="flex items-start justify-between mb-1">
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      {isCritique && <span className="badge-base bg-destructive/10 text-destructive text-[10px]">★ OBLIGATOIRE</span>}
                      <h3 className="font-semibold text-sm text-foreground">{TYPES_DOCUMENTS[requis.type_document]}</h3>
                    </div>
                    {requis.description && <p className="text-xs text-muted-foreground mt-0.5">{requis.description}</p>}
                  </div>
                </div>

                {doc && !estExpire && !estRejete ? (
                  <div className="mt-2">
                    <p className="text-xs text-muted-foreground">📎 {doc.nom_fichier} (téléversé le {format(new Date(doc.televerse_le), 'd MMM yyyy', { locale: fr })})</p>
                    {/* Enhanced status badge */}
                    {doc.statut_verification === 'VERIFIE' && (
                      <span className="inline-flex items-center gap-1 badge-base bg-emerald-100 text-emerald-700 text-[10px] mt-1">
                        <CheckCircle2 className="h-3 w-3" /> Vérifié ✅
                      </span>
                    )}
                    {doc.statut_verification === 'EN_ATTENTE' && (
                      <span className="inline-flex items-center gap-1 badge-base bg-amber-100 text-amber-700 text-[10px] mt-1">
                        <Loader2 className="h-3 w-3 animate-spin" /> {enVerification ? 'Vérification en cours (~30 s)' : 'En attente de vérification ⏳'}
                      </span>
                    )}
                    {doc.statut_verification === 'REVUE_MANUELLE_REQUISE' && (
                      <span className="inline-flex items-center gap-1 badge-base bg-blue-100 text-blue-700 text-[10px] mt-1">
                        <Clock className="h-3 w-3" /> En cours de vérification
                      </span>
                    )}
                    {doc.statut_verification === 'API_INDISPONIBLE' && (
                      <span className="inline-flex items-center gap-1 badge-base bg-muted text-muted-foreground text-[10px] mt-1">
                        Vérification temporairement indisponible
                      </span>
                    )}
                    {doc.valide_depuis && (
                      <p className="text-[10px] text-muted-foreground mt-1">Délivré le {format(new Date(doc.valide_depuis), 'd MMM yyyy', { locale: fr })}</p>
                    )}
                    {doc.valide_jusqua && (
                      <p className="text-[10px] text-muted-foreground mt-1">Valide jusqu'au {format(new Date(doc.valide_jusqua), 'd MMM yyyy', { locale: fr })}</p>
                    )}
                    <div className="flex gap-2 mt-2">
                      <button onClick={() => voirDocument(doc)} className="text-xs text-primary font-medium hover:underline">Voir le document</button>
                      {doc.statut_verification !== 'VERIFIE' && (
                        <button
                          onClick={() => reverifier(doc.id)}
                          disabled={reverifyingId === doc.id}
                          className="inline-flex items-center gap-1 text-xs text-primary font-medium hover:underline disabled:opacity-50"
                        >
                          {reverifyingId === doc.id ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />}
                          Revérifier
                        </button>
                      )}
                      <button onClick={() => setTeleversementType(requis.type_document)} className="text-xs text-primary font-medium hover:underline">Remplacer</button>
                      <button onClick={() => setSuppDocId(doc.id)} className="text-xs text-destructive font-medium hover:underline">Supprimer</button>
                    </div>
                  </div>
                ) : estRejete ? (
                  <div className="mt-2">
                    {enVerification ? (
                      <span className="inline-flex items-center gap-1 badge-base bg-amber-100 text-amber-700 text-[10px]">
                        <Loader2 className="h-3 w-3 animate-spin" /> Vérification en cours (~30 s)
                      </span>
                    ) : (
                      <>
                        <p className="text-xs text-destructive">
                          Document non valide{doc.motif_rejet && ` — ${doc.motif_rejet}`}. Veuillez en téléverser un correct.
                        </p>
                        <BadgeY2K variant="error" size="sm" className="mt-1">Rejeté</BadgeY2K>
                      </>
                    )}
                    <div className="flex items-center gap-3 mt-2">
                      <button onClick={() => setTeleversementType(requis.type_document)} className="btn-primary text-xs px-3 py-1.5">Réessayer</button>
                      <button
                        onClick={() => reverifier(doc.id)}
                        disabled={reverifyingId === doc.id}
                        className="inline-flex items-center gap-1 text-xs text-primary font-medium hover:underline disabled:opacity-50"
                      >
                        {reverifyingId === doc.id ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />}
                        Revérifier
                      </button>
                    </div>
                  </div>
                ) : estExpire ? (
                  <div className="mt-2">
                    <p className="text-xs text-amber-600">Document expiré depuis le {format(new Date(doc.valide_jusqua), 'd MMM yyyy', { locale: fr })}. Veuillez en téléverser un récent.</p>
                    <BadgeY2K variant="warning" size="sm" className="mt-1">Expiré</BadgeY2K>
                    <div className="flex items-center gap-3 mt-2">
                      <button onClick={() => setTeleversementType(requis.type_document)} className="btn-primary text-xs px-3 py-1.5">Téléverser un nouveau document</button>
                      <button
                        onClick={() => reverifier(doc.id)}
                        disabled={reverifyingId === doc.id}
                        className="inline-flex items-center gap-1 text-xs text-primary font-medium hover:underline disabled:opacity-50"
                      >
                        {reverifyingId === doc.id ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />}
                        Revérifier
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="mt-2">
                    <p className="text-xs text-amber-600">Document à téléverser — une photo suffit</p>
                    <div className="flex gap-2 mt-2">
                      <button onClick={() => setTeleversementType(requis.type_document)} className="btn-primary text-xs px-3 py-1.5">+ Téléverser</button>
                    </div>
                  </div>
                )}
              </div>
            );
          }
        })}
      </div>

      {/* Coordonnées bancaires (RIB) — le RIB n'est jamais un fichier à téléverser ici.
          - Libéral / mixte : honoraires versés via Stripe Connect (RIB saisi côté Stripe).
          - IBAN « primes de parrainage » : Profil → Paiements (jamais partagé avec l'étab).
          - Missions salariées : l'établissement est l'employeur légal et établit la paie. */}
      {soignant?.profession && (() => {
        const isLiberalOrMixte = soignant?.type_exercice === 'LIBERAL' || soignant?.type_exercice === 'MIXTE';
        return (
          <div className="mt-6 rounded-2xl border border-jolene-rose-200/60 bg-card p-4">
            <div className="flex items-start gap-3">
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
                <Landmark className="h-5 w-5" />
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-sm font-semibold text-foreground">Coordonnées bancaires (RIB)</p>
                <p className="text-sm text-muted-foreground mt-1">
                  Le RIB ne se téléverse pas comme un document.
                </p>
                {isLiberalOrMixte ? (
                  <>
                    <p className="text-sm text-muted-foreground mt-1">
                      Pour vos <span className="font-medium text-foreground">honoraires libéraux</span>, le RIB est saisi de façon sécurisée lors de la configuration de votre compte de versement.
                    </p>
                    <BoutonY2K variant="secondary" size="sm" className="mt-3" onClick={() => navigate('/soignant/stripe-connect')}>
                      Configurer mes versements →
                    </BoutonY2K>
                  </>
                ) : (
                  <p className="text-sm text-muted-foreground mt-1">
                    Pour les <span className="font-medium text-foreground">missions salariées</span>, l'établissement est votre employeur et établit votre bulletin de paie. Votre IBAN pour les primes Jolene se renseigne dans <span className="font-medium text-foreground">Profil → Paiements</span>.
                  </p>
                )}
              </div>
            </div>
          </div>
        );
      })()}

      {/* Documents complémentaires — étudiant / interne faisant fonction */}
      {user && (() => {
        const docScol = mesDocuments.find((d) => d.type_document === 'ATTESTATION_SCOLARITE');
        const statScol = docScol ? STATUTS_VERIFICATION[docScol.statut_verification as string] : null;
        const docLic = mesDocuments.find((d) => d.type_document === 'LICENCE_REMPLACEMENT');
        const statLic = docLic ? STATUTS_VERIFICATION[docLic.statut_verification as string] : null;
        return (
          <div className="mt-6 space-y-2">
            <p className="text-xs text-muted-foreground font-semibold uppercase tracking-wide mb-2">Étudiant / interne en santé</p>
            <div className="card-base flex items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="text-sm font-medium text-foreground">🎓 Attestation de scolarité / passage en année supérieure</p>
                <p className="text-xs text-muted-foreground">
                  Étudiant ? L'IA vérifie votre niveau et débloque l'exercice « faisant fonction »
                  correspondant (ex : étudiant infirmier année 1 validée → aide-soignant).
                </p>
                {docScol && statScol && (
                  <span className={`inline-block mt-1.5 text-[11px] px-2 py-0.5 rounded-full ${statScol.couleur}`}>{statScol.label}</span>
                )}
              </div>
              <button onClick={() => setTeleversementType('ATTESTATION_SCOLARITE')} className="btn-primary text-xs px-3 py-1.5 shrink-0">
                {docScol ? 'Remplacer' : '+ Téléverser'}
              </button>
            </div>
            <div className="card-base flex items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="text-sm font-medium text-foreground">🩺 Licence de remplacement (interne en médecine)</p>
                <p className="text-xs text-muted-foreground">
                  Interne ? Téléversez votre licence de remplacement (Conseil de l'Ordre) :
                  l'IA la vérifie et débloque les remplacements de médecin.
                </p>
                {docLic && statLic && (
                  <span className={`inline-block mt-1.5 text-[11px] px-2 py-0.5 rounded-full ${statLic.couleur}`}>{statLic.label}</span>
                )}
              </div>
              <button onClick={() => setTeleversementType('LICENCE_REMPLACEMENT')} className="btn-primary text-xs px-3 py-1.5 shrink-0">
                {docLic ? 'Remplacer' : '+ Téléverser'}
              </button>
            </div>
          </div>
        );
      })()}

      {/* Attestation sur l'honneur — fin de parcours, après les téléversements */}
      {user && (
        <div className="mt-6">
          <p className="text-xs text-muted-foreground font-semibold uppercase tracking-wide mb-2">Dernière étape</p>
          <AttestationSante userId={user.id} />
        </div>
      )}

      {/* Modal televersement */}
      {televersementType && (
        <ModalTeleversement
          typeDocument={televersementType}
          onConfirmer={televerser}
          onFermer={() => setTeleversementType(null)}
        />
      )}

      {/* Modal suppression */}
      <ModalConfirmation
        ouvert={!!suppDocId}
        onFermer={() => setSuppDocId(null)}
        onConfirmer={supprimerDocument}
        titre="Supprimer ce document ?"
        message="Le document sera archivé. Vous pourrez en téléverser un nouveau."
        labelConfirmer="Supprimer"
        variante="danger"
      />
    </>
  );
}
