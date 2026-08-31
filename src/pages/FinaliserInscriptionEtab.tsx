import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, CheckCircle, Upload, Loader2, ArrowLeft, Shield, AlertTriangle } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { Button } from '@/components/ui/button';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Checkbox } from '@/components/ui/checkbox';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { verifierFichierDocument } from '@/lib/documentUpload';
import { toast } from 'sonner';
import SignatureCanvas from '@/components/SignatureCanvas';
import { buildContratServiceTexte, CONTRAT_SERVICE_VERSION, hashContratTexte } from '@/constantes/contratServiceEtablissement';

interface EtablissementInscription {
  nom: string;
  siret: string;
  type: string;
  adresse_rue: string;
  adresse_code_postal: string;
  adresse_ville: string;
  email_contact: string;
  contrat_service_signe: boolean;
  contrat_service_signe_le: string | null;
  rib_s3_key: string | null;
  statut_verification: string | null;
  peut_publier_missions: boolean | null;
  siret_verifie: boolean | null;
  finess: string | null;
  finess_verifie: boolean | null;
  representant_identite_verifiee: boolean | null;
  rattachement_verifie: boolean | null;
}

function renderMarkdown(texte: string) {
  const lines = texte.split('\n');
  const elements: JSX.Element[] = [];
  let listBuffer: string[] = [];
  let key = 0;
  const flushList = () => {
    if (listBuffer.length > 0) {
      elements.push(
        <ol key={key++} className="list-decimal list-inside space-y-1.5 text-sm text-foreground ml-2 mb-3">
          {listBuffer.map((item, i) => (
            <li key={i} dangerouslySetInnerHTML={{ __html: item.replace(/[<>]/g, m => m === '<' ? '&lt;' : '&gt;').replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') }} />
          ))}
        </ol>,
      );
      listBuffer = [];
    }
  };
  for (const line of lines) {
    if (line.startsWith('# ')) { flushList(); elements.push(<h1 key={key++} className="text-xl font-bold text-foreground mb-3 mt-2">{line.substring(2)}</h1>); }
    else if (line.startsWith('## ')) { flushList(); elements.push(<h2 key={key++} className="text-base font-bold text-foreground mt-5 mb-2">{line.substring(3)}</h2>); }
    else if (line.match(/^\d+\.\s/)) { listBuffer.push(line.replace(/^\d+\.\s/, '')); }
    else if (line.startsWith('- ')) { listBuffer.push(line.substring(2)); }
    else if (line.trim() === '---') { flushList(); elements.push(<hr key={key++} className="border-border my-4" />); }
    else if (line.trim() === '') { flushList(); }
    else { flushList(); elements.push(<p key={key++} className="text-sm text-foreground mb-2 leading-relaxed" dangerouslySetInnerHTML={{ __html: line.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') }} />); }
  }
  flushList();
  return elements;
}

export default function FinaliserInscriptionEtab() {
  usePageTitle('Finaliser inscription');
  const navigate = useNavigate();
  const { user } = useAuth();

  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [etabInfo, setEtabInfo] = useState<EtablissementInscription | null>(null);
  const [step, setStep] = useState<1 | 2>(1);

  // Step 1 state
  const [contratSigne, setContratSigne] = useState(false);
  const [hasScrolled, setHasScrolled] = useState(false);
  const [accepte, setAccepte] = useState(false);
  const [certifie, setCertifie] = useState(false);
  const [signing, setSigning] = useState(false);
  const signLockRef = useRef(false);

  // Step 2 state
  const [ribFile, setRibFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [ribUploaded, setRibUploaded] = useState(false);
  const uploadLockRef = useRef(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data, error } = await supabase
        .from('etablissements')
        .select('nom, siret, type, adresse_rue, adresse_code_postal, adresse_ville, email_contact, contrat_service_signe, contrat_service_signe_le, rib_s3_key, statut_verification, peut_publier_missions, siret_verifie, finess, finess_verifie, representant_identite_verifiee, rattachement_verifie')
        .eq('id', user.id)
        .maybeSingle();
      if (error) {
        setLoadError('Impossible de charger l’état de votre inscription. Réessayez dans quelques instants.');
        setLoading(false);
        return;
      }
      if (!data) {
        setLoadError('Profil établissement introuvable.');
        setLoading(false);
        return;
      }
      if (data) {
        const info = data as unknown as EtablissementInscription;
        setEtabInfo(info);
        const signe = !!info.contrat_service_signe;
        const ribOk = !!(info.rib_s3_key && info.rib_s3_key !== 'legacy/auto-backfill');
        setContratSigne(signe);
        setRibUploaded(ribOk);
        // Step 2 dès que contrat signé (le user upload son RIB ensuite)
        if (signe) setStep(2);
      }
      setLoading(false);
    })();
  }, [user]);

  const contratTexte = useMemo(
    () => buildContratServiceTexte(etabInfo || {}),
    [etabInfo],
  );

  const handleScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const el = e.currentTarget;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 50) setHasScrolled(true);
  };

  const signerContrat = async (signatureBase64: string) => {
    if (!user) return;
    if (signLockRef.current) return; // synchronous lock anti double-clic
    signLockRef.current = true;
    setSigning(true);
    try {
      // Upload signature image (PNG base64 → bucket jolene-documents)
      let signatureS3Key: string | null = null;
      try {
        const matches = signatureBase64.match(/^data:image\/(\w+);base64,(.+)$/);
        if (matches) {
          const ext = matches[1] === 'jpeg' ? 'jpg' : matches[1];
          const binary = atob(matches[2]);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
          const blob = new Blob([bytes], { type: `image/${matches[1]}` });
          const path = `${user.id}/signatures/contrat-service-${Date.now()}.${ext}`;
          const { error: upErr } = await supabase.storage
            .from('jolene-documents')
            .upload(path, blob, { upsert: false, contentType: `image/${matches[1]}` });
          if (upErr) throw upErr;
          signatureS3Key = path;
        }
      } catch {
        throw new Error("La signature dessinée n'a pas pu être enregistrée. Réessayez.");
      }
      if (!signatureS3Key) throw new Error('Une signature dessinée valide est obligatoire.');

      const hash = await hashContratTexte(contratTexte);
      // L'IP réelle est récupérée côté serveur (RPC SECURITY DEFINER lit
      // current_setting('request.headers')::jsonb->>'x-forwarded-for' ou
      // 'cf-connecting-ip'). Passer '' depuis le frontend est safe : la
      // RPC override avec l'IP serveur si présente. Cf. fn_signer_contrat_service.
      const { data, error } = await supabase.rpc('fn_signer_contrat_service', {
        p_version: CONTRAT_SERVICE_VERSION,
        p_ip: '',
        p_user_agent: navigator.userAgent,
        p_contenu_hash: hash,
        p_signature_s3_key: signatureS3Key,
      });
      if (error) throw error;
      const result = data && typeof data === 'object' && !Array.isArray(data)
        ? data as Record<string, unknown>
        : null;
      if (result?.success === false) {
        throw new Error(typeof result.error === 'string' ? result.error : 'Signature refusée.');
      }
      toast.success('Contrat de service signé avec succès !');
      setContratSigne(true);
      setStep(2);
    } catch {
      toast.error('La signature n’a pas pu être enregistrée. Réessayez.');
    } finally {
      signLockRef.current = false;
      setSigning(false);
    }
  };

  const uploadRib = async () => {
    if (!ribFile || !user) return;
    if (uploadLockRef.current) return;
    const validation = await verifierFichierDocument(ribFile, { maxBytes: 5 * 1024 * 1024 });
    if (validation.ok === false) {
      toast.error(validation.message);
      return;
    }

    uploadLockRef.current = true;
    setUploading(true);
    try {
      // Une nouvelle clé évite tout écrasement d'une preuve déjà vérifiée et
      // reste compatible avec la politique Storage immuable.
      const path = `${user.id}/rib-etablissement-${Date.now()}-${globalThis.crypto.randomUUID()}.${validation.extension}`;
      const ancienRibKey = etabInfo?.rib_s3_key && etabInfo.rib_s3_key !== 'legacy/auto-backfill'
        ? etabInfo.rib_s3_key
        : null;
      const { error: upErr } = await supabase.storage
        .from('jolene-documents')
        .upload(path, ribFile, { upsert: false, contentType: validation.mime });
      if (upErr) throw upErr;

      const { data: updated, error: updErr } = await supabase
        .from('etablissements')
        .update({ rib_s3_key: path })
        .eq('id', user.id)
        .select('id')
        .maybeSingle();
      if (updErr || !updated) {
        await supabase.functions.invoke('verify-rib-etablissement', {
          body: { action: 'cleanup_orphan', etablissement_id: user.id, rib_s3_key: path },
        });
        throw updErr || new Error('Établissement introuvable');
      }
      if (ancienRibKey && ancienRibKey !== path) {
        void supabase.functions.invoke('verify-rib-etablissement', {
          body: { action: 'cleanup_orphan', etablissement_id: user.id, rib_s3_key: ancienRibKey },
        });
      }

      // Le téléversement et la validation sont deux états distincts : l'échec
      // de l'analyse ne transforme jamais le RIB en preuve vérifiée.
      const { data: verification, error: verificationError } = await supabase.functions.invoke('verify-rib-etablissement', {
        body: { etablissement_id: user.id },
      });

      setRibUploaded(true);
      if (verificationError || verification?.ok === false) {
        toast.warning('RIB enregistré. Sa vérification reste en cours.');
      } else if (verification?.coherent === true) {
        toast.success('RIB enregistré et contrôlé.');
      } else {
        toast.success('RIB enregistré. Une revue peut encore être nécessaire.');
      }

      setTimeout(() => {
        navigate('/etablissement/activer');
      }, 1200);
    } catch {
      toast.error('Le RIB n’a pas pu être enregistré. Réessayez.');
    } finally {
      uploadLockRef.current = false;
      setUploading(false);
    }
  };

  const preparationAdministrativeTerminee = contratSigne && ribUploaded;
  const activationComplete = !!etabInfo
    && contratSigne
    && etabInfo.statut_verification === 'VERIFIE'
    && etabInfo.peut_publier_missions === true
    && etabInfo.siret_verifie === true
    && !!etabInfo.finess
    && etabInfo.finess_verifie === true
    && etabInfo.representant_identite_verifiee === true
    && etabInfo.rattachement_verifie === true;

  if (loading) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  if (loadError || !etabInfo) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="max-w-xl mx-auto rounded-xl border border-destructive/30 bg-destructive/5 p-5">
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-destructive shrink-0 mt-0.5" aria-hidden="true" />
            <div>
              <h1 className="font-semibold text-foreground">Inscription indisponible</h1>
              <p className="text-sm text-muted-foreground mt-1">{loadError || 'Profil établissement introuvable.'}</p>
              <BoutonY2K size="sm" variant="secondary" className="mt-3" onClick={() => navigate('/etablissement/tableau-de-bord')}>
                Retour au tableau de bord
              </BoutonY2K>
            </div>
          </div>
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="max-w-3xl mx-auto space-y-5">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" className="app-inline-back" onClick={() => navigate(-1)}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
              <Shield className="h-5 w-5 text-primary" /> Finaliser votre inscription
            </h1>
            <p className="text-xs text-muted-foreground">Préparation administrative avant vérification complète</p>
          </div>
        </div>

        {/* Stepper */}
        <div className="flex items-center gap-3">
          <div className={`flex items-center gap-2 px-4 py-2 rounded-full text-sm font-medium ${step === 1 && !contratSigne ? 'bg-primary text-primary-foreground' : contratSigne ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'}`}>
            {contratSigne ? <CheckCircle className="h-4 w-4" /> : <FileText className="h-4 w-4" />}
            1. Contrat de service
          </div>
          <div className="h-px w-8 bg-border" />
          <div className={`flex items-center gap-2 px-4 py-2 rounded-full text-sm font-medium ${step === 2 && !ribUploaded ? 'bg-primary text-primary-foreground' : ribUploaded ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'}`}>
            {ribUploaded ? <CheckCircle className="h-4 w-4" /> : <Upload className="h-4 w-4" />}
            2. RIB
          </div>
        </div>

        {preparationAdministrativeTerminee && (
          <div className={`rounded-xl border-2 p-4 flex items-start gap-3 ${activationComplete ? 'border-success/30 bg-success/5' : 'border-amber-300/60 bg-amber-50/70 dark:bg-amber-950/20'}`}>
            {activationComplete
              ? <CheckCircle className="h-6 w-6 text-success shrink-0 mt-0.5" aria-hidden="true" />
              : <AlertTriangle className="h-6 w-6 text-amber-600 shrink-0 mt-0.5" aria-hidden="true" />}
            <div>
              <p className="font-semibold text-foreground">
                {activationComplete ? 'Établissement vérifié' : 'Préparation administrative terminée'}
              </p>
              <p className="text-sm text-muted-foreground mt-1">
                {activationComplete
                  ? 'Tous les contrôles requis sont validés. Vous pouvez publier des missions.'
                  : 'Le contrat et le RIB sont enregistrés. Le compte reste en cours de vérification tant que le SIRET, le FINESS, l’identité et l’habilitation du représentant ne sont pas tous validés.'}
              </p>
              <div className="flex gap-2 mt-3">
                <BoutonY2K
                  size="sm"
                  variant="secondary"
                  onClick={() => navigate(activationComplete ? '/etablissement/tableau-de-bord' : '/etablissement/activer')}
                >
                  {activationComplete ? 'Aller au tableau de bord' : 'Poursuivre la vérification'}
                </BoutonY2K>
              </div>
            </div>
          </div>
        )}

        {/* Step 1 : Contrat de service */}
        {step === 1 && !contratSigne && (
          <div className="space-y-4">
            <div className="rounded-xl border border-border bg-card p-4">
              <p className="text-sm font-semibold text-foreground mb-3">Contrat de service Jolene — Version {CONTRAT_SERVICE_VERSION}</p>
              <div
                className="max-h-[50vh] overflow-y-auto border border-border rounded-lg p-4 bg-muted/20 text-sm"
                onScroll={handleScroll}
              >
                {renderMarkdown(contratTexte)}
              </div>
              {!hasScrolled && (
                <p className="text-xs text-muted-foreground mt-2 animate-pulse">Veuillez lire le contrat jusqu'au bout pour pouvoir signer.</p>
              )}
            </div>

            <div className="space-y-3">
              <label className="flex items-start gap-3 cursor-pointer">
                <Checkbox checked={accepte} onCheckedChange={v => setAccepte(!!v)} disabled={!hasScrolled} />
                <span className="text-sm text-foreground">J'ai lu et j'accepte le contrat de service Jolene</span>
              </label>
              <label className="flex items-start gap-3 cursor-pointer">
                <Checkbox checked={certifie} onCheckedChange={v => setCertifie(!!v)} disabled={!hasScrolled} />
                <span className="text-sm text-foreground">Je certifie être habilité(e) à engager mon établissement</span>
              </label>
            </div>

            {accepte && certifie && (
              <div className="space-y-3">
                <p className="text-sm font-medium text-foreground">Votre signature :</p>
                <SignatureCanvas onSave={signerContrat} />
                {signing && (
                  <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Loader2 className="h-4 w-4 animate-spin" /> Signature en cours...
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {/* Step 1 done — résumé */}
        {contratSigne && step === 2 && (
          <div className="rounded-xl border border-success/20 bg-success/5 p-3 flex items-center gap-3">
            <CheckCircle className="h-5 w-5 text-success shrink-0" />
            <div className="flex-1">
              <p className="text-sm font-medium text-foreground">Contrat de service signé</p>
              <p className="text-xs text-muted-foreground">
                Version {CONTRAT_SERVICE_VERSION} — signé le {etabInfo?.contrat_service_signe_le ? new Date(etabInfo.contrat_service_signe_le).toLocaleDateString('fr-FR') : 'aujourd\'hui'}
              </p>
            </div>
          </div>
        )}

        {/* Step 2 : Upload RIB */}
        {step === 2 && !ribUploaded && (
          <div className="space-y-4">
            <div className="rounded-xl border border-border bg-card p-4 space-y-3">
              <p className="text-sm font-semibold text-foreground flex items-center gap-2">
                <Upload className="h-4 w-4 text-primary" /> Relevé d'identité bancaire (RIB)
              </p>
              <p className="text-xs text-muted-foreground" id="rib-help">
                Votre RIB est nécessaire pour les opérations de paiement sur la plateforme (prélèvements commission, virements). Format PDF, JPEG, PNG ou WebP (max 5 Mo). Donnée chiffrée et accessible uniquement par l'admin Jolene.
              </p>
              <input
                id="rib-file-input"
                type="file"
                accept="application/pdf,image/jpeg,image/png,image/webp"
                onChange={async e => {
                  const selected = e.target.files?.[0] || null;
                  if (!selected) { setRibFile(null); return; }
                  const validation = await verifierFichierDocument(selected, { maxBytes: 5 * 1024 * 1024 });
                  if (validation.ok === false) {
                    setRibFile(null);
                    toast.error(validation.message);
                    e.target.value = '';
                    return;
                  }
                  setRibFile(selected);
                }}
                className="block w-full text-sm text-foreground file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-primary/10 file:text-primary hover:file:bg-primary/20 cursor-pointer"
                aria-label="Téléverser votre RIB (PDF, JPEG, PNG ou WebP, 5 Mo max)"
                aria-describedby="rib-help"
              />
              {ribFile && (
                <p className="text-xs text-muted-foreground">
                  Fichier sélectionné : {ribFile.name} ({(ribFile.size / 1024).toFixed(0)} Ko)
                </p>
              )}
              <BoutonY2K onClick={uploadRib} disabled={!ribFile || uploading} className="gap-2">
                {uploading && <Loader2 className="h-4 w-4 animate-spin" />}
                <Upload className="h-4 w-4" /> Enregistrer le RIB
              </BoutonY2K>
            </div>
          </div>
        )}

        {/* Step 2 done */}
        {ribUploaded && step === 2 && !preparationAdministrativeTerminee && (
          <div className="rounded-xl border border-success/20 bg-success/5 p-3 flex items-center gap-3">
            <CheckCircle className="h-5 w-5 text-success shrink-0" />
            <p className="text-sm font-medium text-foreground">RIB enregistré</p>
          </div>
        )}
      </div>
    </LayoutApp>
  );
}
