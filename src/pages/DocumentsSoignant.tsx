import React, { useState, useEffect, useMemo } from 'react';
import { handleErrorSilent } from '@/lib/handleError';
import { useNavigate } from 'react-router-dom';
import { FolderOpen, AlertCircle, Clock, CheckCircle2 } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { JaugeProgression } from '@/components/JaugeProgression';
import { ModalTeleversement } from '@/components/ModalTeleversement';
import { ModalConfirmation } from '@/components/ModalConfirmation';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { TYPES_DOCUMENTS, STATUTS_VERIFICATION, TYPES_DOCUMENTS_EXCLUS_UPLOAD } from '@/lib/documents';
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
      .single()
      .then(({ data }) => {
        if (data && (data as any).attestation_sante_signee_le) {
          setSignedAt((data as any).attestation_sante_signee_le);
          setCheckVaccin(true);
          setCheckMedecine(true);
        }
      });
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
        Les documents originaux (carnet de vaccination, attestation de médecine du travail) sont vérifiés par l'établissement lors de votre première mission. Soin Direct ne stocke aucune donnée de santé.
      </p>
    </div>
  );
}

export default function DocumentsSoignant() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [soignant, setSoignant] = useState<any>(null);
  const [documentsRequis, setDocumentsRequis] = useState<any[]>([]);
  const [mesDocuments, setMesDocuments] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  // Modal state
  const [televersementType, setTeleversementType] = useState<string | null>(null);
  const [televersementExpiration, setTeleversementExpiration] = useState<boolean>(true);
  const [suppDocId, setSuppDocId] = useState<string | null>(null);

  const charger = async () => {
    if (!user) return;
    const [{ data: sg }, { data: dr }, { data: md }] = await Promise.all([
      supabase.from('soignants').select('profession').eq('id', user.id).single(),
      supabase.from('documents_requis_par_profession').select('*'),
      supabase.from('documents_soignants').select('*').eq('soignant_id', user.id).is('supprime_le', null).order('televerse_le', { ascending: false }),
    ]);
    if (sg) {
      setSoignant(sg);
      // Exclure les types gérés par attestation sur l'honneur
      setDocumentsRequis(
        (dr || []).filter((d: any) =>
          d.profession === (sg as any).profession &&
          !TYPES_DOCUMENTS_EXCLUS_UPLOAD.includes(d.type_document)
        )
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

  const completionDocs = docsRequis.length > 0 ? Math.round((docsValides.length / docsRequis.length) * 100) : 100;

  const documentsExpirantBientot = useMemo(() => mesDocuments.filter(d =>
    d.valide_jusqua && d.statut_verification === 'VERIFIE' &&
    new Date(d.valide_jusqua) > new Date() &&
    differenceInDays(new Date(d.valide_jusqua), new Date()) < 30
  ), [mesDocuments]);

  const televerser = async (fichier: File, libelle: string, valideDepuis: string, valideJusqua: string) => {
    if (!user || !televersementType) return;
    const chemin = `${user.id}/${televersementType}/${Date.now()}_${fichier.name}`;
    const { error: uploadError } = await supabase.storage.from('soin-direct-documents').upload(chemin, fichier, { contentType: fichier.type, upsert: false });
    if (uploadError) { toast.error('Erreur lors du téléversement. Veuillez réessayer.'); return; }

    const docReqData = documentsRequis.find(d => d.type_document === televersementType);
    const { data, error } = await supabase.from('documents_soignants').insert({
      soignant_id: user.id,
      type_document: televersementType as any,
      libelle: libelle || null,
      s3_bucket: 'soin-direct-documents',
      s3_cle: chemin,
      nom_fichier: fichier.name,
      type_mime: fichier.type,
      taille_octets: fichier.size,
      valide_depuis: valideDepuis || new Date().toISOString().split('T')[0],
      valide_jusqua: valideJusqua || null,
      est_critique: docReqData?.est_critique || false,
    } as any).select().single();

    if (error) { toast.error(extraireMessageErreur(error)); return; }

    const { error: auditError } = await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id, p_type_acteur: 'SOIGNANT', p_action: 'DOCUMENT_TELEVERSEMENT',
      p_type_ressource: 'document', p_id_ressource: (data as any).id, p_cle_s3: chemin,
      p_details: { type_document: televersementType, nom_fichier: fichier.name, taille: fichier.size },
      p_ip: null, p_navigateur: navigator.userAgent,
    });
    if (auditError) handleErrorSilent(auditError, 'Audit téléversement document');

    toast.success('Document téléversé avec succès !');
    setTeleversementType(null);
    charger();
  };

  const voirDocument = async (doc: any) => {
    const { data } = await supabase.storage.from('soin-direct-documents').createSignedUrl(doc.s3_cle, 300);
    if (!data?.signedUrl) { toast.error('Impossible de générer le lien'); return; }

    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user!.id, p_type_acteur: 'SOIGNANT', p_action: 'DOCUMENT_CONSULTATION',
      p_type_ressource: 'document', p_id_ressource: doc.id, p_cle_s3: doc.s3_cle,
      p_details: { type_document: doc.type_document }, p_ip: null, p_navigateur: navigator.userAgent,
    });
    window.open(data.signedUrl, '_blank');
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

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  // Organize: critiques first, then optionnels
  const typesOrdonnes = [
    ...documentsRequis.filter(d => d.est_critique),
    ...documentsRequis.filter(d => !d.est_critique),
  ];

  return (
    <LayoutApp role="SOIGNANT">
      <h1 className="text-xl font-bold text-foreground mb-1">📂 Mes documents professionnels</h1>
      <p className="text-sm text-muted-foreground mb-4">
        Téléversez et gérez vos documents. Les documents marqués ★ sont obligatoires pour postuler aux missions.
      </p>

      {/* Attestation sur l'honneur */}
      {user && <AttestationSante userId={user.id} />}

      {/* Alertes expiration */}
      {documentsExpirantBientot.map(d => (
        <div key={d.id} className="bg-destructive/5 border border-destructive/20 rounded-xl p-3 mb-3 flex items-start gap-2">
          <Clock className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
          <p className="text-xs text-destructive">
            ⏰ Votre {TYPES_DOCUMENTS[d.type_document] || d.type_document} expire dans {differenceInDays(new Date(d.valide_jusqua), new Date())} jours ({format(new Date(d.valide_jusqua), 'd MMM yyyy', { locale: fr })}).{' '}
            <button onClick={() => { setTeleversementType(d.type_document); setTeleversementExpiration(true); }} className="text-primary font-medium hover:underline">Mettre à jour →</button>
          </p>
        </div>
      ))}

      {/* Jauge globale */}
      {completionDocs >= 100 ? (
        <div className="rounded-2xl bg-emerald-50 border border-emerald-200 p-4 mb-4 text-center">
          <p className="text-sm font-semibold text-emerald-700">✅ Tous vos documents obligatoires sont à jour</p>
        </div>
      ) : (
        <div className="rounded-2xl bg-amber-50 border border-amber-200 p-4 mb-4">
          <div className="flex items-center justify-between mb-2">
            <p className="text-sm font-semibold text-foreground">{docsRequis.length - docsValides.length} document(s) manquant(s) ou expiré(s)</p>
            <span className="text-xs text-amber-700 font-medium">⚠️ Vous ne pouvez pas postuler</span>
          </div>
          <JaugeProgression valeur={docsValides.length} max={docsRequis.length} couleurBarre="bg-amber-500" couleurFond="bg-amber-100" />
        </div>
      )}

      {/* Liste des documents */}
      <div className="space-y-3">
        {typesOrdonnes.map((requis, idx) => {
          const isCritique = requis.est_critique;
          const doc = mesDocuments.find(d => d.type_document === requis.type_document);
          const statut = doc ? STATUTS_VERIFICATION[doc.statut_verification] : null;
          const estExpire = doc?.valide_jusqua && new Date(doc.valide_jusqua) < new Date();
          const estRejete = doc?.statut_verification === 'REJETE';

          // Divider avant les optionnels
          if (idx > 0 && !isCritique && documentsRequis[idx - 1]?.est_critique) {
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
                    {statut && <span className={`badge-base ${statut.couleur} text-[10px] mt-1`}>{statut.label}</span>}
                    {doc.valide_jusqua && (
                      <p className="text-[10px] text-muted-foreground mt-1">Valide jusqu'au {format(new Date(doc.valide_jusqua), 'd MMM yyyy', { locale: fr })}</p>
                    )}
                    <div className="flex gap-2 mt-2">
                      <button onClick={() => voirDocument(doc)} className="text-xs text-primary font-medium hover:underline">Voir</button>
                      <button onClick={() => { setTeleversementType(requis.type_document); setTeleversementExpiration(!!requis.a_expiration); }} className="text-xs text-primary font-medium hover:underline">Remplacer</button>
                      <button onClick={() => setSuppDocId(doc.id)} className="text-xs text-destructive font-medium hover:underline">Supprimer</button>
                    </div>
                  </div>
                ) : estExpire ? (
                  <div className="mt-2">
                    <p className="text-xs text-destructive">⏰ Expiré depuis le {format(new Date(doc.valide_jusqua), 'd MMM yyyy', { locale: fr })}</p>
                    <span className="badge-base bg-destructive/10 text-destructive text-[10px] mt-1">Expiré ⏰</span>
                    <div className="flex gap-2 mt-2">
                      <button onClick={() => { setTeleversementType(requis.type_document); setTeleversementExpiration(!!requis.a_expiration); }} className="text-xs text-primary font-medium hover:underline">Téléverser un nouveau document</button>
                    </div>
                  </div>
                ) : estRejete ? (
                  <div className="mt-2">
                    <p className="text-xs text-destructive">✗ Rejeté {doc.motif_rejet && `— Motif : "${doc.motif_rejet}"`}</p>
                    <span className="badge-base bg-destructive/10 text-destructive text-[10px] mt-1">Rejeté ✗</span>
                    <div className="flex gap-2 mt-2">
                      <button onClick={() => { setTeleversementType(requis.type_document); setTeleversementExpiration(!!requis.a_expiration); }} className="text-xs text-primary font-medium hover:underline">Téléverser un nouveau document</button>
                    </div>
                  </div>
                ) : (
                  <div className="mt-2">
                    <p className="text-xs text-amber-600">⚠️ Document non téléversé</p>
                    <div className="flex gap-2 mt-2">
                      <button onClick={() => { setTeleversementType(requis.type_document); setTeleversementExpiration(!!requis.a_expiration); }} className="btn-primary text-xs px-3 py-1.5">+ Téléverser</button>
                    </div>
                  </div>
                )}
              </div>
            );
          }
        })}
      </div>

      {/* Modal televersement */}
      {televersementType && (
        <ModalTeleversement
          typeDocument={televersementType}
          aExpiration={televersementExpiration}
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
    </LayoutApp>
  );
}
