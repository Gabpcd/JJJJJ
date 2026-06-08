import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FileText, CheckCircle, Upload, Loader2, ArrowLeft, Shield, Download } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { Button } from '@/components/ui/button';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Checkbox } from '@/components/ui/checkbox';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import SignatureCanvas from '@/components/SignatureCanvas';
import { buildContratServiceTexte, CONTRAT_SERVICE_VERSION, hashContratTexte } from '@/constantes/contratServiceEtablissement';

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
  const [etabInfo, setEtabInfo] = useState<any>(null);
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
      const { data } = await supabase
        .from('etablissements')
        .select('nom, siret, type, adresse_rue, adresse_code_postal, adresse_ville, email_contact, contrat_service_signe, contrat_service_signe_le, rib_s3_key')
        .eq('id', user.id)
        .maybeSingle();
      if (data) {
        setEtabInfo(data);
        const signe = !!(data as any).contrat_service_signe;
        const ribOk = !!((data as any).rib_s3_key && (data as any).rib_s3_key !== 'legacy/auto-backfill');
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
          if (!upErr) signatureS3Key = path;
        }
      } catch {
        // Best-effort : si upload signature échoue, continue sans bloquer
      }

      const hash = await hashContratTexte(contratTexte);
      // L'IP réelle est récupérée côté serveur (RPC SECURITY DEFINER lit
      // current_setting('request.headers')::jsonb->>'x-forwarded-for' ou
      // 'cf-connecting-ip'). Passer '' depuis le frontend est safe : la
      // RPC override avec l'IP serveur si présente. Cf. fn_signer_contrat_service.
      const { data, error } = await supabase.rpc('fn_signer_contrat_service' as any, {
        p_version: CONTRAT_SERVICE_VERSION,
        p_ip: '',
        p_user_agent: navigator.userAgent,
        p_contenu_hash: hash,
        p_signature_s3_key: signatureS3Key,
      });
      if (error) throw error;
      if ((data as any)?.success === false) throw new Error((data as any)?.error);
      toast.success('Contrat de service signé avec succès !');
      setContratSigne(true);
      setStep(2);
    } catch (err: any) {
      toast.error(err?.message || 'Erreur lors de la signature');
    } finally {
      signLockRef.current = false;
      setSigning(false);
    }
  };

  const uploadRib = async () => {
    if (!ribFile || !user) return;
    if (uploadLockRef.current) return;
    uploadLockRef.current = true;
    const ext = ribFile.name.split('.').pop()?.toLowerCase() || 'pdf';
    const allowed = ['pdf', 'jpg', 'jpeg', 'png'];
    if (!allowed.includes(ext)) {
      toast.error('Format accepté : PDF, JPG ou PNG');
      return;
    }
    if (ribFile.size > 5 * 1024 * 1024) {
      toast.error('Fichier trop volumineux (max 5 Mo)');
      return;
    }

    setUploading(true);
    try {
      const path = `${user.id}/rib.${ext}`;
      const { error: upErr } = await supabase.storage
        .from('jolene-documents')
        .upload(path, ribFile, { upsert: true });
      if (upErr) throw upErr;

      const { error: updErr } = await supabase
        .from('etablissements')
        .update({ rib_s3_key: path } as any)
        .eq('id', user.id);
      if (updErr) throw updErr;

      toast.success('RIB uploadé avec succès !');
      setRibUploaded(true);

      setTimeout(() => {
        toast.success('Inscription finalisée ! Bienvenue sur Jolene.');
        navigate('/etablissement/tableau-de-bord');
      }, 1200);
    } catch (err: any) {
      toast.error(err?.message || 'Erreur lors de l\'upload');
    } finally {
      uploadLockRef.current = false;
      setUploading(false);
    }
  };

  const allDone = contratSigne && ribUploaded;

  if (loading) {
    return (
      <LayoutApp role="ADMIN_ETABLISSEMENT">
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      </LayoutApp>
    );
  }

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="max-w-3xl mx-auto space-y-5">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={() => navigate(-1)}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
              <Shield className="h-5 w-5 text-primary" /> Finaliser votre inscription
            </h1>
            <p className="text-xs text-muted-foreground">2 étapes pour commencer à publier des missions</p>
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

        {allDone && (
          <div className="rounded-xl border-2 border-success/30 bg-success/5 p-4 flex items-start gap-3">
            <CheckCircle className="h-6 w-6 text-success shrink-0 mt-0.5" />
            <div>
              <p className="font-semibold text-foreground">Inscription finalisée</p>
              <p className="text-sm text-muted-foreground mt-1">
                Votre contrat de service est signé et votre RIB est enregistré. Vous pouvez publier des missions.
              </p>
              <div className="flex gap-2 mt-3">
                <BoutonY2K size="sm" variant="secondary" onClick={() => navigate('/etablissement/tableau-de-bord')}>
                  Aller au dashboard
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
                Votre RIB est nécessaire pour les opérations de paiement sur la plateforme (prélèvements commission, virements). Format PDF, JPG ou PNG (max 5 Mo). Donnée chiffrée et accessible uniquement par l'admin Jolene.
              </p>
              <input
                id="rib-file-input"
                type="file"
                accept=".pdf,.jpg,.jpeg,.png"
                onChange={e => setRibFile(e.target.files?.[0] || null)}
                className="block w-full text-sm text-foreground file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-primary/10 file:text-primary hover:file:bg-primary/20 cursor-pointer"
                aria-label="Téléverser votre RIB (PDF, JPG ou PNG, 5 Mo max)"
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
        {ribUploaded && step === 2 && !allDone && (
          <div className="rounded-xl border border-success/20 bg-success/5 p-3 flex items-center gap-3">
            <CheckCircle className="h-5 w-5 text-success shrink-0" />
            <p className="text-sm font-medium text-foreground">RIB enregistré</p>
          </div>
        )}
      </div>
    </LayoutApp>
  );
}
